--- The prompt flow (terminal token): pick a Prompt, render it against the
--- focused Agent's context, and type it into the Agent's input. The placeholder
--- vocabulary is the shared contract in `config.PROMPT_PLACEHOLDERS`.
local Config = require("vantage.config")
local Picker = require("vantage.frontend.picker")
local Review = require("vantage.frontend.review")
local Send = require("vantage.commands.send")
local Util = require("vantage.util")

local M = {}

---@class vantage.PromptCtx
---@field buf integer context buffer
---@field row integer 1-based cursor row
---@field cwd string focused Agent cwd (relativization base)

--- Known placeholder names. Anything else is left literal (health flags it).
local PLACEHOLDERS = Config.PROMPT_PLACEHOLDERS

--- Monotonic stamp for the most-recently-visited window, read by context
--- resolution.
local visit_counter = 0

--- Track the last non-terminal window for Prompt context resolution.
function M.setup()
  visit_counter = 0
  vim.api.nvim_create_augroup("VantageWinVisit", { clear = true })
  vim.api.nvim_create_autocmd("WinEnter", {
    group = "VantageWinVisit",
    callback = function()
      visit_counter = visit_counter + 1
      vim.w[vim.api.nvim_get_current_win()].vantage_visit = visit_counter
    end,
  })
end

--- The most-recently-visited non-terminal window, tracked by the `WinEnter`
--- autocmd registered in `Prompt.setup` (per-window `vantage_visit` stamp).
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
  return { buf = buf, row = cursor[1], cwd = agent.cwd }
end

--- `path` relative to `cwd`; absolute when `path` escapes `cwd`.
---@param cwd string base directory
---@param path string absolute file path
---@return string
local function loc_file(cwd, path)
  return Util.relpath(cwd, path)
end

---@param ctx vantage.PromptCtx
---@param format vantage.ReferenceFormat
---@return string?
local function resolve_file(ctx, format)
  local name = vim.api.nvim_buf_get_name(ctx.buf)
  if name == nil or name == "" then
    return nil
  end
  return format(loc_file(ctx.cwd, name), nil)
end

---@param ctx vantage.PromptCtx
---@param format vantage.ReferenceFormat
---@return string?
local function resolve_line(ctx, format)
  local name = vim.api.nvim_buf_get_name(ctx.buf)
  if name == nil or name == "" then
    return nil
  end
  return format(loc_file(ctx.cwd, name), (":L%d"):format(ctx.row))
end

local resolvers = {
  file = resolve_file,
  line = resolve_line,
  reviews = function(ctx, format)
    return Review.render(ctx.cwd, format)
  end,
}

--- Render a template against `ctx`, spelling every location reference through
--- `format` (the focused Tool's dialect, defaulting to the plain
--- `file` and space-joined `loc` form). Returns the rendered text, or nil
--- (with the failing placeholder name) when any placeholder resolved empty.
---@param template string
---@param ctx vantage.PromptCtx
---@param format? vantage.ReferenceFormat
---@return string?
---@return string?
function M.render(template, ctx, format)
  format = format or Util.reference
  local out = {}
  for _, line in ipairs(vim.split(template, "\n", { plain = true })) do
    local rendered, failed = Util.interpolate(line, PLACEHOLDERS, function(name)
      return resolvers[name](ctx, format)
    end)
    if rendered == nil then
      return nil, failed
    end
    out[#out + 1] = rendered
  end
  return table.concat(out, "\n")
end

--- The known placeholder names — the Prompt vocabulary. health.lua validates
--- user templates against this single source of truth.
M.PLACEHOLDERS = PLACEHOLDERS

--- Render a prompt against the focused Agent's context and type it into the
--- Agent's input (no auto-submit).
---@param name string
local function send_prompt(name)
  local focused, err = Send.focused()
  if not focused then
    Util.warn(err or "failed to resolve the focused agent")
    return
  end
  local template = Config.options.prompts[name]
  local text, failed = M.render(template, M.context(focused), Send.formatter(focused))
  if text == nil then
    Util.warn(("prompt '%s' skipped: {%s} resolved empty"):format(name, failed))
    return
  end
  local ok, send_err = Send.send(focused, text)
  if not ok then
    Util.warn(("prompt '%s': %s"):format(name, send_err or "failed to send"))
    return
  end
  if template:find("{reviews}", 1, true) and Config.options.reviews.clear_on_send then
    Review.clear()
  end
end

--- Pick a prompt name through the Picker's plain-select form and send it to
--- the focused Agent. The current window is restored afterwards so the cursor
--- stays where it was (e.g. the terminal).
function M.run()
  local names = {}
  for name in pairs(Config.options.prompts) do
    -- Short-circuit: only inspect the Review registry when this prompt can
    -- actually need it.
    if name ~= "{reviews}" or #Review.collect() > 0 then
      names[#names + 1] = name
    end
  end
  table.sort(names)
  local win = vim.api.nvim_get_current_win()
  local function restore()
    if vim.api.nvim_win_is_valid(win) then
      vim.api.nvim_set_current_win(win)
    end
  end
  Picker.pick_plain(names, { prompt = "Prompt: " }, function(name)
    if name then
      send_prompt(name)
    end
    -- Restore after the picker engine has finished closing its window; a
    -- synchronous restore can fight the engine's own teardown.
    vim.schedule(restore)
  end)
end

return M
