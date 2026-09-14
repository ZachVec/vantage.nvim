--- The Backend's public surface: pure data and domain verbs over the pluggable
--- Driver, consumed by the Frontend. Holds no state, knows no UI.
local Config = require("vantage.config")
local Driver = require("vantage.backend.driver")
local Util = require("vantage.util")

local M = {}

--- The live inventory: flat Agents in creation order plus the Groups derived
--- from them (each Group once, in the Agents' order). No Focus read — a caller
--- that does not care what the Terminal shows does not pay for it.
---@return { agents: vantage.Agent[], groups: string[] }?
---@return string?
function M.inventory()
  local agents, err = Driver.get().agents()
  if not agents then
    return nil, err
  end
  local seen = {}
  local groups = {}
  for _, agent in ipairs(agents) do
    if not seen[agent.group] then
      seen[agent.group] = true
      groups[#groups + 1] = agent.group
    end
  end
  return { agents = agents, groups = groups }, nil
end

--- The Agent the Terminal (job pid) is currently showing: the Focus. Nil with
--- a reason when there is none — no Terminal at all, a Terminal whose client is
--- gone, or a client that is not on an Agent window. Read it fresh; it is never
--- stored. "No Terminal at all" is the Frontend's own fact, so it short-circuits
--- before the Driver; the Driver answers the multiplexer half in one query.
---@param pid? integer the terminal job's pid
---@return vantage.Agent?
---@return string?
function M.focus(pid)
  if pid == nil then
    return nil, Config.FOCUS_NO_TERMINAL
  end
  return Driver.get().focus(pid)
end

--- Create an Agent from a Tool entry: resolve the tool to its command, then
--- delegate. The Group is created implicitly when it does not exist.
---@param opts { group: string, tool: string, cwd: string }
---@return vantage.Agent?
---@return string?
function M.create(opts)
  local tool = Config.options.cli.tools[opts.tool]
  if not tool then
    return nil, ("unknown tool '%s'"):format(opts.tool)
  end
  local cmd = Util.shell_join(tool.cmd)
  return Driver.get().create({ group = opts.group, cmd = cmd, cwd = opts.cwd, tool = opts.tool })
end

--- Re-point the terminal's client to an Agent.
---@param pid integer the terminal job's pid
---@param agent vantage.Agent
---@return boolean
---@return string?
function M.retarget(pid, agent)
  return Driver.get().retarget(pid, agent)
end

--- Paste final text into an Agent's input (no auto-submit).
---@param agent vantage.Agent
---@param text string
---@return boolean
---@return string?
function M.send(agent, text)
  return Driver.get().send_keys(agent, text)
end

--- The Agent pane's recent output, for entry previews.
---@param agent vantage.Agent
---@return string[]?
---@return string?
function M.capture(agent)
  return Driver.get().capture_pane(agent)
end

--- Create this Terminal's View for an Agent and return its attach command.
---@param agent vantage.Agent
---@return vantage.Attachment?
---@return string?
function M.attach(agent)
  return Driver.get().attach(agent)
end

--- Remove a View created for a Terminal that failed to start.
---@param view string
---@return boolean
---@return string?
function M.kill_view(view)
  return Driver.get().kill_view(view)
end

---@param agent vantage.Agent
---@return boolean
---@return string?
function M.kill_agent(agent)
  return Driver.get().kill_agent(agent)
end

---@param group string
---@return boolean
---@return string?
function M.kill_group(group)
  return Driver.get().kill_group(group)
end

---@return { clients: string[], sessions: string[] }?
---@return string?
function M.status()
  return Driver.get().status()
end

return M
