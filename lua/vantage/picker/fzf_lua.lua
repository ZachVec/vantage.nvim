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
    cb(("%d. %s"):format(i, item.text))
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

--- Open an fzf_exec picker over `spec` with a live item list: a c-x action
--- (`alt`, the flow's `on_delete` specialization, optional) removes the
--- current row's domain value in place, then re-reads `items_provider` and
--- reloads the list, exiting when nothing remains. When `spec.scope` exists,
--- its transform applies on every read while the c-g toggle is on (default)
--- and the picker binds ctrl-g to flip it in place. `extract` maps a chosen
--- item to the value `on_choice` receives.
---@param spec vantage.PickSpec
---@param extract fun(item: any): any
---@param on_choice fun(value: any)
---@param alt? fun(item: any) the c-x removal action; rows with nothing to
---   remove (Tool rows) are ignored by the call site
---@return boolean empty
local function pick_static(spec, extract, on_choice, alt)
  local scope_on = spec.scope ~= nil
  local function read()
    local all = spec.items_provider()
    if scope_on and spec.scope then
      return spec.scope(all)
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
          on_choice(extract(item))
        end)
      end
    end,
  }
  if alt then
    actions["ctrl-x"] = {
      fn = function(selected)
        local item = item_of(selected)
        if item then
          alt(item)
        end
        state.items = read()
        if #state.items == 0 then
          require("fzf-lua").utils.fzf_exit()
        end
      end,
      reload = true,
    }
  end
  if spec.scope then
    actions["ctrl-g"] = {
      fn = function()
        scope_on = not scope_on
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
      local lines = spec.preview and spec.preview(item)
      if not lines then
        return ""
      end
      return table.concat(lines, "\n")
    end,
  })
  return false
end

---@param spec vantage.PickSpec
---@param on_choice fun(choice: { kind: "agent"|"tool", agent?: vantage.Agent, tool?: string, focused?: boolean })
---@return boolean empty
function M.pick_agent(spec, on_choice)
  return pick_static(
    spec,
    function(item)
      return item
    end,
    on_choice,
    function(item)
      if item.kind == "agent" and not item.focused and spec.on_delete then
        spec.on_delete(item.agent)
      end
    end
  )
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
  return pick_static(
    spec,
    function(item)
      return item.annotation
    end,
    on_choice,
    function(item)
      spec.on_delete(item.annotation)
    end
  )
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
