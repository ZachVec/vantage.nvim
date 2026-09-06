--- Agent actions: switch, kill, and the create/pick flow behind both the
--- Agent picker's Tool rows and toggle's open path. All Agent domain work for
--- the command layer lives here.
local Backend = require("vantage.backend")
local Client = require("vantage.client")
local Config = require("vantage.config")
local Picker = require("vantage.picker")
local Select = require("vantage.select")
local Util = require("vantage.util")

local M = {}

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

--- The "+ new group" row of the Group pick (Tool-row creation).
local NEW_GROUP = "+ new group"

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
--- toggle's open, retarget for switch). Shared by the Tool rows at the tail of
--- the Agent picker.
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

--- Pick an Agent to act on (focus or re-target), create one from a trailing
--- Tool row, or confirm the pinned `(focused)` row, which deliberately does
--- nothing. The tail action differs by command: `Client.focus` (toggle's open
--- path) materializes and shows a terminal; `Client.retarget` (switch) only
--- re-points an existing one.
---@param after fun(agent: vantage.Agent)
---@param from_terminal boolean
function M.pick_or_new(after, from_terminal)
  local empty = Picker.get().pick_agent(Select.agent_spec(from_terminal), function(choice)
    if choice.kind == "tool" then
      create_with_tool(choice.tool, after, from_terminal)
    elseif not choice.focused then
      after(choice.agent)
    end
  end)
  if empty then
    Util.warn("no agents and no tools configured (cli.tools)")
  end
end

--- `switch` (terminal keymap token): re-point the live terminal to an Agent,
--- interactively.
function M.switch()
  M.pick_or_new(Client.retarget, true)
end

--- `kill` (terminal keymap token): kill a Group or Agent, interactively.
function M.kill()
  local empty = Picker.get().pick_kill(Select.kill_spec(true), function(target)
    Backend.get().kill(target)
  end)
  if empty then
    Util.warn("nothing to kill")
  end
end

return M
