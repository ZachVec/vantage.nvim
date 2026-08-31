--- Picker frontend interface: dispatch to the configured picker implementation.
--- This is the Frontend analogue of backend/init.lua: callers go through
--- Picker.get() and never touch a specific picker module directly.
local Config = require("vantage.config")
local Util = require("vantage.util")

local M = {}

--- User-facing name -> module path. A whitelist, so a raw user string is never
--- `require`d; unknown values fall back to native.
local REGISTRY = {
  native = "vantage.picker.native",
  ["fzf-lua"] = "vantage.picker.fzf_lua",
  snacks = "vantage.picker.snacks",
}

---@return vantage.PickerImpl
function M.get()
  local name = Config.options.picker
  local mod = REGISTRY[name]
  if not mod then
    Util.warn(("unknown picker '%s' — falling back to native"):format(tostring(name)))
    return require("vantage.picker.native")
  end
  local ok, impl = pcall(require, mod)
  if not ok then
    Util.warn(("picker '%s' unavailable (%s) — falling back to native"):format(name, tostring(impl)))
    return require("vantage.picker.native")
  end
  return impl
end

return M
