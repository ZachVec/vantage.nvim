--- Plain selection UI: `vim.ui.select` flows that have nothing to preview — the
--- Agent-creation wizard's Tool and Group choice. The pluggable Picker
--- (`vantage.picker`) is reserved for selections with a pane preview (the Agent
--- list and the kill list); these two return only a bare name, so they use the
--- built-in `vim.ui.select` directly, exactly as `:Vantage prompt` already does.
local Backend = require("vantage.backend")
local Config = require("vantage.config")
local Util = require("vantage.util")

local M = {}

--- Sorted tool names. nil (with a warning) when cli.tools is empty.
---@return { name: string, text: string }[]?
local function tool_items()
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

--- Existing Groups + the "+ new group" sentinel. nil when there are no Groups
--- yet: the caller prompts for the name directly.
---@return { name: string, text: string }[]?
local function group_items()
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

--- Prompt for a new Group name (insert-mode cmdline) and invoke the callback.
--- Scheduled so a picker window can finish closing before the cmdline opens.
---@param callback fun(group: string)
local function prompt_new_group(callback)
  vim.schedule(function()
    local name = vim.trim(vim.fn.input({ prompt = "Group name: " }))
    if name ~= "" then
      callback(name)
    end
  end)
end

--- vim.ui.select over display items (each carrying a `text` string).
---@param items table[]
---@param on_choice fun(item: table)
local function select_items(items, on_choice)
  vim.ui.select(items, {
    prompt = Util.picker_prompt,
    format_item = function(item)
      return item.text
    end,
  }, function(item)
    if item then
      on_choice(item)
    end
  end)
end

---@param callback fun(tool_name: string)
function M.pick_tool(callback)
  local items = tool_items()
  if not items then
    return
  end
  select_items(items, function(item)
    callback(item.name)
  end)
end

---@param callback fun(group: string)
function M.pick_group(callback)
  local items = group_items()
  if not items then
    prompt_new_group(callback)
    return
  end
  select_items(items, function(item)
    if item.name == "+ new group" then
      prompt_new_group(callback)
    else
      callback(item.name)
    end
  end)
end

return M
