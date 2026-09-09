--- Picker frontend facade: resolve the configured implementation and own the
--- capability/command negotiation shared by every pick.
local Config = require("vantage.config")

local M = {}

--- User-facing name -> module path. A whitelist, so a raw user string is never
--- `require`d.
local REGISTRY = {
  native = "vantage.frontend.picker.native",
  ["fzf-lua"] = "vantage.frontend.picker.fzf_lua",
  snacks = "vantage.frontend.picker.snacks",
}

--- True when the Lua module `mod` is on the runtimepath, without loading it.
---@param mod string
---@return boolean
local function module_available(mod)
  local path = mod:gsub("%.", "/")
  return #vim.api.nvim_get_runtime_file(("lua/%s.lua"):format(path), false) > 0
    or #vim.api.nvim_get_runtime_file(("lua/%s/init.lua"):format(path), false) > 0
end

---@type vantage.PickerImpl?
local resolved

--- Resolve the configured Picker. Called by the composition root before any
--- runtime side effects; invalid configuration is a setup error.
function M.setup()
  resolved = nil
  local name = Config.options.picker
  local mod = REGISTRY[name]
  if not mod then
    error(("vantage: unknown picker '%s'"):format(tostring(name)), 0)
  end
  local ok, impl = pcall(require, mod)
  if not ok then
    error(("vantage: picker '%s' unavailable (%s)"):format(name, tostring(impl)), 0)
  end
  if
    type(impl.capabilities) ~= "table"
    or type(impl.capabilities.preview) ~= "boolean"
    or type(impl.capabilities.command) ~= "boolean"
    or type(impl.pick) ~= "function"
    or type(impl.pick_plain) ~= "function"
  then
    error(("vantage: picker '%s' does not implement vantage.PickerImpl"):format(name), 0)
  end
  if impl.requires and not module_available(impl.requires) then
    error(("vantage: picker '%s' requires '%s'"):format(name, impl.requires), 0)
  end
  resolved = impl
end

--- The resolved Picker implementation. Internal to this module.
---@return vantage.PickerImpl
local function get()
  if not resolved then
    error("vantage: picker not initialized; call require('vantage').setup() first", 0)
  end
  return resolved
end

--- Test/initialization helper: forget the resolved Picker.
function M.reset()
  resolved = nil
end

--- The resolved Picker's static capability table.
---@return vantage.PickerCapabilities
function M.capabilities()
  return get().capabilities
end

--- Validate and normalize flow commands before handing them to a renderer.
---@param commands? vantage.PickerCommand[]
---@return vantage.PickerCommand[]?
local function normalize_commands(commands)
  if not commands or #commands == 0 then
    return nil
  end
  local seen = {}
  for index, command in ipairs(commands) do
    local lhs, rhs = command[1], command[2]
    if type(lhs) ~= "string" or lhs == "" then
      error(("vantage: picker command %d has no lhs"):format(index), 0)
    end
    if type(rhs) ~= "function" then
      error(("vantage: picker command '%s' rhs must be a function"):format(lhs), 0)
    end
    if seen[lhs] then
      error(("vantage: duplicate picker command lhs '%s'"):format(lhs), 0)
    end
    seen[lhs] = true
  end
  return commands
end

--- Render a preview-capable pick through the configured implementation.
---@param spec vantage.PickSpec
---@param opts vantage.PickOpts
---@return boolean empty
function M.pick(spec, opts)
  local impl = get()
  if type(opts.on_choice) ~= "function" then
    error("vantage: picker opts.on_choice must be a function", 0)
  end
  local commands = normalize_commands(opts.commands)
  if commands and not impl.capabilities.command then
    commands = nil
  end
  return impl.pick(spec, {
    on_choice = opts.on_choice,
    commands = commands,
  })
end

--- Render a plain selection through the configured implementation.
---@param items any[]
---@param opts vantage.PlainSelectOpts
---@param on_choice fun(item: any?, index?: integer)
function M.pick_plain(items, opts, on_choice)
  return get().pick_plain(items, opts, on_choice)
end

return M
