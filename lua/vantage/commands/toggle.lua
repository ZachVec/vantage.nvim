--- The toggle flow: hide/show the terminal; with no terminal, pick an Agent
--- (or create one) and open the terminal on it. Presence is all it owns —
--- and, as the only consumer of the terminal's buffer-local keys, it also
--- owns `cli.win.keys` application and the built-in action tokens.
local Bridge = require("vantage.backend.bridge")
local Config = require("vantage.config")
local Switch = require("vantage.commands.switch")
local Terminal = require("vantage.frontend.terminal")
local Util = require("vantage.util")

local M = {}

---@type table<string, fun()>
local ACTIONS = {
  toggle = function()
    M.run()
  end,
  switch = function()
    require("vantage.commands.switch").switch()
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
  pcall(vim.keymap.set, modes, lhs, rhs, {
    buffer = buffer,
    desc = keymap.desc,
    silent = true,
    nowait = true,
  })
end

--- Apply cli.win.keys to a terminal buffer at terminal creation.
---@param buffer integer
local function apply_keys(buffer)
  for _, keymap in ipairs(Config.options.cli.win.keys or {}) do
    apply_key(buffer, keymap)
  end
end

--- Toggle's tail: attach the terminal to the Agent and show it.
---@param agent vantage.Agent
local function attach(agent)
  local argv = Bridge.attach_command(agent.group, agent.target)
  if Terminal.open(argv) then
    apply_keys(Terminal.buffer)
  end
end

function M.run()
  if Terminal.toggle() then
    return
  end
  Switch.pick(attach)
end

return M
