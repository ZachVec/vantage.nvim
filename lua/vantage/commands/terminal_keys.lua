--- Install cli.win.keys into the Vantage terminal buffer.
local Actions = require("vantage.commands.actions")
local Config = require("vantage.config")
local Util = require("vantage.util")

local M = {}

--- Apply one cli.win.keys entry buffer-locally.
---@param buffer integer
---@param keymap table
local function apply_key(buffer, keymap)
  local lhs, rhs = keymap[1], keymap[2]
  if not lhs or rhs == nil then
    Util.warn("keymap entry must be a 4-tuple { lhs, rhs, mode?, desc? }")
    return
  end
  rhs = Actions.resolve(rhs)
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
