--- Native picker: vim.ui.select. Respects any global vim.ui.select override the
--- user may have installed (dressing.nvim, snacks' ui_select, …).
local Items = require("vantage.picker.items")
local Util = require("vantage.util")

local M = {}

---@param callback fun(choice: { kind: "agent"|"tool", agent?: vantage.Agent, tool?: string, focused?: boolean })
function M.pick_agent(callback)
  local items = Items.agent_items()
  if #items == 0 then
    Util.warn("no agents and no tools configured (cli.tools)")
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

--- Native has no preview and no in-picker keymaps: `vim.ui.select` offers only
--- selection, so the `delete` callback is unused here.
---@param opts { select: fun(annotation: vantage.Annotation), delete: fun(annotation: vantage.Annotation) }
function M.pick_annotation(opts)
  local items = Items.annotation_items()
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
      opts.select(item.annotation)
    end
  end)
end

--- Pick from a plain list (no preview) on this engine: the live global
--- `vim.ui.select` — including any override — since native is defined as
--- "follow the environment's renderer". Every plain choice in a flow then
--- shares one renderer family by construction.
---@param items any[]
---@param opts { prompt?: string, format_item?: fun(item: any): string }
---@param on_choice fun(item: any?, index?: integer)
function M.pick_plain(items, opts, on_choice)
  vim.ui.select(items, {
    prompt = opts.prompt,
    format_item = opts.format_item,
  }, on_choice)
end

return M
