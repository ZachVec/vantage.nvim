--- Shared picker domain: builds the rich items each picker implementation
--- renders. Every item carries a `text` display string plus whatever domain
--- fields its callback needs; implementations own only the rendering and the
--- recovery of the chosen item. Free-text Group entry lives here because it is
--- shared across every implementation.
local Backend = require("vantage.backend")
local Config = require("vantage.config")
local Util = require("vantage.util")

local M = {}

--- The picker prompt: a single angle-right glyph (U+F105, e.g. Nerd Font).
M.prompt = vim.fn.nr2char(0xF105)

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

--- Sorted tool names. nil (with a warning) when cli.tools is empty.
---@return { name: string, text: string }[]?
function M.tool_items()
  local names = {}
  for name in pairs(Config.options.cli.tools) do
    names[#names + 1] = name
  end
  table.sort(names)
  if #names == 0 then
    Util.warn("no tools configured (cli.tools)")
    return nil
  end
  local items = {}
  for _, name in ipairs(names) do
    items[#items + 1] = { name = name, text = name }
  end
  return items
end

--- Sorted prompt names. nil (with a warning) when prompts is empty.
---@return { name: string, text: string }[]?
function M.prompt_items()
  local names = {}
  for name in pairs(Config.options.prompts) do
    names[#names + 1] = name
  end
  table.sort(names)
  if #names == 0 then
    Util.warn("no prompts configured (setup { prompts = { ... } })")
    return nil
  end
  local items = {}
  for _, name in ipairs(names) do
    items[#items + 1] = { name = name, text = name }
  end
  return items
end

--- Existing Groups + the "+ new group" sentinel. nil when there are no Groups
--- yet: the caller skips the picker and prompts for the name directly.
---@return { name: string, text: string }[]?
function M.group_items()
  local groups = Backend.get().groups()
  if #groups == 0 then
    return nil
  end
  local items = {}
  for _, group in ipairs(groups) do
    items[#items + 1] = { name = group, text = group }
  end
  items[#items + 1] = { name = "+ new group", text = "+ new group" }
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

--- Prompt for a new Group name (insert-mode cmdline) and invoke the callback.
--- Scheduled so a picker window can finish closing before the cmdline opens.
---@param callback fun(group: string)
function M.prompt_new_group(callback)
  vim.schedule(function()
    local name = vim.trim(vim.fn.input({ prompt = "Group name: " }))
    if name ~= "" then
      callback(name)
    end
  end)
end

return M
