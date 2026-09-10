--- Native picker: vim.ui.select. Respects any global vim.ui.select override the
--- user may have installed (dressing.nvim, snacks' ui_select, …).
local M = {}

---@type vantage.PickerCapabilities
M.capabilities = {
  preview = false,
  command = false,
}

--- Render a spec's items with vim.ui.select. Commands are ignored because
--- vim.ui.select has no custom-key surface.
---@param spec vantage.PickSpec
---@param opts vantage.PickOpts
---@return boolean empty
function M.pick(spec, opts)
  local items = spec.items_provider()
  if #items == 0 then
    return true
  end
  vim.ui.select(items, {
    prompt = spec.prompt,
    format_item = function(item)
      return item:format()
    end,
  }, function(item)
    if item then
      opts.on_choice(item)
    end
  end)
  return false
end

--- Pick from a plain list (no preview) on this engine: the live global
--- `vim.ui.select` — including any override — since native is defined as
--- "follow the environment's renderer".
---@param items any[]
---@param opts vantage.PlainSelectOpts
---@param on_choice fun(item: any?, index?: integer)
function M.pick_plain(items, opts, on_choice)
  vim.ui.select(items, {
    prompt = opts.prompt,
    format_item = opts.format_item,
  }, on_choice)
end

return M
