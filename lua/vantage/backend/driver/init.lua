--- Driver registry: resolve the configured multiplexer driver once per setup.
--- This is the extension seam for future drivers (e.g. zellij).

---@class vantage.Agent A running coding-agent process.
---@field id string opaque Driver identity
---@field seq integer driver-neutral creation order
---@field group string
---@field cmd string
---@field cwd string
---@field tool string the cli.tools key that created it (for the format hook)
---@field state? string

---@class vantage.Attachment A Terminal's transient View and attach command.
---@field view string
---@field argv string[]

---@class vantage.Driver The multiplexer contract behind the Backend's public surface.
---@field create fun(opts: { group: string, cmd: string, cwd: string, tool: string }): vantage.Agent?, string?
---@field agents fun(): vantage.Agent[]?, string?
---@field focus fun(pid: integer): vantage.Agent?, string?
---@field retarget fun(pid: integer, agent: vantage.Agent): boolean, string?
---@field attach fun(agent: vantage.Agent): vantage.Attachment?, string?
---@field kill_view fun(view: string): boolean, string?
---@field kill_agent fun(agent: vantage.Agent): boolean, string?
---@field kill_group fun(group: string): boolean, string?
---@field send_keys fun(agent: vantage.Agent, text: string): boolean, string?
---@field capture_pane fun(agent: vantage.Agent, max_lines?: integer): string[]?, string?
---@field status fun(): { clients: string[], sessions: string[] }?, string?
---@field health fun(): { status: "ok"|"warn"|"err", message: string, fatal?: boolean }[]

local Config = require("vantage.config")

local M = {}

--- User-facing name -> module path. A whitelist, so a raw user string is never
--- `require`d.
local REGISTRY = {
  tmux = "vantage.backend.driver.tmux",
}

local REQUIRED = {
  "create",
  "agents",
  "focus",
  "retarget",
  "attach",
  "kill_view",
  "kill_agent",
  "kill_group",
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

return M
