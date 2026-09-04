--- Frontend selection orchestration: builds the rich items each picker flow
--- renders and assembles the PickSpec the picker implementations consume.
--- The picker implementations stay presentation-only and depend on nothing but
--- their engine; all domain assembly lives here.
---
--- A PickSpec field is an *input* to the picker (data, preview content, an
--- environment fact, an in-flight action); the chosen item is delivered
--- through the positional `on_choice` (the picker's single result channel),
--- and the picker's synchronous boolean return reports whether the list was
--- empty.
local Annotation = require("vantage.annotation")
local Backend = require("vantage.backend")
local Client = require("vantage.client")
local Config = require("vantage.config")
local Util = require("vantage.util")

local M = {}

--- Toggle row glyphs (Nerd Fonts; nf-fa-toggle_on and nf-fa-toggle_off): a
--- running Agent row leads with the "on" icon, a trailing Tool row (which
--- would create a new Agent) with the "off" one. Built with nr2char rather
--- than literal escapes (Lua 5.1 has no \u{…}). Two spaces keep the icon clear
--- of the text.
local AGENT_ICON = vim.fn.nr2char(0xF205) .. "  "
local TOOL_ICON = vim.fn.nr2char(0xF204) .. "  "

--- The picker prompt glyph (U+F105, e.g. Nerd Font), passed to the picker as
--- the spec's `prompt` so implementations need no Vantage module.
local PROMPT = Util.picker_prompt

---@param agent vantage.Agent
---@return string
local function format_agent(agent)
  return ("%s · %s · %s"):format(agent.tool or agent.cmd, agent.group, Util.tilde(agent.cwd))
end

--- The Agent rows' ascending order: group, absolute cwd, tool name (the
--- `cli.tools` key; `cmd` as the nil fallback), then window id (@N) by
--- creation order for exact ties.
---@param left vantage.Agent
---@param right vantage.Agent
---@return boolean
local function agent_order(left, right)
  if left.group ~= right.group then
    return left.group < right.group
  end
  if left.cwd ~= right.cwd then
    return left.cwd < right.cwd
  end
  local left_tool = left.tool or left.cmd
  local right_tool = right.tool or right.cmd
  if left_tool ~= right_tool then
    return left_tool < right_tool
  end
  -- @N window ids sort numerically; a malformed id (never produced by the
  -- tmux driver) degrades to 0 so the comparator stays total.
  local left_id = tonumber(left.target:match("^@(%d+)$")) or 0
  local right_id = tonumber(right.target:match("^@(%d+)$")) or 0
  return left_id < right_id
end

--- The window predicate for "invoked from the vantage terminal window": the
--- terminal is open and is the current window (the window the cursor was last
--- in). An invoke-time fact — the snacks picker consumes it (via the spec, or
--- via `pick_plain`'s opts) to decide whether to re-enter terminal mode on
--- close.
---@return boolean
function M.invoked_from_terminal()
  return Client.is_open() and vim.api.nvim_get_current_win() == Client.window
end

--- The cwd to relativize against: the focused Agent's cwd, else the current
--- window's local cwd. Shared by the annotation preview and the note float
--- title.
---@return string
function M.focused_cwd()
  local agent = Client.last_agent_alive()
  return agent and agent.cwd or Util.cwd()
end

--- Agent-picker items: the focused Agent first (marked ` (focused)`, exempt
--- from the ordering), then every Agent sorted by group, cwd, tool name, then
--- one Tool row per configured `cli.tools` key (sorted) to create a new
--- Agent. May be empty.
---@param focused vantage.Agent?
---@return { kind: "agent"|"tool", agent?: vantage.Agent, tool?: string, focused?: boolean, text: string }[]
local function agent_items(focused)
  local agents = Backend.get().list()
  local items = {}
  if focused then
    items[#items + 1] = {
      kind = "agent",
      agent = focused,
      focused = true,
      text = AGENT_ICON .. format_agent(focused) .. " (focused)",
    }
  end
  table.sort(agents, agent_order)
  for _, agent in ipairs(agents) do
    if not focused or agent.target ~= focused.target then
      items[#items + 1] = { kind = "agent", agent = agent, text = AGENT_ICON .. format_agent(agent) }
    end
  end
  local tools = {}
  for name in pairs(Config.options.cli.tools) do
    tools[#tools + 1] = name
  end
  table.sort(tools)
  for _, name in ipairs(tools) do
    items[#items + 1] = { kind = "tool", tool = name, text = TOOL_ICON .. name }
  end
  return items
end

--- Agents (as { target, agent }) + Groups (as { target }) to kill. May be empty.
---@return { target: string, agent?: vantage.Agent, text: string }[]
local function kill_items()
  local items = {}
  for _, agent in ipairs(Backend.get().list()) do
    items[#items + 1] = { target = agent.target, agent = agent, text = format_agent(agent) }
  end
  for _, group in ipairs(Backend.get().groups()) do
    items[#items + 1] = { target = group, text = ("group %s"):format(group) }
  end
  return items
end

--- Annotations (as { annotation, text }). May be empty.
---@return { annotation: vantage.Annotation, text: string }[]
local function annotation_items()
  local items = {}
  for _, annotation in ipairs(Annotation.collect()) do
    local path = Util.tilde(vim.api.nvim_buf_get_name(annotation.buf) or "")
    local first = (vim.split(annotation.note, "\n", { plain = true })[1] or ""):gsub("%s+", " ")
    items[#items + 1] = {
      annotation = annotation,
      text = ("%s:L%d-%d  %s"):format(path, annotation.start_row, annotation.end_row, first),
    }
  end
  return items
end

--- Preview content for an Agent/Tool item: the Agent's pane as plain-text
--- lines, or nil for a Tool row (which has no Agent) — nothing to preview.
---@param item table
---@return string[]?
local function pane_preview(item)
  if not item.agent then
    return nil
  end
  return Backend.get().capture_pane(item.agent.target)
end

--- Preview content for an annotation item: the configured `item` template
--- (WYSIWYG), split into lines.
---@param item table
---@return string[]
local function annotation_preview(item)
  return vim.split(Annotation.render_item(item.annotation, M.focused_cwd()), "\n")
end

--- The Agent-list selection spec.
---@return vantage.PickSpec
function M.agent_spec()
  local from_terminal = M.invoked_from_terminal()
  local focused = from_terminal and Client.last_agent_alive() or nil
  return {
    prompt = PROMPT,
    items_provider = function()
      return agent_items(focused)
    end,
    preview = pane_preview,
    invoked_from_terminal = from_terminal,
  }
end

--- The kill-list selection spec.
---@return vantage.PickSpec
function M.kill_spec()
  return {
    prompt = PROMPT,
    items_provider = kill_items,
    preview = pane_preview,
    invoked_from_terminal = M.invoked_from_terminal(),
  }
end

--- The annotation-list selection spec. `on_delete` removes the chosen
--- annotation; the picker re-reads `items_provider` afterwards and closes
--- when nothing remains.
---@return vantage.PickSpec
function M.annotation_spec()
  return {
    prompt = PROMPT,
    items_provider = annotation_items,
    preview = annotation_preview,
    invoked_from_terminal = M.invoked_from_terminal(),
    on_delete = function(annotation)
      Annotation.delete(annotation.buf, annotation.id)
    end,
  }
end

return M
