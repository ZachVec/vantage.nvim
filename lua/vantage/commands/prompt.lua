--- The prompt flow (terminal token): pick a Prompt, render it against the
--- focused Agent's context, and type it into the Agent's input. The placeholder
--- vocabulary is this module's own resolvers: one per known placeholder.
local Bridge = require("vantage.backend.bridge")
local Config = require("vantage.config")
local Picker = require("vantage.frontend.picker")
local Review = require("vantage.frontend.review")
local Terminal = require("vantage.frontend.terminal")
local Util = require("vantage.util")

local M = {}

---@class vantage.PromptCtx
---@field buf integer context buffer
---@field row integer 1-based cursor row
---@field cwd string focused Agent cwd (relativization base)

--- Monotonic stamp for the most-recently-visited window, read by context
--- resolution.
local visit_counter = 0

--- One resolver per placeholder. `tool` is the focused Tool's reference
--- dialect; nil spells the default. A nil result fails the render.
---@type table<string, fun(ctx: vantage.PromptCtx, tool: string?): string?>
local resolvers = {
  file = function(ctx, tool)
    return Config.tool_reference(tool, ctx.cwd, vim.api.nvim_buf_get_name(ctx.buf))
  end,
  line = function(ctx, tool)
    return Config.tool_reference(tool, ctx.cwd, vim.api.nvim_buf_get_name(ctx.buf), ctx.row)
  end,
  reviews = function(ctx, tool)
    return Review.render(ctx.cwd, tool)
  end,
}

--- The placeholder vocabulary: the resolvers' own keys, so a name can never be
--- known without something to resolve it. `Util.interpolate` leaves an unknown
--- token literal; `setup` warns about a configured template that names one.
---@type table<string, boolean>
local PLACEHOLDERS = {}
for name in pairs(resolvers) do
  PLACEHOLDERS[name] = true
end

--- Track the last non-terminal window for Prompt context resolution, and warn
--- about a configured template naming a placeholder no resolver knows
--- (`Util.interpolate` would type it literally). The vocabulary is the
--- resolvers' keys, and `health.lua` may not import this layer, so the check
--- runs here, on the applied config. A non-string template is not this check's
--- business; it fails when it is sent.
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

  local unknown = {}
  for _, template in pairs(Config.options.prompts) do
    if type(template) == "string" then
      for token in template:gmatch("{([%w_]+)}") do
        if not PLACEHOLDERS[token] then
          unknown[token] = true
        end
      end
    end
  end
  local names = vim.tbl_map(function(token)
    return "{" .. token .. "}"
  end, vim.tbl_keys(unknown))
  if #names > 0 then
    table.sort(names)
    Util.warn(("prompts: unknown placeholder(s) %s"):format(table.concat(names, ", ")))
  end
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

--- Render a template against `ctx`, spelling every location reference through
--- the focused Tool's `format` hook (defaulting to the plain `file` and
--- space-joined `loc` form). Returns the rendered text, or nil (with the
--- failing placeholder name) when any placeholder resolved empty.
---@param template string
---@param ctx vantage.PromptCtx
---@param tool? string the focused Tool's reference dialect; nil spells the default
---@return string?
---@return string?
function M.render(template, ctx, tool)
  local out = {}
  for _, line in ipairs(vim.split(template, "\n", { plain = true })) do
    local rendered, failed = Util.interpolate(line, PLACEHOLDERS, function(name)
      return resolvers[name](ctx, tool)
    end)
    if rendered == nil then
      return nil, failed
    end
    out[#out + 1] = rendered
  end
  return table.concat(out, "\n")
end

--- Render a prompt against the focused Agent's context and type it into the
--- Agent's input (no auto-submit).
---@param name string
local function send_prompt(name)
  local focused, err = Bridge.focus(Terminal.pid())
  if not focused then
    Util.warn(err or "no focused agent")
    return
  end
  local template = Config.options.prompts[name]
  local text, failed = M.render(template, M.context(focused), focused.tool)
  if text == nil then
    Util.warn(("prompt '%s' skipped: {%s} resolved empty"):format(name, failed))
    return
  end
  local ok, send_err = Bridge.send(focused, text)
  if not ok then
    Util.warn(("prompt '%s': %s"):format(name, send_err or "failed to send"))
    return
  end
  if template:find("{reviews}", 1, true) and Config.options.reviews.clear_on_send then
    Review.clear()
  end
end

--- Pick a prompt name through the Picker's plain-select form and send it to
--- the focused Agent. Handing the window back when the pick closes is the
--- Picker implementation's job (see `vantage.PickerImpl`).
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
  Picker.pick_plain(names, { prompt = "Prompt: " }, function(name)
    if name then
      send_prompt(name)
    end
  end)
end

return M
