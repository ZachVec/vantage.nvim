--- Built-in actions available inside the Vantage terminal.
---
--- `cli.win.keys` entries are resolved through ACTIONS and installed into the
--- terminal buffer. Command modules are required lazily so this module has no
--- module-load cycle with attach.lua.
local Config = require("vantage.config")
local Util = require("vantage.util")

local M = {}

---@type table<string, fun()>
local ACTIONS = {
  toggle = function()
    require("vantage.commands.attach").toggle()
  end,
  switch = function()
    require("vantage.commands.attach").switch()
  end,
  prompt = function()
    require("vantage.commands.prompt").run()
  end,
}

--- Resolve a cli.win.keys rhs: a string naming a built-in action becomes that
--- action's function; anything else is returned unchanged.
---@param rhs any
---@return any
function M.resolve(rhs)
  if type(rhs) == "string" then
    return ACTIONS[rhs] or rhs
  end
  return rhs
end

--- Apply one cli.win.keys entry buffer-locally.
---@param buffer integer
---@param keymap table
local function apply_key(buffer, keymap)
  local lhs, rhs = keymap[1], keymap[2]
  if not lhs or rhs == nil then
    Util.warn("keymap entry must be a 4-tuple { lhs, rhs, mode?, desc? }")
    return
  end
  rhs = M.resolve(rhs)
  local mode = keymap.mode or "n"
  if type(mode) == "table" then
    mode = table.concat(mode, "")
  end
  local modes = vim.split(mode, "", { plain = true })
  local ok, err = pcall(vim.keymap.set, modes, lhs, rhs, {
    buffer = buffer,
    desc = keymap.desc,
    silent = true,
    nowait = true,
  })
  if not ok then
    Util.warn(("invalid terminal keymap '%s': %s"):format(lhs, tostring(err)))
  end
end

--- Apply cli.win.keys to a terminal buffer at terminal creation.
---@param buffer integer
function M.apply(buffer)
  for _, keymap in ipairs(Config.options.cli.win.keys or {}) do
    apply_key(buffer, keymap)
  end
end

return M
