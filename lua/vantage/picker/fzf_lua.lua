--- fzf-lua picker implementation. Drives fzf-lua's native `fzf_exec`; because
--- fzf-lua returns display strings rather than the original objects, each entry
--- carries a numeric prefix that round-trips the item index — the same scheme
--- fzf-lua's own ui_select shim uses.
local M = {}

local function fzf()
  return require("fzf-lua")
end

--- "1. text" entries; the prefix encodes the 1-based index so a returned
--- display string maps back to its item. Emitted one per callback, matching
--- fzf-lua's function-contents contract (see docs/gotchas.md).
---@param items table[]
---@param cb fun(line?: string)
local function emit(items, cb)
  for i, item in ipairs(items) do
    cb(("%d. %s"):format(i, item:format()))
  end
  cb(nil)
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

--- Open an fzf_exec picker over `spec` with a live item list. When `deletable`
--- is set, a c-x action removes the current row in place via `item:delete()`
--- — re-reading `items_provider` and reloading the list only when it reports a
--- removal, exiting when nothing remains. When `spec.group` exists, its
--- filter applies on every read while the c-g toggle is on (default) and
--- the picker binds ctrl-g to flip it in place. The chosen item is passed to
--- `on_choice` unchanged.
---@param spec vantage.PickSpec
---@param on_choice fun(item: any)
---@param deletable? boolean whether the picker binds c-x in-place removal
---@return boolean empty
local function pick_static(spec, on_choice, deletable)
  local group_on = spec.group ~= nil
  local function read()
    local all = spec.items_provider()
    if group_on then
      return spec.group(all)
    end
    return all
  end
  local state = { items = read() }
  if #state.items == 0 then
    return true
  end

  local function content(cb)
    emit(state.items, cb)
  end

  local function item_of(selected)
    return state.items[index_of(selected)]
  end

  local actions = {
    ["default"] = function(selected)
      local item = item_of(selected)
      if item then
        vim.schedule(function()
          on_choice(item)
        end)
      end
    end,
  }
  if deletable then
    actions["ctrl-x"] = {
      fn = function(selected)
        local item = item_of(selected)
        if item and item:delete() then
          state.items = read()
          if #state.items == 0 then
            require("fzf-lua").utils.fzf_exit()
          end
        end
      end,
      reload = true,
    }
  end
  if spec.group then
    actions["ctrl-g"] = {
      fn = function()
        group_on = not group_on
        state.items = read()
        if #state.items == 0 then
          require("fzf-lua").utils.fzf_exit()
        end
      end,
      reload = true,
    }
  end

  fzf().fzf_exec(content, {
    prompt = spec.prompt,
    actions = actions,
    preview = function(selected)
      local item = item_of(selected)
      if not item then
        return ""
      end
      local lines = item:preview()
      if not lines then
        return ""
      end
      return table.concat(lines, "\n")
    end,
  })
  return false
end

---@param spec vantage.PickSpec
---@param on_choice fun(item: any)
---@return boolean empty
function M.pick_agent(spec, on_choice)
  return pick_static(spec, on_choice, true)
end

---@param spec vantage.PickSpec
---@param on_choice fun(item: any)
---@return boolean empty
function M.pick_kill(spec, on_choice)
  return pick_static(spec, on_choice)
end

---@param spec vantage.PickSpec
---@param on_choice fun(item: any)
---@return boolean empty
function M.pick_annotation(spec, on_choice)
  return pick_static(spec, on_choice, true)
end

--- Pick from a plain list (no preview) on this engine: fzf-lua's own
--- ui_select implementation — the same function fzf-lua registers as a global
--- `vim.ui.select` override — so plain selects stay on the fzf renderer family.
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
