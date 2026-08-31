--- Selection UI. v0 uses vim.ui.select directly; the module boundary is the
--- swap seam for future pickers (fzf-lua, snacks, …).
local Backend = require("vantage.backend")
local Config = require("vantage.config")
local Util = require("vantage.util")

local M = {}

---@param agent vantage.Agent
---@return string
local function fmt_agent(agent)
  return ("%s  %s  [%s]"):format(agent.cmd, Util.tilde(agent.cwd), agent.group)
end

--- Pick an Agent (or the "+ new agent" entry).
---@param callback fun(choice: { kind: "agent"|"new", agent?: vantage.Agent })
function M.pick_agent(callback)
  local agents = Backend.get().list()
  if #agents == 0 then
    Util.warn("no agents yet — use :Vantage toggle to create")
    return
  end
  local items = {}
  for _, agent in ipairs(agents) do
    items[#items + 1] = { kind = "agent", agent = agent }
  end
  items[#items + 1] = { kind = "new" }
  vim.ui.select(items, {
    prompt = "Vantage › agent",
    format_item = function(item)
      if item.kind == "new" then
        return "+ new agent"
      end
      return fmt_agent(item.agent)
    end,
  }, function(choice)
    if choice then
      callback(choice)
    end
  end)
end

--- Pick a Tool name from cli.tools.
---@param callback fun(tool_name: string)
function M.pick_tool(callback)
  local tool_names = {}
  for name in pairs(Config.options.cli.tools) do
    tool_names[#tool_names + 1] = name
  end
  table.sort(tool_names)
  if #tool_names == 0 then
    Util.warn("no tools configured (cli.tools)")
    return
  end
  vim.ui.select(tool_names, { prompt = "Vantage › tool" }, function(tool_name)
    if tool_name then
      callback(tool_name)
    end
  end)
end

--- Pick an existing Group or type a new name.
--- With no Groups yet (first Agent), skip the picker and go straight to input.
---@param callback fun(group: string)
function M.pick_group(callback)
  local groups = Backend.get().groups()
  if #groups == 0 then
    local name = vim.trim(vim.fn.input({ prompt = "Group name: " }))
    if name ~= "" then
      callback(name)
    end
    return
  end
  local items = vim.deepcopy(groups)
  items[#items + 1] = "+ new group"
  vim.ui.select(items, { prompt = "Vantage › group" }, function(choice)
    if not choice then
      return
    end
    if choice == "+ new group" then
      -- Free-text name: use input() directly (insert-mode cmdline), since a
      -- vim.ui.input override may open in normal mode.
      local name = vim.trim(vim.fn.input({ prompt = "Group name: " }))
      if name ~= "" then
        callback(name)
      end
    else
      callback(choice)
    end
  end)
end

--- Pick an Agent or Group to kill.
---@param callback fun(target: string)
function M.pick_kill(callback)
  local items = {}
  for _, agent in ipairs(Backend.get().list()) do
    items[#items + 1] = { target = agent.target, label = fmt_agent(agent) }
  end
  for _, group in ipairs(Backend.get().groups()) do
    items[#items + 1] = { target = group, label = ("group %s"):format(group) }
  end
  if #items == 0 then
    Util.warn("nothing to kill")
    return
  end
  vim.ui.select(items, {
    prompt = "Vantage › kill",
    format_item = function(item)
      return item.label
    end,
  }, function(choice)
    if choice then
      callback(choice.target)
    end
  end)
end

return M
