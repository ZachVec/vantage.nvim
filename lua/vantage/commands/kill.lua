--- The kill flow (`:Vantage kill`): pick an Agent or Group and kill it.
--- The entry's `kind` says which of the two the flow kills.
local Bridge = require("vantage.backend.bridge")
local Entries = require("vantage.frontend.entries")
local Picker = require("vantage.frontend.picker")
local Util = require("vantage.util")

local M = {}

local PROMPT = Util.picker_prompt

--- Agents (creation order) then Groups (sorted), or an empty list plus the
--- Driver's reason when the inventory could not be read.
---@return vantage.PickSpec
local function spec()
  return {
    prompt = PROMPT,
    items_provider = function()
      local inventory, err = Bridge.inventory()
      if inventory == nil then
        return {}, err
      end
      local agents = inventory.agents
      local groups = inventory.groups
      local items = vim
        .iter(agents)
        :map(function(agent)
          return Entries.agent(agent)
        end)
        :totable()
      vim.list_extend(
        items,
        vim
          .iter(groups)
          :map(function(group)
            return Entries.group(group)
          end)
          :totable()
      )
      return items
    end,
  }
end

--- Kill what the entry names, in place.
---@param entry vantage.picker.Entry
---@return boolean
---@return string?
local function kill(entry)
  if entry.kind == "group" then
    ---@cast entry vantage.picker.GroupEntry
    return Bridge.kill_group(entry.group)
  end
  ---@cast entry vantage.picker.AgentEntry
  return Bridge.kill_agent(entry.agent)
end

function M.run()
  local empty, err = Picker.pick(spec(), {
    on_choice = function(entry)
      local ok, kill_err = kill(entry)
      if not ok then
        Util.warn(kill_err or "failed to kill")
      end
    end,
  })
  if err then
    Util.warn(err)
  elseif empty then
    Util.warn("nothing to kill")
  end
end

return M
