--- Backend interface: dispatch to the configured multiplexer driver.
--- This is the extension seam for future drivers (e.g. zellij).
local Config = require("vantage.config")
local Util = require("vantage.util")

local M = {}

--- User-facing name -> module path. A whitelist, so a raw user string is never
--- `require`d; unknown values fall back to tmux.
local REGISTRY = {
  tmux = "vantage.backend.tmux",
}

---@return table the concrete backend driver module
function M.get()
  local name = Config.options.backend
  local mod = REGISTRY[name]
  if not mod then
    Util.warn(("unknown backend '%s' — falling back to tmux"):format(tostring(name)))
    return require("vantage.backend.tmux")
  end
  local ok, impl = pcall(require, mod)
  if not ok then
    Util.warn(("backend '%s' unavailable (%s) — falling back to tmux"):format(name, tostring(impl)))
    return require("vantage.backend.tmux")
  end
  return impl
end

return M
