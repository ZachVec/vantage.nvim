--- The switch flow (terminal token) plus the shared pick flow toggle reuses.
--- Entry rows are defined here because this flow is the only one that
--- resolves them; only the Agent row's display text is shared (display.lua).
---
--- SwitchEntry is the row protocol (group data + format/preview/target);
--- SwitchAgentEntry and SwitchToolEntry inherit it and are called directly at
--- construction, so there is no kind dispatch.
local Bridge = require("vantage.backend.bridge")
local Config = require("vantage.config")
local Display = require("vantage.frontend.display")
local Picker = require("vantage.frontend.picker")
local Terminal = require("vantage.frontend.terminal")
local Util = require("vantage.util")

local M = {}

local NEW_GROUP = "+ new group"
local PROMPT = Util.picker_prompt

---@class vantage.SwitchEntry One picker row in the switch/toggle flow. Every
--- subclass implements the same protocol: `group` data, `format()`,
--- `preview()`, and `target(done)` — which hands the chosen Agent to `done`.
--- A pinned focused row never calls `done` (selecting it is a deliberate
--- no-op).
---@field group string?
---@field format fun(self: vantage.SwitchEntry): string
---@field preview fun(self: vantage.SwitchEntry): string[]?
---@field target fun(self: vantage.SwitchEntry, done: fun(agent: vantage.Agent))

--- Ask for a Group through the picker (existing Groups + a new-name row), or
--- straight through input() when none exist. The continuation is the tool
--- row's target continuation: the picker is asynchronous.
---@param after fun(group: string)
local function ask_group(after)
  local names = Bridge.agents(nil).groups
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
  Picker.get().pick_plain(names, { prompt = "Group: " }, function(group)
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

---@class vantage.SwitchAgentEntry : vantage.SwitchEntry An Agent row: resolves
--- to itself; the pinned focused row resolves to nothing.
---@field agent vantage.Agent
---@field focused boolean
local SwitchAgentEntry = {}
SwitchAgentEntry.__index = SwitchAgentEntry

---@param agent vantage.Agent
---@param focused boolean
---@return vantage.SwitchAgentEntry
function SwitchAgentEntry.new(agent, focused)
  return setmetatable({
    group = agent.group,
    agent = agent,
    focused = focused == true,
  }, SwitchAgentEntry)
end

function SwitchAgentEntry:format()
  local base = Display.format_agent(self.agent)
  if self.focused then
    return base .. " (focused)"
  end
  return base
end

function SwitchAgentEntry:preview()
  return Bridge.capture(self.agent)
end

function SwitchAgentEntry:target(done)
  if not self.focused then
    done(self.agent)
  end
end

---@class vantage.SwitchToolEntry : vantage.SwitchEntry A Tool row: resolves by
--- asking for a Group, then creating an Agent in it.
---@field name string
local SwitchToolEntry = {}
SwitchToolEntry.__index = SwitchToolEntry

---@param name string
---@return vantage.SwitchToolEntry
function SwitchToolEntry.new(name)
  return setmetatable({
    group = nil,
    name = name,
  }, SwitchToolEntry)
end

function SwitchToolEntry:format()
  return Display.tool_icon .. self.name
end

function SwitchToolEntry:preview()
  return nil
end

function SwitchToolEntry:target(done)
  local function create(group)
    local agent = Bridge.create({ group = group, tool = self.name, cwd = Util.cwd() })
    if agent then
      done(agent)
    end
  end
  ask_group(create)
end

--- The Agent rows' ascending order: group, cwd, tool name, then window id.
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
  return Util.agent_window_index(left.target) < Util.agent_window_index(right.target)
end

--- The pick list: the focused Agent pinned first, then every Agent sorted,
--- then one Tool row per configured cli.tools key (sorted).
---@param agents vantage.Agent[]
---@param focused vantage.Agent?
---@return vantage.SwitchEntry[]
local function build_items(agents, focused)
  local items = {}
  table.sort(agents, agent_order)
  if focused then
    items[#items + 1] = SwitchAgentEntry.new(focused, true)
  end
  for _, agent in ipairs(agents) do
    if not focused or agent.target ~= focused.target then
      items[#items + 1] = SwitchAgentEntry.new(agent, false)
    end
  end
  local tools = vim.tbl_keys(Config.options.cli.tools)
  table.sort(tools)
  for _, name in ipairs(tools) do
    items[#items + 1] = SwitchToolEntry.new(name)
  end
  return items
end

--- The Agent-list selection spec. `focused` is re-resolved per read, so the
--- pin and the default group scope follow the live Agent. The list opens
--- scoped to the focused Agent's Group (fzf-lua/snacks toggle it with <c-g>).
---@param pid? integer the terminal job's pid
---@return vantage.PickSpec
function M.spec(pid)
  local focused
  return {
    prompt = PROMPT,
    items_provider = function()
      local snapshot = Bridge.agents(pid)
      focused = snapshot.focused
      return build_items(snapshot.agents, snapshot.focused)
    end,
    group = function(items)
      if not focused then
        return items
      end
      return vim
        .iter(items)
        :filter(function(item)
          return item.group == nil or item.group == focused.group
        end)
        :totable()
    end,
  }
end

--- Pick an Agent to act on (resolve), creating one from a Tool row when
--- needed. The tail differs by flow and lives in the caller.
---@param after fun(agent: vantage.Agent)
---@param pid? integer the terminal job's pid (nil = no focused Agent)
function M.pick(after, pid)
  local empty = Picker.get().pick_agent(M.spec(pid), function(entry)
    entry:target(after)
  end)
  if empty then
    Util.warn("no agents and no tools configured (cli.tools)")
  end
end

--- `switch` (terminal keymap token): re-point the live terminal to an Agent.
function M.switch()
  local pid = Terminal.pid()
  if not pid then
    Util.warn("no terminal — use :Vantage toggle first")
    return
  end
  M.pick(function(agent)
    Bridge.retarget(pid, agent)
  end, pid)
end

return M
