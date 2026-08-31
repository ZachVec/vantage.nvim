--- The :Vantage user command: subcommand dispatch.
local Backend = require("vantage.backend")
local Client = require("vantage.client")
local Config = require("vantage.config")
local Picker = require("vantage.picker")
local Util = require("vantage.util")

local M = {}

local function usage()
  vim.notify(
    table.concat({
      "Vantage — coding-agent manager",
      "",
      "  :Vantage switch [<@N>]       focus an Agent (interactive if no arg)",
      "  :Vantage kill [<group|@N>]   kill a Group or Agent (interactive if no arg)",
      "  :Vantage toggle              hide/show the terminal (creates if empty)",
      "  :Vantage detach              detach the client (kills the View; Agents survive)",
      "  :Vantage status              show clients + sessions",
    }, "\n"),
    vim.log.levels.INFO
  )
end

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
---@param cmd string
---@param cwd string
local function do_create(group, cmd, cwd)
  local agent = Backend.get().create({ group = group, cmd = cmd, cwd = cwd })
  if agent then
    Client.focus(agent)
  end
end

local function create_wizard()
  Picker.get().pick_tool(function(tool_name)
    local tool = Config.options.cli.tools[tool_name]
    Picker.get().pick_group(function(group)
      do_create(group, table.concat(tool.cmd, " "), Util.cwd())
    end)
  end)
end

--- Pick an Agent, or create a new one via the "new" entry in the picker.
local function pick_or_new()
  Picker.get().pick_agent(function(choice)
    if choice.kind == "new" then
      create_wizard()
    else
      Client.focus(choice.agent)
    end
  end)
end

--- Hide/show the terminal (lightweight); with no live terminal, re-open to the
--- last Agent, create one if there are none, or pick otherwise.
function M.toggle()
  if Client.toggle() then
    return
  end
  local last_agent = Client.last_agent_alive()
  if last_agent then
    Client.focus(last_agent)
    return
  end
  if #Backend.get().list() == 0 then
    create_wizard()
    return
  end
  pick_or_new()
end

function M.run(args)
  local fargs = args.fargs or {}
  local subcommand = fargs[1]
  local remaining = {}
  for i = 2, #fargs do
    remaining[#remaining + 1] = fargs[i]
  end

  if subcommand == nil then
    -- no default subcommand: show help
    usage()
  elseif subcommand == "switch" then
    if #remaining == 0 then
      pick_or_new()
      return
    end
    local agent = find_agent(remaining[1])
    if agent then
      Client.focus(agent)
    else
      Util.warn(("no such agent '%s'"):format(remaining[1]))
    end
  elseif subcommand == "kill" then
    if #remaining == 0 then
      Picker.get().pick_kill(function(target)
        Backend.get().kill(target)
      end)
      return
    end
    Backend.get().kill(remaining[1])
  elseif subcommand == "toggle" then
    M.toggle()
  elseif subcommand == "detach" then
    Client.detach()
  elseif subcommand == "status" then
    local status_info = Backend.get().status()
    local lines = { "sessions:" }
    for _, line in ipairs(status_info.sessions) do
      lines[#lines + 1] = "  " .. line
    end
    lines[#lines + 1] = "clients:"
    for _, line in ipairs(status_info.clients) do
      lines[#lines + 1] = "  " .. line
    end
    vim.notify(table.concat(lines, "\n"), vim.log.levels.INFO)
  else
    Util.warn(("unknown subcommand '%s'"):format(subcommand))
    usage()
  end
end

---@param arglead string
---@param cmdline string
---@return string[]
function M.complete(arglead, cmdline)
  if cmdline:match("^%s*Vantage%s*$") or cmdline:match("^%s*Vantage%s+%S*%s*$") then
    return vim.tbl_filter(function(s)
      return vim.startswith(s, arglead)
    end, { "switch", "kill", "toggle", "detach", "status" })
  end
  return {}
end

return M
