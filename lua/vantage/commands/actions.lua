--- Built-in terminal action tokens used by cli.win.keys.
---
--- The map lives outside attach.lua so terminal-key installation can
--- consume it without a module-level dependency cycle.
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

return M
