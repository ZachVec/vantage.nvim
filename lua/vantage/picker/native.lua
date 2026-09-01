--- Native picker: vim.ui.select. Respects any global vim.ui.select override the
--- user may have installed (dressing.nvim, snacks' ui_select, …).
local Items = require("vantage.picker.items")

local M = {}

---@param callback fun(choice: { kind: "agent"|"new", agent?: vantage.Agent })
function M.pick_agent(callback)
  local items = Items.agent_items()
  if not items then
    return
  end
  vim.ui.select(items, {
    prompt = Items.prompt,
    format_item = function(item)
      return item.text
    end,
  }, function(choice)
    if choice then
      callback(choice)
    end
  end)
end

---@param callback fun(target: string)
function M.pick_kill(callback)
  local items = Items.kill_items()
  if not items then
    return
  end
  vim.ui.select(items, {
    prompt = Items.prompt,
    format_item = function(item)
      return item.text
    end,
  }, function(item)
    if item then
      callback(item.target)
    end
  end)
end

return M
