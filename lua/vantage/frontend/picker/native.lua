--- Native picker: vim.ui.select. Respects any global vim.ui.select override the
--- user may have installed (dressing.nvim, snacks' ui_select, …).
local M = {}

--- Render a streaming pick. `vim.ui.select` takes a fixed list, so the stream
--- is drained first and rendered through this implementation's own plain
--- select: waiting for the final list is what an engine with no stream surface
--- can do, and `many` degrades to one choice because `vim.ui.select` has no
--- marking.
---@param spec vantage.PickSpec
---@param opts vantage.PickOpts
function M.pick_fancy(spec, opts)
  local items, finished = {}, false
  spec.items(function(chunk)
    vim.list_extend(items, chunk)
  end, function()
    finished = true
  end)
  while not finished do
    vim.wait(1000, function()
      return finished
    end, 10)
  end
  M.pick_naive(items, {
    prompt = spec.prompt,
    format_item = function(entry)
      return entry.text
    end,
  }, function(entry)
    if entry then
      opts.on_choices({ entry })
    end
  end)
end

--- Pick from a plain list (no preview) on this engine: the live global
--- `vim.ui.select` — including any override — since native is defined as
--- "follow the environment's renderer".
---@param items any[]
---@param opts vantage.NaiveOpts
---@param on_choice fun(item: any?, index?: integer)
function M.pick_naive(items, opts, on_choice)
  vim.ui.select(items, {
    prompt = opts.prompt,
    format_item = opts.format_item,
  }, on_choice)
end

return M
