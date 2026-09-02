--- Prompt domain: named Templates and Actions typed into a focused Agent's input.
---
--- A Template is a string under `setup { prompts = { name = "…" } }`, expanded
--- against the current context before being sent. Placeholders: `{file}`,
--- `{line}`, `{function}`, `{class}` render Claude-style location references
--- relative to the focused Agent's cwd; `{annotations}` renders all accumulated
--- Annotations.
---
--- An Action is a built-in prompt (`files`, `buffers`) that opens a picker and
--- types the selected location references; see `M.actions` / `M.render_paths`.
local M = {}

local Util = require("vantage.util")

---@class vantage.PromptCtx
---@field buf integer context buffer
---@field row integer 1-based cursor row
---@field col integer 1-based cursor column
---@field cwd string focused Agent cwd (relativization base)

--- Known placeholder names. Anything else is left literal (healthcheck flags it).
local PLACEHOLDERS = { file = true, line = true, ["function"] = true, ["class"] = true, annotations = true }

-- ---------------------------------------------------------------------------
-- Context
-- ---------------------------------------------------------------------------

--- The most-recently-visited non-terminal window, tracked by the `WinEnter`
--- autocmd registered in `config.setup` (per-window `vantage_visit` stamp).
--- Falls back to the current window.
---@return integer window id
local function context_window()
  local wins = vim.tbl_filter(function(w)
    local buf = vim.api.nvim_win_get_buf(w)
    return vim.bo[buf].filetype ~= "vantage_terminal"
  end, vim.api.nvim_list_wins())
  table.sort(wins, function(a, b)
    return (vim.w[a].vantage_visit or 0) > (vim.w[b].vantage_visit or 0)
  end)
  return wins[1] or vim.api.nvim_get_current_win()
end

---@param agent vantage.Agent
---@return vantage.PromptCtx
function M.context(agent)
  local win = context_window()
  local buf = vim.api.nvim_win_get_buf(win)
  local cursor = vim.api.nvim_win_get_cursor(win)
  return { buf = buf, row = cursor[1], col = cursor[2] + 1, cwd = agent.cwd }
end

-- ---------------------------------------------------------------------------
-- Location rendering (Claude-style references)
-- ---------------------------------------------------------------------------

--- "@<path>" with `path` relative to `cwd`; absolute when `path` escapes `cwd`.
---@param cwd string base directory
---@param path string absolute file path
---@return string
function M.relativize(cwd, path)
  return "@" .. Util.relpath(cwd, path)
end

--- "@<path>".
---@param ctx vantage.PromptCtx
---@return string?
local function resolve_file(ctx)
  local name = vim.api.nvim_buf_get_name(ctx.buf)
  if name == nil or name == "" then
    return nil
  end
  return M.relativize(ctx.cwd, name)
end

--- "@<path> :L<row>".
---@param ctx vantage.PromptCtx
---@return string?
local function resolve_line(ctx)
  local name = vim.api.nvim_buf_get_name(ctx.buf)
  if name == nil or name == "" then
    return nil
  end
  return ("%s :L%d"):format(M.relativize(ctx.cwd, name), ctx.row)
end

-- ---------------------------------------------------------------------------
-- {function} / {class}: nvim-treesitter-textobjects
-- ---------------------------------------------------------------------------

--- The name of the treesitter node starting at `row`/`col` (0-based), via the
--- field/identifier heuristic sidekick uses.
---@param buf integer
---@param row integer 0-based
---@param col integer 0-based
---@return string?
local function node_name(buf, row, col)
  local node = vim.treesitter.get_node({ bufnr = buf, pos = { row, col } })
  if not node then
    return nil
  end
  for _, field in ipairs({ "name", "identifier", "field" }) do
    local name_node = node:field(field)[1]
    if name_node then
      local text = vim.treesitter.get_node_text(name_node, buf)
      if text and #text > 0 then
        return text
      end
    end
  end
  for child in node:iter_children() do
    if child:type():match("identifier") then
      local text = vim.treesitter.get_node_text(child, buf)
      if text and #text > 0 then
        return text
      end
    end
  end
  return nil
end

--- The enclosing `@<kind>.outer` textobject at the cursor, or nil when the
--- textobjects plugin/query is unavailable or the cursor is not inside one.
---@param ctx vantage.PromptCtx
---@param kind "function"|"class"
---@return { name?: string, row: integer, col: integer }?
local function textobject(ctx, kind)
  if not vim.api.nvim_buf_is_valid(ctx.buf) then
    return nil
  end
  local ok, shared = pcall(require, "nvim-treesitter-textobjects.shared")
  if not ok then
    return nil
  end
  local ok_parser, parser = pcall(vim.treesitter.get_parser, ctx.buf)
  if not ok_parser or not parser then
    return nil
  end
  parser:parse()
  local lang = parser:lang()
  if not vim.treesitter.query.get(lang, "textobjects") then
    return nil
  end
  local success, range =
    pcall(shared.textobject_at_point, ("@%s.outer"):format(kind), "textobjects", ctx.buf, { ctx.row, ctx.col })
  if not success or not range then
    return nil
  end
  -- Range6 is 0-based [start_row, start_col, start_byte, end_row, end_col, end_byte].
  local name = node_name(ctx.buf, range[1], range[2])
  return { name = name, row = range[1] + 1, col = range[2] + 1 }
end

--- "function|class <name> @<path> :L<row>:C<col>".
---@param ctx vantage.PromptCtx
---@param kind "function"|"class"
---@return string?
local function resolve_symbol(ctx, kind)
  local t = textobject(ctx, kind)
  if not t then
    return nil
  end
  local name = vim.api.nvim_buf_get_name(ctx.buf)
  if name == nil or name == "" then
    return nil
  end
  local prefix = t.name and ("%s %s "):format(kind, t.name) or (kind .. " ")
  return ("%s%s :L%d:C%d"):format(prefix, M.relativize(ctx.cwd, name), t.row, t.col)
end

local resolvers = {
  file = resolve_file,
  line = resolve_line,
  ["function"] = function(ctx)
    return resolve_symbol(ctx, "function")
  end,
  ["class"] = function(ctx)
    return resolve_symbol(ctx, "class")
  end,
  annotations = function(ctx)
    return require("vantage.annotation").render(ctx.cwd)
  end,
}

-- ---------------------------------------------------------------------------
-- Rendering
-- ---------------------------------------------------------------------------

---@param line string
---@param ctx vantage.PromptCtx
---@return string? rendered line, nil when a placeholder resolved empty
---@return string? the placeholder name that failed, when nil is returned
local function render_line(line, ctx)
  local failed
  local out = line:gsub("{([%w_]+)}", function(name)
    if not PLACEHOLDERS[name] then
      return "{" .. name .. "}" -- unknown: leave literal (healthcheck flags it)
    end
    local value = resolvers[name](ctx)
    if value == nil then
      failed = name
      return ""
    end
    return value
  end)
  if failed then
    return nil, failed
  end
  return out
end

--- Render a template against `ctx`. Returns the rendered text, or nil (with the
--- failing placeholder name) when any placeholder resolved empty.
---@param template string
---@param ctx vantage.PromptCtx
---@return string?
---@return string?
function M.render(template, ctx)
  local out = {}
  for _, line in ipairs(vim.split(template, "\n", { plain = true })) do
    local rendered, failed = render_line(line, ctx)
    if rendered == nil then
      return nil, failed
    end
    out[#out + 1] = rendered
  end
  return table.concat(out, "\n")
end

-- ---------------------------------------------------------------------------
-- Actions
-- ---------------------------------------------------------------------------

--- Built-in Action prompts (name -> true). An Action opens a picker and types
--- the selected location references, rather than rendering a template.
--- `:Vantage prompt` offers these only when the configured Picker implements
--- `pick_files`/`pick_buffers` (fzf-lua and snacks; not native).
M.actions = { files = true, buffers = true }

--- Render selected absolute paths as newline-joined location references
--- relative to the focused Agent's cwd.
---@param agent vantage.Agent
---@param paths string[] absolute file paths
---@return string
function M.render_paths(agent, paths)
  local refs = {}
  for _, path in ipairs(paths) do
    refs[#refs + 1] = M.relativize(agent.cwd, path)
  end
  return table.concat(refs, "\n")
end

return M
