--- The kill flow (`:Vantage kill`): pick an Agent or Group and kill it.
--- KillAgentEntry and KillGroupEntry are the two row kinds; both implement the
--- KillEntry protocol (format/preview/delete).
local Bridge = require("vantage.backend.bridge")
local Display = require("vantage.frontend.display")
local Picker = require("vantage.frontend.picker")
local Util = require("vantage.util")

local M = {}

local PROMPT = Util.picker_prompt

---@class vantage.KillEntry One picker row in the kill flow.
---@field format fun(self: vantage.KillEntry): string
---@field preview fun(self: vantage.KillEntry): string[]?
---@field delete fun(self: vantage.KillEntry): boolean, string?

---@class vantage.KillAgentEntry : vantage.KillEntry
---@field agent vantage.Agent
local KillAgentEntry = {}
KillAgentEntry.__index = KillAgentEntry

---@param agent vantage.Agent
---@return vantage.KillAgentEntry
function KillAgentEntry.new(agent)
  return setmetatable({ agent = agent }, KillAgentEntry)
end

function KillAgentEntry:format()
  return Display.format_agent(self.agent)
end

function KillAgentEntry:preview()
  local lines, err = Bridge.capture(self.agent)
  if lines == nil then
    return { err or "failed to capture agent" }
  end
  return lines
end

function KillAgentEntry:delete()
  return Bridge.kill_agent(self.agent)
end

---@class vantage.KillGroupEntry : vantage.KillEntry
---@field group string
local KillGroupEntry = {}
KillGroupEntry.__index = KillGroupEntry

---@param group string
---@return vantage.KillGroupEntry
function KillGroupEntry.new(group)
  return setmetatable({ group = group }, KillGroupEntry)
end

function KillGroupEntry:format()
  return ("group %s"):format(self.group)
end

function KillGroupEntry:preview()
  return nil
end

function KillGroupEntry:delete()
  return Bridge.kill_group(self.group)
end

--- Agents (creation order) then Groups (sorted). May be empty.
---@param state? { error?: string }
---@return vantage.PickSpec
local function spec(state)
  state = state or {}
  return {
    prompt = PROMPT,
    items_provider = function()
      local snapshot, err = Bridge.agents(nil)
      state.error = err
      if snapshot == nil then
        return {}
      end
      local agents = snapshot.agents
      local groups = snapshot.groups
      local items = vim
        .iter(agents)
        :map(function(agent)
          return KillAgentEntry.new(agent)
        end)
        :totable()
      vim.list_extend(
        items,
        vim
          .iter(groups)
          :map(function(group)
            return KillGroupEntry.new(group)
          end)
          :totable()
      )
      return items
    end,
  }
end

function M.run()
  local state = {}
  local empty = Picker.pick(spec(state), {
    on_choice = function(entry)
      local ok, err = entry:delete()
      if not ok then
        Util.warn(err)
      end
    end,
  })
  if state.error then
    Util.warn(state.error)
  elseif empty then
    Util.warn("nothing to kill")
  end
end

return M
