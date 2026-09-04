--- fzf-lua picker implementation. Drives fzf-lua's native `fzf_exec`; because
--- fzf-lua returns display strings rather than the original objects, each entry
--- carries a numeric prefix that round-trips the item index — the same scheme
--- fzf-lua's own ui_select shim uses.
local M = {}

local function fzf()
  return require("fzf-lua")
end

--- "1. text" entries; the prefix encodes the 1-based index so a returned
--- display string maps back to its item.
---@param items table[]
---@return string[]
local function entries(items)
  local out = {}
  for i, item in ipairs(items) do
    out[i] = ("%d. %s"):format(i, item.text)
  end
  return out
end

--- Recover the 1-based item index from a returned entry string.
---@param selected string[]
---@return integer?
local function index_of(selected)
  local entry = selected and selected[1]
  if not entry then
    return nil
  end
  return tonumber(entry:match("^%s*(%d+)%."))
end

--- Preview the selected item through the spec's preview thunk as plain text;
--- empty string when the item has nothing to preview.
---@param spec vantage.PickSpec
---@param items table[]
---@return fun(selected: string[]): string
local function preview(spec, items)
  return function(selected)
    local item = items[index_of(selected)]
    if not item then
      return ""
    end
    local lines = spec.preview and spec.preview(item)
    if not lines then
      return ""
    end
    return table.concat(lines, "\n")
  end
end

--- Open an fzf_exec picker over `spec` with a static item list (no reload).
--- `extract` maps a chosen item to the value `on_choice` receives.
---@param spec vantage.PickSpec
---@param extract fun(item: any): any
---@param on_choice fun(value: any)
---@return boolean empty
local function pick_static(spec, extract, on_choice)
  local items = spec.items_provider()
  if #items == 0 then
    return true
  end
  fzf().fzf_exec(entries(items), {
    prompt = spec.prompt,
    actions = {
      ["default"] = function(selected)
        local item = items[index_of(selected)]
        if item then
          vim.schedule(function()
            on_choice(extract(item))
          end)
        end
      end,
    },
    preview = preview(spec, items),
  })
  return false
end

---@param spec vantage.PickSpec
---@param on_choice fun(choice: { kind: "agent"|"tool", agent?: vantage.Agent, tool?: string, focused?: boolean })
---@return boolean empty
function M.pick_agent(spec, on_choice)
  return pick_static(spec, function(item)
    return item
  end, on_choice)
end

---@param spec vantage.PickSpec
---@param on_choice fun(target: string)
---@return boolean empty
function M.pick_kill(spec, on_choice)
  return pick_static(spec, function(item)
    return item.target
  end, on_choice)
end

---@param spec vantage.PickSpec
---@param on_choice fun(annotation: vantage.Annotation)
---@return boolean empty
function M.pick_annotation(spec, on_choice)
  local state = { items = spec.items_provider() }
  if #state.items == 0 then
    return true
  end

  -- Emit the cached items. `reload` re-invokes this; the ctrl-x action
  -- refreshes `state.items` beforehand, so the list is re-read exactly once
  -- per delete rather than on every invocation.
  local function content(cb)
    for i, item in ipairs(state.items) do
      cb(("%d. %s"):format(i, item.text))
    end
    cb(nil)
  end

  local function item_of(selected)
    return state.items[index_of(selected)]
  end

  fzf().fzf_exec(content, {
    prompt = spec.prompt,
    actions = {
      ["default"] = function(selected)
        local item = item_of(selected)
        if item then
          vim.schedule(function()
            on_choice(item.annotation)
          end)
        end
      end,
      ["ctrl-x"] = {
        fn = function(selected)
          local item = item_of(selected)
          if item then
            spec.on_delete(item.annotation)
          end
          state.items = spec.items_provider()
          if #state.items == 0 then
            require("fzf-lua").utils.fzf_exit()
          end
        end,
        reload = true,
      },
    },
    preview = function(selected)
      local item = item_of(selected)
      if not item then
        return ""
      end
      local lines = spec.preview(item)
      if not lines then
        return ""
      end
      return table.concat(lines, "\n")
    end,
  })
  return false
end

--- Pick from a plain list (no preview) on this engine: fzf-lua's own
--- ui_select implementation — the same function fzf-lua registers as a global
--- `vim.ui.select` override — so the wizard stays on the fzf renderer family.
---@param items any[]
---@param opts vantage.PlainSelectOpts
---@param on_choice fun(item: any?, index?: integer)
function M.pick_plain(items, opts, on_choice)
  require("fzf-lua.providers.ui_select").ui_select(items, {
    prompt = opts.prompt,
    format_item = opts.format_item,
  }, on_choice)
end

return M
