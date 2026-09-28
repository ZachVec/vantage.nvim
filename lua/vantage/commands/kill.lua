--- The kill flow (`:Vantage kill`): pick Agents and kill them. The list holds
--- only Agent entries, so killing a whole Group means marking every member.
local Backend = require("vantage.backend")
local Entries = require("vantage.frontend.entries")
local Picker = require("vantage.frontend.picker")
local Util = require("vantage.util")

local M = {}

local PROMPT = Util.picker_prompt

--- Agents in creation order, or nothing plus the Driver's reason when the
--- inventory could not be read.
---@return vantage.PickSpec
local function spec()
  return {
    prompt = PROMPT,
    many = true,
    preview = Entries.preview,
    items = function(emit, done)
      local inventory, err = Backend.inventory()
      if inventory == nil then
        Util.warn(err or "failed to read agents")
        return done()
      end
      local items = {}
      for _, agent in ipairs(inventory.agents) do
        items[#items + 1] = Entries.agent(agent)
      end
      emit(items)
      done()
    end,
  }
end

function M.run()
  Picker.pick_fancy(spec(), {
    on_choices = function(entries)
      for _, entry in ipairs(entries) do
        ---@cast entry vantage.picker.AgentEntry
        local ok, kill_err = Backend.kill_agent(entry.agent)
        if not ok then
          Util.warn(kill_err or "failed to kill")
        end
      end
    end,
  })
end

return M
