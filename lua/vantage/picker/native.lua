--- Native picker: vim.ui.select. Respects any global vim.ui.select override the
--- user may have installed (dressing.nvim, snacks' ui_select, …).
local M = {}

--- Render a spec's items with vim.ui.select. Returns true when the list is
--- empty (nothing shown); otherwise opens the picker and returns false. The
--- chosen item is passed to `on_choice` unchanged.
---@param spec vantage.PickSpec
---@param on_choice fun(item: any)
---@return boolean empty
local function select(spec, on_choice)
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
      on_choice(item)
    end
  end)
  return false
end

---@param spec vantage.PickSpec
---@param on_choice fun(item: any)
---@return boolean empty
function M.pick_agent(spec, on_choice)
  return select(spec, on_choice)
end

---@param spec vantage.PickSpec
---@param on_choice fun(item: any)
---@return boolean empty
function M.pick_kill(spec, on_choice)
  return select(spec, on_choice)
end

---@param spec vantage.PickSpec
---@param on_choice fun(item: any)
---@return boolean empty
function M.pick_annotation(spec, on_choice)
  return select(spec, on_choice)
end

--- Pick from a plain list (no preview) on this engine: the live global
--- `vim.ui.select` — including any override — since native is defined as
--- "follow the environment's renderer". Every plain choice in a flow then
--- shares one renderer family by construction.
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
