--- Frontend selection orchestration: builds the domain objects each picker
--- flow renders and assembles the PickSpec the picker implementations consume.
--- The picker implementations stay presentation-only and depend on nothing but
--- their engine; all domain assembly lives here.
---
--- Each picker item is a domain object — an Agent, Tool, Group, or Annotation
--- — carrying its own protocol methods: `format()` (display string),
--- `preview()` (preview lines or nil), `delete()` (remove it, returning
--- whether something was removed), `activate(after)` (perform the selection
--- action, invoking the flow-injected `after`), and `group()` (the Group it
--- belongs to, or nil when it has none).
---
--- A PickSpec field is an *input* to the picker (the items to render, an
--- environment fact, an in-flight group filter); the chosen item is
--- delivered through the positional `on_choice` (the picker's single result
--- channel), and the picker's synchronous boolean return reports whether the
--- list was empty.
local Annotation = require("vantage.annotation")
local Backend = require("vantage.backend")
local Client = require("vantage.client")
local Config = require("vantage.config")
local Picker = require("vantage.picker")
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

--- The "+ new group" row of the Group pick (Tool-row creation).
local NEW_GROUP = "+ new group"

---@param agent vantage.Agent
---@return string
local function format_agent(agent)
  return AGENT_ICON .. ("%s · %s · %s"):format(agent.tool, agent.group, Util.tilde(agent.cwd))
end

---@param group string
---@param tool_name string
---@param cmd string
---@param cwd string
---@param after fun(agent: vantage.Agent)
local function do_create(group, tool_name, cmd, cwd, after)
  local agent = Backend.get().create({ group = group, cmd = cmd, cwd = cwd, tool = tool_name })
  if agent then
    after(agent)
  end
end

--- Prompt for a new Group name (insert-mode cmdline). Scheduled so a picker
--- window can finish closing before the cmdline opens.
---@param callback fun(group: string)
local function ask_new_group_name(callback)
  vim.schedule(function()
    local name = vim.trim(vim.fn.input({ prompt = "Group name: " }))
    if name ~= "" then
      callback(name)
    end
  end)
end

--- Pick a Group (or prompt a new-Group name) for a Tool, then create the
--- Agent and run `after` on it (the tail action differs by command: focus for
--- toggle's open, retarget for switch). This is the Tool row's `activate`.
---@param tool_name string
---@param after fun(agent: vantage.Agent)
---@param from_terminal boolean
local function create_with_tool(tool_name, after, from_terminal)
  local tool = Config.options.cli.tools[tool_name]
  local cmd = Util.shell_join(tool.cmd)
  local picker = Picker.get()
  local function create(group)
    do_create(group, tool_name, cmd, Util.cwd(), after)
  end
  local groups = Backend.get().groups()
  if #groups == 0 then
    ask_new_group_name(create)
    return
  end
  groups[#groups + 1] = NEW_GROUP
  picker.pick_plain(groups, { prompt = "Group: ", from_terminal = from_terminal }, function(group)
    if not group then
      return
    end
    if group == NEW_GROUP then
      ask_new_group_name(create)
    else
      create(group)
    end
  end)
end

---@param agent vantage.Agent
---@param focused boolean
---@return table
local function agent_entry(agent, focused)
  return {
    format = function()
      local base = format_agent(agent)
      if focused then
        return base .. " (focused)"
      end
      return base
    end,
    preview = function()
      return Backend.get().capture_pane(agent.target)
    end,
    delete = function()
      if focused then
        return false
      end
      Backend.get().kill(agent.target)
      return true
    end,
    activate = function(_, after)
      if focused then
        return
      end
      after(agent)
    end,
    group = function()
      return agent.group
    end,
  }
end

---@param name string
---@param from_terminal boolean
---@return table
local function tool_entry(name, from_terminal)
  return {
    format = function()
      return TOOL_ICON .. name
    end,
    preview = function()
      return nil
    end,
    delete = function()
      return false
    end,
    activate = function(_, after)
      create_with_tool(name, after, from_terminal)
    end,
    group = function()
      return nil -- Tool rows are creation actions, not Group members.
    end,
  }
end

---@param group string
---@return table
local function group_entry(group)
  return {
    format = function()
      return ("group %s"):format(group)
    end,
    preview = function()
      return nil
    end,
    delete = function()
      Backend.get().kill(group)
      return true
    end,
    -- NOTE: a Group's `activate` (switch the client to this Group) is defined
    -- in the domain model but not yet wired to a flow; it lands when the kill
    -- picker is redesigned.
    group = function()
      return group
    end,
  }
end

---@param annotation vantage.Annotation
---@param cwd string
---@return table
local function annotation_entry(annotation, cwd)
  local path = Util.tilde(vim.api.nvim_buf_get_name(annotation.buf) or "")
  local first = (vim.split(annotation.note, "\n", { plain = true })[1] or ""):gsub("%s+", " ")
  return {
    format = function()
      return ("%s:L%d-%d  %s"):format(path, annotation.start_row, annotation.end_row, first)
    end,
    preview = function()
      return vim.split(Annotation.render_item(annotation, cwd), "\n")
    end,
    delete = function()
      Annotation.delete(annotation.buf, annotation.id)
      return true
    end,
    activate = function(_, after)
      after(annotation)
    end,
    group = function()
      return nil
    end,
  }
end

--- The Agent rows' ascending order: group, absolute cwd, tool name (the
--- `cli.tools` key), then window id (@N) by
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
  local left_tool = left.tool
  local right_tool = right.tool
  if left_tool ~= right_tool then
    return left_tool < right_tool
  end
  -- @N window ids sort numerically; a malformed id (never produced by the
  -- tmux driver) degrades to 0 so the comparator stays total.
  return Util.agent_window_index(left.target) < Util.agent_window_index(right.target)
end

--- Agent-picker items: the focused Agent first (marked ` (focused)`, exempt
--- from the ordering), then every Agent sorted by group, cwd, tool name, then
--- one Tool row per configured `cli.tools` key (sorted) to create a new
--- Agent. May be empty.
---@param agents vantage.Agent[]
---@param focused vantage.Agent?
---@param from_terminal boolean
---@return table[]
local function agent_items(agents, focused, from_terminal)
  local items = {}
  if focused then
    items[#items + 1] = agent_entry(focused, true)
  end
  table.sort(agents, agent_order)
  for _, agent in ipairs(agents) do
    if not focused or agent.target ~= focused.target then
      items[#items + 1] = agent_entry(agent, false)
    end
  end
  local tools = {}
  for name in pairs(Config.options.cli.tools) do
    tools[#tools + 1] = name
  end
  table.sort(tools)
  for _, name in ipairs(tools) do
    items[#items + 1] = tool_entry(name, from_terminal)
  end
  return items
end

--- Agents + Groups to kill. May be empty.
---@return table[]
local function kill_items()
  local snapshot = Backend.get().snapshot()
  local items = {}
  for _, agent in ipairs(snapshot.agents) do
    items[#items + 1] = agent_entry(agent, false)
  end
  for _, group in ipairs(snapshot.groups) do
    items[#items + 1] = group_entry(group)
  end
  return items
end

--- Annotations. May be empty.
---@return table[]
local function annotation_items()
  local cwd = Util.cwd()
  local items = {}
  for _, annotation in ipairs(Annotation.collect()) do
    items[#items + 1] = annotation_entry(annotation, cwd)
  end
  return items
end

--- The live group filter for the Agent list: while a focused Agent is
--- alive, keep only its Group's Agent rows (Tool rows always stay — they are
--- creation actions, not Group members); with no focused Agent — or after it
--- dies mid-picker — keep everything.
---@param items table[]
---@param focused vantage.Agent?
---@return table[]
local function agent_group(items, focused)
  if not focused then
    return items
  end
  local out = {}
  for _, entry in ipairs(items) do
    local group = entry:group()
    if group == nil or group == focused.group then
      out[#out + 1] = entry
    end
  end
  return out
end

--- The Agent-list selection spec. `<c-x>` on a non-focused Agent row
--- (fzf-lua/snacks) kills it in place; the picker re-reads `items_provider`
--- only when `delete()` reports a removal, so the killed Agent's row vanishes.
--- The pinned `(focused)` row ignores `<c-x>` (its `delete` is a deliberate
--- no-op; killing it would drop the client's focus — see the Agent Note).
--- `focused` is re-resolved per read, so the pin follows the live Agent. The
--- Agent list opens filtered to the focused Agent's Group by default
--- (fzf-lua/snacks toggle it with `<c-g>`; native keeps showing everything).
---@param from_terminal boolean caller-declared: this pick runs inside the terminal
---@return vantage.PickSpec
function M.agent_spec(from_terminal)
  local focused
  return {
    prompt = PROMPT,
    items_provider = function()
      local view = from_terminal and Client.view or nil
      local snapshot = Backend.get().snapshot(view)
      focused = snapshot.focused
      return agent_items(snapshot.agents, focused, from_terminal)
    end,
    from_terminal = from_terminal,
    group = function(items)
      return agent_group(items, focused)
    end,
  }
end

--- The kill-list selection spec.
---@param from_terminal boolean caller-declared: this pick runs inside the terminal
---@return vantage.PickSpec
function M.kill_spec(from_terminal)
  return {
    prompt = PROMPT,
    items_provider = kill_items,
    from_terminal = from_terminal,
  }
end

--- The annotation-list selection spec. `<c-x>` removes the chosen annotation
--- in place; the picker re-reads `items_provider` and closes when nothing
--- remains.
---@param from_terminal boolean caller-declared: this pick runs inside the terminal
---@return vantage.PickSpec
function M.annotation_spec(from_terminal)
  return {
    prompt = PROMPT,
    items_provider = annotation_items,
    from_terminal = from_terminal,
  }
end

return M
