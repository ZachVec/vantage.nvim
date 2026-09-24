--- The built-in Terminal actions: what a `cli.win.keys` `rhs` string may name.
---
--- The Terminal installs `cli.win.keys` on its buffer and asks this module what
--- each string means; the token table lives here because a token's meaning is a
--- command. Command modules are required lazily so this module has no
--- module-load cycle with attach.lua.

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
  files = function()
    require("vantage.commands.gather").files()
  end,
  buffers = function()
    require("vantage.commands.gather").buffers()
  end,
}

--- Resolve a cli.win.keys rhs: a string naming a built-in action becomes that
--- action's function; anything else is returned unchanged. The Terminal takes
--- this as its `resolve`.
---@param rhs any
---@return any
function M.resolve(rhs)
  if type(rhs) == "string" then
    return ACTIONS[rhs] or rhs
  end
  return rhs
end

return M
