--- The Bridge: the Backend's public surface consumed by the Frontend. Pure
--- data and domain verbs over the Driver; it holds no state and knows no UI.
local Config = require("vantage.config")
local Driver = require("vantage.backend.driver")
local Util = require("vantage.util")

local M = {}

--- The live inventory — flat Agents (creation order), derived Groups, and the
--- Agent the terminal (job pid) is currently showing. One aggregated read;
--- grouping is a caller concern.
---@param pid? integer the terminal job's pid
---@return { agents: vantage.Agent[], groups: string[], focused?: vantage.Agent }
function M.agents(pid)
  return Driver.get().snapshot(pid)
end

--- Create an Agent from a Tool row: resolve the tool to its command, then
--- delegate. The Group is created implicitly when it does not exist.
---@param opts { group: string, tool: string, cwd: string }
---@return vantage.Agent?
function M.create(opts)
  local tool = Config.options.cli.tools[opts.tool]
  if not tool then
    return nil
  end
  local cmd = Util.shell_join(tool.cmd)
  return Driver.get().create({ group = opts.group, cmd = cmd, cwd = opts.cwd, tool = opts.tool })
end

--- Re-point the terminal's client to an Agent.
---@param pid integer the terminal job's pid
---@param agent vantage.Agent
---@return boolean
function M.retarget(pid, agent)
  return Driver.get().retarget(pid, agent)
end

--- Paste final text into an Agent's input (no auto-submit).
---@param agent vantage.Agent
---@param text string
function M.send(agent, text)
  Driver.get().send_keys(agent, text)
end

--- The Agent pane's recent output, for entry previews.
---@param agent vantage.Agent
---@return string[]
function M.capture(agent)
  return Driver.get().capture_pane(agent)
end

--- The argv the Terminal runs to attach to (Group, Agent).
---@param group string
---@param agent string Agent window id (@N)
---@return string[]
function M.attach_command(group, agent)
  return Driver.get().attach_command(group, agent)
end

---@param agent vantage.Agent
function M.kill_agent(agent)
  Driver.get().kill_agent(agent)
end

---@param group string
function M.kill_group(group)
  Driver.get().kill_group(group)
end

---@return { clients: string[], sessions: string[] }
function M.status()
  return Driver.get().status()
end

return M
