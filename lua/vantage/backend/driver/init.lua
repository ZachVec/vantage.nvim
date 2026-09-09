--- Driver registry: resolve the configured multiplexer driver once per setup.
--- This is the extension seam for future drivers (e.g. zellij).
local Config = require("vantage.config")

local M = {}

--- User-facing name -> module path. A whitelist, so a raw user string is never
--- `require`d.
local REGISTRY = {
  tmux = "vantage.backend.driver.tmux",
}

local REQUIRED = {
  "create",
  "snapshot",
  "retarget",
  "attach_command",
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
