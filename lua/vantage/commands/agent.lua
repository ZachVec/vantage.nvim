--- Agent actions: switch, kill, and the pick flow behind the Agent picker and
--- toggle's open path. The domain work of creating an Agent from a Tool row
--- lives in the Tool item's `activate` (see vantage.select).
local Client = require("vantage.client")
local Picker = require("vantage.picker")
local Select = require("vantage.select")
local Util = require("vantage.util")

local M = {}

--- Pick an Agent to act on (focus or re-target), create one from a trailing
--- Tool row, or confirm the pinned `(focused)` row, which deliberately does
--- nothing. Each item's `activate(after)` runs the tail action on its domain
--- object — `Client.focus` (toggle's open path) materializes and shows a
--- terminal, `Client.retarget` (switch) only re-points an existing one — and
--- the Tool item's `activate` creates the Agent first.
---@param after fun(agent: vantage.Agent)
---@param from_terminal boolean
function M.pick_or_new(after, from_terminal)
  local empty = Picker.get().pick_agent(Select.agent_spec(from_terminal), function(item)
    item:activate(after)
  end)
  if empty then
    Util.warn("no agents and no tools configured (cli.tools)")
  end
end

--- `switch` (terminal keymap token): re-point the live terminal to an Agent,
--- interactively.
function M.switch()
  M.pick_or_new(Client.retarget, true)
end

--- `kill` (terminal keymap token): kill a Group or Agent, interactively.
--- Selecting a row calls its `delete()` — an Agent kills itself, a Group kills
--- the whole Group.
function M.kill()
  local empty = Picker.get().pick_kill(Select.kill_spec(true), function(item)
    item:delete()
  end)
  if empty then
    Util.warn("nothing to kill")
  end
end

return M
