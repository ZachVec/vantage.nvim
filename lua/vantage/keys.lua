--- Terminal keymap tokens: the built-in actions a `cli.win.keys` rhs string
--- may name. A rhs string matching one of these resolves to the action
--- function; any other rhs (a key sequence / <cmd> string or a Lua function)
--- is passed verbatim to vim.keymap.set.
local M = {}

---@type table<string, fun()>
local ACTIONS = {
  toggle = function()
    require("vantage.commands").toggle()
  end,
  switch = function()
    require("vantage.commands.agent").switch()
  end,
  kill = function()
    require("vantage.commands.agent").kill()
  end,
  prompt = function()
    require("vantage.commands.prompt").run()
  end,
}

--- Resolve a cli.win.keys rhs: a string naming a built-in action becomes that
--- action's function; anything else (including other strings and Lua
--- functions) is returned unchanged for vim.keymap.set.
---@param rhs any
---@return any
function M.resolve(rhs)
  if type(rhs) == "string" then
    return ACTIONS[rhs] or rhs
  end
  return rhs
end

return M
