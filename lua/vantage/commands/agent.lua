--- Agent commands: switch, kill, and the create/pick flow behind both the
--- Agent picker's Tool rows and toggle's open path. All Agent domain work for
--- the command layer lives here.
local Backend = require("vantage.backend")
local Client = require("vantage.client")
local Config = require("vantage.config")
local Picker = require("vantage.picker")
local Select = require("vantage.select")
local Util = require("vantage.util")

local M = {}

---@param target string
---@return vantage.Agent?
local function find_agent(target)
  for _, agent in ipairs(Backend.get().list()) do
    if agent.target == target then
      return agent
    end
  end
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
local function create_with_tool(tool_name, after)
  local tool = Config.options.cli.tools[tool_name]
  if not tool then
    return
  end
  local cmd = table.concat(tool.cmd, " ")
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
  picker.pick_plain(
    groups,
    { prompt = "Group: ", invoked_from_terminal = Select.invoked_from_terminal() },
    function(group)
      if not group then
        return
      end
      if group == NEW_GROUP then
        ask_new_group_name(create)
      else
        create(group)
      end
    end
  )
end

--- Pick an Agent to act on (focus or re-target), create one from a trailing
--- Tool row, or confirm the pinned `(focused)` row, which deliberately does
--- nothing. The tail action differs by command: `Client.focus` (toggle's open
--- path) materializes and shows a terminal; `Client.retarget` (switch) only
--- re-points an existing one.
---@param after fun(agent: vantage.Agent)
function M.pick_or_new(after)
  local empty = Picker.get().pick_agent(Select.agent_spec(), function(choice)
    if choice.kind == "tool" then
      create_with_tool(choice.tool, after)
    elseif not choice.focused then
      after(choice.agent)
    end
  end)
  if empty then
    Util.warn("no agents and no tools configured (cli.tools)")
  end
end

--- `:Vantage switch`: re-point the existing terminal to an Agent (interactive
--- if no argument). Requires a live terminal; with none it warns.
---@param remaining string[]
function M.switch(remaining)
  if not Client.is_attached() then
    Util.warn("no client — use :Vantage toggle to open one")
    return
  end
  if #remaining == 0 then
    M.pick_or_new(Client.retarget)
    return
  end
  local agent = find_agent(remaining[1])
  if agent then
    Client.retarget(agent)
  else
    Util.warn(("no such agent '%s'"):format(remaining[1]))
  end
end

--- `:Vantage kill`: kill a Group or Agent (interactive if no argument).
---@param remaining string[]
function M.kill(remaining)
  if #remaining == 0 then
    local empty = Picker.get().pick_kill(Select.kill_spec(), function(target)
      Backend.get().kill(target)
    end)
    if empty then
      Util.warn("nothing to kill")
    end
    return
  end
  Backend.get().kill(remaining[1])
end

return M
