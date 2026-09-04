--- Shared picker domain: builds the rich items each picker implementation
--- renders (the Agent list and the kill list). Every item carries a `text`
--- display string plus whatever domain fields its callback needs;
--- implementations own only the rendering and the recovery of the chosen item.
--- Plain choices (the Agent-creation Tool/Group steps and :Vantage prompt)
--- pass plain strings to `PickerImpl.pick_plain` and need no builder here.
local Backend = require("vantage.backend")
local Config = require("vantage.config")
local Util = require("vantage.util")

local M = {}

--- The picker prompt: a single angle-right glyph (U+F105, e.g. Nerd Font).
M.prompt = Util.picker_prompt

--- Toggle row glyphs (Nerd Fonts; nf-fa-toggle_on and nf-fa-toggle_off): a
--- running Agent row leads with the "on" icon, a trailing Tool row (which
--- would create a new Agent) with the "off" one. Like the picker prompt
--- glyph, they are built with nr2char rather than literal escapes (Lua 5.1
--- has no \u{…}). Two spaces keep the icon clear of the text.
local AGENT_ICON = vim.fn.nr2char(0xF205) .. "  "
local TOOL_ICON = vim.fn.nr2char(0xF204) .. "  "

---@param agent vantage.Agent
---@return string
function M.format_agent(agent)
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

--- The Agent this picker invocation is "focused on": the Agent the vantage
--- terminal currently shows, when the picker is invoked from that terminal
--- window (the window the cursor was last in). Picking from anywhere else
--- has no focused Agent.
---@return vantage.Agent?
local function focused_agent()
  local Client = require("vantage.client")
  if not Client.is_open() or vim.api.nvim_get_current_win() ~= Client.window then
    return nil
  end
  return Client.last_agent_alive()
end

--- Agent-picker items: the focused Agent first (marked ` (focused)`, exempt
--- from the ordering), then every Agent sorted by group, cwd, tool name, then
--- one Tool row per configured `cli.tools` key (sorted) to create a new
--- Agent. May be empty — pickers warn and return when there is nothing to
--- choose.
---@return { kind: "agent"|"tool", agent?: vantage.Agent, tool?: string, focused?: boolean, text: string }[]
function M.agent_items()
  local agents = Backend.get().list()
  local focused = focused_agent()
  local items = {}
  if focused then
    items[#items + 1] = {
      kind = "agent",
      agent = focused,
      focused = true,
      text = AGENT_ICON .. M.format_agent(focused) .. " (focused)",
    }
  end
  table.sort(agents, agent_order)
  for _, agent in ipairs(agents) do
    if not focused or agent.target ~= focused.target then
      items[#items + 1] = { kind = "agent", agent = agent, text = AGENT_ICON .. M.format_agent(agent) }
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

--- Agents (as { target, agent }) + Groups (as { target }) to kill.
--- nil (with a warning) when there is nothing to kill.
---@return { target: string, agent?: vantage.Agent, text: string }[]?
function M.kill_items()
  local items = {}
  for _, agent in ipairs(Backend.get().list()) do
    items[#items + 1] = { target = agent.target, agent = agent, text = M.format_agent(agent) }
  end
  for _, group in ipairs(Backend.get().groups()) do
    items[#items + 1] = { target = group, text = ("group %s"):format(group) }
  end
  if #items == 0 then
    Util.warn("nothing to kill")
    return nil
  end
  return items
end

--- The cwd to relativize annotation previews against: the focused Agent's cwd,
--- else the current window's local cwd.
---@return string
function M.annotation_cwd()
  local agent = require("vantage.client").last_agent_alive()
  return agent and agent.cwd or Util.cwd()
end

--- Annotations (as { annotation, text }) for the picker, or nil when there are
--- none (warned unless `silent`).
---@param silent? boolean
---@return { annotation: vantage.Annotation, text: string }[]?
function M.annotation_items(silent)
  local Annotation = require("vantage.annotation")
  local annotations = Annotation.collect()
  if #annotations == 0 then
    if not silent then
      Util.warn("no annotations — add one with :Vantage annotate")
    end
    return nil
  end
  local items = {}
  for _, annotation in ipairs(annotations) do
    local path = Util.tilde(vim.api.nvim_buf_get_name(annotation.buf) or "")
    local first = (vim.split(annotation.note, "\n", { plain = true })[1] or ""):gsub("%s+", " ")
    items[#items + 1] = {
      annotation = annotation,
      text = ("%s:L%d-%d  %s"):format(path, annotation.start_row, annotation.end_row, first),
    }
  end
  return items
end

return M
