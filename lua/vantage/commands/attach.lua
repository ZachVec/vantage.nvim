--- The Terminal attachment flows and the shared Agent picker they use.
---
--- `toggle` owns Terminal presence; `switch` owns the attached client's
--- target. The Agent/Tool rows, Group choice, and creation handoff are local
--- to this module because both flows are their only consumers.
local Actions = require("vantage.commands.actions")
local Bridge = require("vantage.backend.bridge")
local Config = require("vantage.config")
local Display = require("vantage.frontend.display")
local Picker = require("vantage.frontend.picker")
local Terminal = require("vantage.frontend.terminal")
local Util = require("vantage.util")

local M = {}

local NEW_GROUP = "+ new group"
local PROMPT = Util.picker_prompt

---@class vantage.AgentPickerState
---@field group_on boolean
---@field error? string
---@field focused? vantage.Agent

---@class vantage.AgentPickerEntry
---@field group string?
---@field format fun(self: vantage.AgentPickerEntry): string
---@field preview fun(self: vantage.AgentPickerEntry): string[]?

---@class vantage.AgentSelection What choosing an Agent-list row means.
---@field kind "focused"|"agent"|"new"
---@field agent? vantage.Agent the Agent to act on ("focused" and "agent"); the
--- Tool to create from travels in the row, not here

--- Ask for a Group through the picker, or straight through input() when none
--- exist. The continuation is asynchronous.
---@param after fun(group: string)
local function ask_group(after)
  local inventory, err = Bridge.inventory()
  if inventory == nil then
    Util.warn(err or "failed to read agents")
    return
  end
  local names = inventory.groups
  local function prompt_name()
    vim.schedule(function()
      local name = vim.trim(vim.fn.input({ prompt = "Group name: " }))
      if name ~= "" then
        after(name)
      end
    end)
  end
  if #names == 0 then
    prompt_name()
    return
  end
  names[#names + 1] = NEW_GROUP
  Picker.pick_plain(names, { prompt = "Group: " }, function(group)
    if not group then
      return
    end
    if group == NEW_GROUP then
      prompt_name()
    else
      after(group)
    end
  end)
end

---@class vantage.AgentPickerAgentEntry : vantage.AgentPickerEntry
---@field agent vantage.Agent
---@field focused boolean
local AgentEntry = {}
AgentEntry.__index = AgentEntry

---@param agent vantage.Agent
---@param focused boolean
---@return vantage.AgentPickerAgentEntry
function AgentEntry.new(agent, focused)
  return setmetatable({
    group = agent.group,
    agent = agent,
    focused = focused == true,
  }, AgentEntry)
end

function AgentEntry:format()
  local base = Display.format_agent(self.agent)
  if self.focused then
    return base .. " (focused)"
  end
  return base
end

function AgentEntry:preview()
  local lines, err = Bridge.capture(self.agent)
  if lines == nil then
    return { err or "failed to capture agent" }
  end
  return lines
end

--- Choosing an Agent row names that Agent. The pinned Focus row is already the
--- attached one, so it names nothing.
---@return vantage.AgentSelection
function AgentEntry:select()
  if self.focused then
    return { kind = "focused" }
  end
  return { kind = "agent", agent = self.agent }
end

---@class vantage.AgentPickerToolEntry : vantage.AgentPickerEntry
---@field name string
local ToolEntry = {}
ToolEntry.__index = ToolEntry

---@param name string
---@return vantage.AgentPickerToolEntry
function ToolEntry.new(name)
  return setmetatable({
    group = nil,
    name = name,
  }, ToolEntry)
end

function ToolEntry:format()
  return Display.tool_icon .. self.name
end

function ToolEntry:preview()
  return nil
end

--- Choosing a Tool row asks for a Group to create the Agent in. The row names
--- the Tool; the flow reads it and owns creation, so a cancelled Group choice
--- ends there.
---@return vantage.AgentSelection
function ToolEntry:select()
  return { kind = "new" }
end

--- The Agent rows' ascending order: group, cwd, tool name, then creation seq.
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
  if left.tool ~= right.tool then
    return left.tool < right.tool
  end
  return left.seq < right.seq
end

---@param agents vantage.Agent[]
---@param focused vantage.Agent?
---@return vantage.AgentPickerEntry[]
local function build_items(agents, focused)
  local items = {}
  table.sort(agents, agent_order)
  if focused then
    items[#items + 1] = AgentEntry.new(focused, true)
  end
  for _, agent in ipairs(agents) do
    if not focused or agent.id ~= focused.id then
      items[#items + 1] = AgentEntry.new(agent, false)
    end
  end
  local tools = vim.tbl_keys(Config.options.cli.tools)
  table.sort(tools)
  for _, name in ipairs(tools) do
    items[#items + 1] = ToolEntry.new(name)
  end
  return items
end

--- The Agent-list selection spec. The live group scope is read from `state`
--- by the flow-owned `<c-g>` command.
---@param pid? integer the terminal job's pid
---@param state? vantage.AgentPickerState
---@return vantage.PickSpec
local function spec(pid, state)
  state = state or { group_on = false }
  return {
    prompt = PROMPT,
    items_provider = function()
      local inventory, err = Bridge.inventory()
      state.error = err
      if inventory == nil then
        return {}
      end
      -- The Focus is a second read: the inventory never carries it.
      local focused, _ = Bridge.focus(pid)
      state.focused = focused
      local items = build_items(inventory.agents, focused)
      if state.group_on and focused then
        return vim
          .iter(items)
          :filter(function(item)
            return item.group == nil or item.group == focused.group
          end)
          :totable()
      end
      return items
    end,
  }
end

--- Kill the current row's Agent in place. The pinned `(focused)` row is the
--- Agent the Terminal is attached to, so it and Tool rows (no Agent yet) are
--- no-ops. Returns true when the list may have changed.
---@param ctx vantage.PickerCommandCtx
---@return boolean
local function kill_agent(ctx)
  local item = ctx.item
  if not item or item.focused or not item.agent then
    return false
  end
  local ok, err = Bridge.kill_agent(item.agent)
  if not ok then
    Util.warn(err or "failed to kill agent")
    return false
  end
  return true
end

--- Pick an Agent to act on, resolving the chosen row's selection (creating an
--- Agent from a Tool row when that is what was chosen).
---@param after fun(agent: vantage.Agent)
---@param pid? integer the terminal job's pid (nil = no focused Agent)
local function pick(after, pid)
  local state = { group_on = Picker.capabilities().command }
  local empty = Picker.pick(spec(pid, state), {
    on_choice = function(entry)
      local selection = entry:select()
      if selection.kind == "focused" then
        return
      end
      if selection.kind == "agent" then
        after(selection.agent)
        return
      end
      ask_group(function(group)
        local agent, err = Bridge.create({ group = group, tool = entry.name, cwd = Util.cwd() })
        if not agent then
          Util.warn(err or "failed to create agent")
          return
        end
        after(agent)
      end)
    end,
    commands = {
      {
        "<C-x>",
        kill_agent,
        desc = "kill agent",
      },
      {
        "<C-g>",
        function()
          state.group_on = not state.group_on
          return true
        end,
        desc = "toggle group scope",
      },
    },
  })
  if state.error then
    Util.warn(state.error)
  elseif empty then
    Util.warn("no agents and no tools configured (cli.tools)")
  end
end

--- Attach a new Terminal client to `agent` and install the terminal keymaps.
--- The View the Backend created is removed again when the terminal cannot
--- start, so a failed open leaves no session behind.
---@param agent vantage.Agent
local function open_on(agent)
  local attachment, err = Bridge.attach(agent)
  if not attachment then
    Util.warn(err or "failed to create terminal attachment")
    return
  end
  if Terminal.open(attachment.argv) then
    Actions.apply(Terminal.buffer)
  else
    Bridge.kill_view(attachment.view)
  end
end

--- Toggle Terminal presence; with no Terminal, pick an Agent and open it.
function M.toggle()
  if Terminal.toggle() then
    return
  end
  pick(open_on)
end

--- Re-point the live Terminal to another Agent.
function M.switch()
  local pid = Terminal.pid()
  if not pid then
    Util.warn("no terminal — use :Vantage toggle first")
    return
  end

  pick(function(agent)
    local ok, err = Bridge.retarget(pid, agent)
    if not ok then
      Util.warn(err or "failed to switch agent")
    end
  end, pid)
end

return M
