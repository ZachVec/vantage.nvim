--- Shared picker domain: builds the rich items each picker implementation
--- renders (the Agent list and the kill list). Every item carries a `text`
--- display string plus whatever domain fields its callback needs;
--- implementations own only the rendering and the recovery of the chosen item.
--- Plain selections with nothing to preview (the Tool and Group choice) live in
--- `vantage.select`.
local Backend = require("vantage.backend")
local Util = require("vantage.util")

local M = {}

--- The picker prompt: a single angle-right glyph (U+F105, e.g. Nerd Font).
M.prompt = Util.picker_prompt

---@param agent vantage.Agent
---@return string
function M.format_agent(agent)
  return ("%s  %s  [%s]"):format(agent.cmd, Util.tilde(agent.cwd), agent.group)
end

--- Agent items + the "+ new agent" sentinel. nil (with a warning) when there
--- are no Agents yet.
---@return { kind: "agent"|"new", agent?: vantage.Agent, text: string }[]?
function M.agent_items()
  local agents = Backend.get().list()
  if #agents == 0 then
    Util.warn("no agents yet — use :Vantage toggle to create")
    return nil
  end
  local items = {}
  for _, agent in ipairs(agents) do
    items[#items + 1] = { kind = "agent", agent = agent, text = M.format_agent(agent) }
  end
  items[#items + 1] = { kind = "new", text = "+ new agent" }
  return items
end

--- Agents (as { target, agent }) + Groups (as { target }) to kill.
--- nil (with a warning) when there is nothing to kill.
---@return { target: string, agent?: vantage.Agent, text: string }[]?
function M.kill_items()
  local items = {}
  for _, agent in ipairs(Backend.get().list()) do
    items[#items + 1] = { target = agent.target, agent = agent, text = M.format_agent(agent) }
  end
  for _, group in ipairs(Backend.get().groups()) do
    items[#items + 1] = { target = group, text = ("group %s"):format(group) }
  end
  if #items == 0 then
    Util.warn("nothing to kill")
    return nil
  end
  return items
end

return M
