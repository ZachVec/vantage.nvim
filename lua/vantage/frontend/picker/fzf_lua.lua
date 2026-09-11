--- fzf-lua picker implementation. Drives fzf-lua's native `fzf_exec`; because
--- fzf-lua returns display strings rather than the original objects, each entry
--- carries a numeric prefix that round-trips the item index — the same scheme
--- fzf-lua's own ui_select shim uses.
local M = {}

---@type string
M.requires = "fzf-lua"

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

--- The numeric prefix exists only to round-trip entries back to items; hide it
--- from the list with `--with-nth`, the way fzf-lua's own providers do. fzf
--- still hands the original line to actions, so the round-trip holds. No
--- `--nth`: fzf evaluates it against the *transformed* line, so `--nth=2..`
--- would drop the entry's own first field and leave a single-token path with
--- an empty search scope.
local PREFIX_HIDDEN = { ["--with-nth"] = "2.." }

--- Recover the 1-based item index from one returned entry string.
---@param entry string
---@return integer?
local function index_of(entry)
  return tonumber(entry:match("^%s*(%d+)%."))
end

--- Map fzf's returned display strings back to their items, in returned order.
---@param items table[]
---@param selected string[]?
---@return table[]
local function items_of(items, selected)
  local out = {}
  for _, entry in ipairs(selected or {}) do
    local item = items[index_of(entry) or 0]
    if item then
      out[#out + 1] = item
    end
  end
  return out
end

--- Translate a Neovim key notation into fzf's action name.
---@param lhs string
---@return string
local function fzf_key(lhs)
  local key = lhs:lower()
  local inner = key:match("^<(.+)>$")
  if not inner then
    return key
  end
  local parts = vim.split(inner, "-", { plain = true })
  local base = table.remove(parts)
  local base_names = {
    cr = "enter",
    enter = "enter",
    esc = "esc",
    tab = "tab",
    space = "space",
    bs = "bspace",
  }
  base = base_names[base] or base
  local modifiers = { c = "ctrl", m = "alt", s = "shift" }
  local out = {}
  for _, modifier in ipairs(parts) do
    out[#out + 1] = modifiers[modifier] or modifier
  end
  out[#out + 1] = base
  return table.concat(out, "-")
end

---@type vantage.PickerCapabilities
M.capabilities = {
  preview = true,
  command = true,
  multi = true,
}

--- Open an fzf_exec picker over `spec` with a live item list and the flow's
--- neutral picker commands.
---@param spec vantage.PickSpec
---@param opts vantage.PickOpts
---@return boolean empty
function M.pick(spec, opts)
  local state = { items = spec.items_provider() }
  if #state.items == 0 then
    return true
  end

  local function content(cb)
    emit(state.items, cb)
  end

  local function item_of(selected)
    return items_of(state.items, selected)[1]
  end

  ---@type table<string, any>
  local actions = {
    ["default"] = function(selected)
      local item = item_of(selected)
      if item then
        vim.schedule(function()
          opts.on_choice(item)
        end)
      end
    end,
  }
  for _, command in ipairs(opts.commands or {}) do
    actions[fzf_key(command[1])] = {
      fn = function(selected)
        local changed = command[2]({
          item = item_of(selected),
          items = state.items,
        })
        if changed then
          state.items = spec.items_provider()
          if #state.items == 0 then
            fzf().utils.fzf_exit()
          end
        end
      end,
      reload = true,
    }
  end

  fzf().fzf_exec(content, {
    prompt = spec.prompt,
    fzf_opts = PREFIX_HIDDEN,
    winopts = { on_close = opts.on_close },
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

--- Open an fzf picker with `--multi`: tab marks rows and Enter confirms the
--- marked set (fzf returns the row under the cursor when nothing is marked).
---@param spec vantage.PickSpec
---@param opts vantage.PickMultiOpts
---@return boolean empty
function M.pick_multi(spec, opts)
  local items = spec.items_provider()
  if #items == 0 then
    return true
  end

  fzf().fzf_exec(function(cb)
    emit(items, cb)
  end, {
    prompt = spec.prompt,
    fzf_opts = vim.tbl_extend("force", { ["--multi"] = true }, PREFIX_HIDDEN),
    winopts = { on_close = opts.on_close },
    actions = {
      ["default"] = function(selected)
        local chosen = items_of(items, selected)
        if #chosen > 0 then
          vim.schedule(function()
            opts.on_choices(chosen)
          end)
        end
      end,
    },
    preview = function(selected)
      local item = items_of(items, selected)[1]
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

--- Pick from a plain list (no preview) on this engine: fzf-lua's own
--- ui_select implementation — the same function fzf-lua registers as a global
--- `vim.ui.select` override.
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
