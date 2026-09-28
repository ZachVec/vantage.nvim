--- The Backend: the plugin's domain layer and its door to a multiplexer
--- implementation. It holds no state and knows no UI.
---
--- One file carries both of the Backend's roles: the surface the Frontend
--- imports (`inventory`, `create`, `attach`, and the pass-throughs to the
--- resolved Driver) and the `vantage.Driver` contract a multiplexer implements.
--- `backend/` is one layer — `vantage.backend`, `vantage.backend.tmux` — so the
--- module callers import, the contract implementations satisfy, and the types
--- they share all sit in one place.
---
--- A Driver's own options live in `Config.options.backend_opts` under its
--- registry name (`tmux.socket`): the shared option table names no multiplexer
--- concept.

---@class vantage.Agent A running coding-agent process.
---@field id string opaque Driver identity
---@field seq integer driver-neutral creation order
---@field group string
---@field cmd string
---@field cwd string
---@field tool string the cli.tools key that created it (for the format hook)
---@field state? string

---@class vantage.Attachment A Terminal's client on its View: the handle
---`attach` returns and the Frontend holds for as long as the Terminal lives. It
---carries identity only — every method answers from live state, never from a
---cached Agent, Group, or View — so it cannot disagree with the multiplexer.
---@field focus fun(self: vantage.Attachment): vantage.Agent?, string?
---@field retarget fun(self: vantage.Attachment, agent: vantage.Agent): boolean, string?

---@class vantage.Driver The multiplexer contract behind the Backend's public surface.
---@field create fun(opts: { group: string, cmd: string, cwd: string, tool: string }): vantage.Agent?, string?
---@field agents fun(): vantage.Agent[]?, string?
---@field attach fun(agent: vantage.Agent, launch: fun(argv: string[]): boolean, string?): vantage.Attachment?, string?
---@field kill_agent fun(agent: vantage.Agent): boolean, string?
---@field send_keys fun(agent: vantage.Agent, text: string): boolean, string?
---@field capture_pane fun(agent: vantage.Agent, max_lines?: integer): string[]?, string?
---@field status fun(): { clients: string[], sessions: string[] }?, string?
---@field health fun(): { status: "ok"|"warn"|"err", message: string, fatal?: boolean }[]

local Config = require("vantage.config")
local Util = require("vantage.util")

local M = {}

--- User-facing name -> module path. A whitelist, so a raw user string is never
--- `require`d.
local REGISTRY = {
  tmux = "vantage.backend.tmux",
}

local REQUIRED = {
  "create",
  "agents",
  "attach",
  "kill_agent",
  "send_keys",
  "capture_pane",
  "status",
  "health",
}

---@type vantage.Driver?
local resolved

--- Resolve the configured Driver. Called by the composition root before any
--- runtime side effects; invalid configuration is a setup error.
function M.setup()
  resolved = nil
  local name = Config.options.backend
  local mod = REGISTRY[name]
  if not mod then
    error(("vantage: unknown backend '%s'"):format(tostring(name)), 0)
  end
  local ok, impl = pcall(require, mod)
  if not ok then
    error(("vantage: backend '%s' unavailable (%s)"):format(name, tostring(impl)), 0)
  end
  for _, method in ipairs(REQUIRED) do
    if type(impl[method]) ~= "function" then
      error(("vantage: backend '%s' does not implement vantage.Driver.%s"):format(name, method), 0)
    end
  end
  resolved = impl
end

--- The Driver resolved during setup.
---@return vantage.Driver
function M.get()
  if not resolved then
    error("vantage: backend not initialized; call require('vantage').setup() first", 0)
  end
  return resolved
end

--- Test/initialization helper: forget the resolved Driver.
function M.reset()
  resolved = nil
end

--- The live inventory: flat Agents in creation order plus the Groups derived
--- from them (each Group once, in the Agents' order). No Focus read — a caller
--- that does not care what the Terminal shows does not pay for it.
---@return { agents: vantage.Agent[], groups: string[] }?
---@return string?
function M.inventory()
  local agents, err = M.get().agents()
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

--- Create an Agent from a Tool entry: resolve the tool to its command, then
--- delegate. `opts.tool` is a `cli.tools` key — `Config.apply` has already
--- dropped invalid entries — so the lookup cannot miss. The Group is created
--- implicitly when it does not exist.
---@param opts { group: string, tool: string, cwd: string }
---@return vantage.Agent?
---@return string?
function M.create(opts)
  local tool = Config.options.cli.tools[opts.tool]
  local cmd = Util.shell_join(tool.cmd)
  return M.get().create({ group = opts.group, cmd = cmd, cwd = opts.cwd, tool = opts.tool })
end

--- Paste final text into an Agent's input (no auto-submit).
---@param agent vantage.Agent
---@param text string
---@return boolean
---@return string?
function M.send(agent, text)
  return M.get().send_keys(agent, text)
end

--- The Agent pane's recent output, for entry previews.
---@param agent vantage.Agent
---@return string[]?
---@return string?
function M.capture(agent)
  return M.get().capture_pane(agent)
end

--- Create this Terminal's Attachment for an Agent: the View is created, then
--- `launch(argv)` starts the client on it, and a client that cannot start takes
--- the View back down. The returned handle is the Frontend's identity for its
--- Terminal; `focus` and `retarget` answer from live state.
---@param agent vantage.Agent
---@param launch fun(argv: string[]): boolean, string?
---@return vantage.Attachment?
---@return string?
function M.attach(agent, launch)
  return M.get().attach(agent, launch)
end

---@param agent vantage.Agent
---@return boolean
---@return string?
function M.kill_agent(agent)
  return M.get().kill_agent(agent)
end

---@return { clients: string[], sessions: string[] }?
---@return string?
function M.status()
  return M.get().status()
end

--- Health-check records from the resolved Driver.
---@return { status: "ok"|"warn"|"err", message: string, fatal?: boolean }[]
function M.health()
  return M.get().health()
end

return M
