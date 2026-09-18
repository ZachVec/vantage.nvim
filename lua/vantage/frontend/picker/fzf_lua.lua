--- fzf-lua picker implementation. Drives fzf-lua's native `fzf_exec`; because
--- fzf-lua returns display strings rather than the original objects, each
--- emitted line carries a numeric prefix that round-trips the entry index —
--- the same scheme fzf-lua's own ui_select shim uses. The pick's item stream is
--- pushed into fzf's stdin as it arrives: fzf-lua's function contents hands
--- every line of a batch to `on_write` (one pipe write per batch) and takes nil
--- as end of input, over a pipe that stays open until then (see
--- docs/gotchas.md).
local M = {}

---@type string
M.requires = "fzf-lua"

local function fzf()
  return require("fzf-lua")
end

--- "1. text" lines; the prefix encodes the 1-based index so a returned display
--- string maps back to its entry. Emitted one per callback, matching fzf-lua's
--- function-contents contract.
local PREFIX = "%d. %s"

--- The numeric prefix exists only to round-trip a line back to its entry; hide
--- it from the list with `--with-nth`, the way fzf-lua's own providers do. fzf
--- still hands the original line to actions, so the round-trip holds. No
--- `--nth`: fzf evaluates it against the *transformed* line, so `--nth=2..`
--- would drop the line's own first field and leave a single-token path with an
--- empty search scope.
local PREFIX_HIDDEN = { ["--with-nth"] = "2.." }

--- Recover the 1-based item index from one returned entry string.
---@param entry string
---@return integer?
local function index_of(entry)
  return tonumber(entry:match("^%s*(%d+)%."))
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
  command = true,
}

--- Render a pick through fzf_exec. The flow's source is started once per fzf
--- run: the opening run, and a fresh run whenever a command reported that the
--- list may have changed (fzf's `reload` binding re-enters the contents
--- function). A reload that changed nothing re-emits the snapshot instead.
---@param spec vantage.PickSpec
---@param opts vantage.PickOpts
function M.pick_fancy(spec, opts)
  local items = {}
  local cancel ---@type fun()?
  -- Start a fresh run on the next contents call: true for the opening run, and
  -- again whenever a command returned true.
  local rerun = true

  --- Map fzf's returned display strings back to their entries, in returned
  --- order.
  ---@param selected string[]?
  ---@return vantage.picker.Entry[]
  local function chosen_of(selected)
    local out = {}
    for _, line in ipairs(selected or {}) do
      local entry = items[index_of(line) or 0]
      if entry then
        out[#out + 1] = entry
      end
    end
    return out
  end

  --- Write each batch's prefixed lines in one pipe write, and nil as end of
  --- input.
  ---@param on_write_nl fun(line: string?)
  ---@param on_write fun(lines: string[])
  local function content(on_write_nl, on_write)
    if cancel then
      cancel()
      cancel = nil
    end
    ---@param lines string[]
    local function write(lines)
      if #lines > 0 then
        on_write(lines)
      end
    end
    if rerun then
      rerun = false
      items = {}
      cancel = spec.items(function(chunk)
        local lines = {}
        for _, entry in ipairs(chunk) do
          items[#items + 1] = entry
          lines[#lines + 1] = PREFIX:format(#items, entry.text)
        end
        write(lines)
      end, function()
        on_write_nl(nil)
      end)
      return
    end
    local lines = {}
    for index, entry in ipairs(items) do
      lines[#lines + 1] = PREFIX:format(index, entry.text)
    end
    write(lines)
    on_write_nl(nil)
  end

  ---@type table<string, any>
  local actions = {
    ["default"] = function(selected)
      local chosen = chosen_of(selected)
      if #chosen > 0 then
        vim.schedule(function()
          opts.on_choices(chosen)
        end)
      end
    end,
  }
  for _, command in ipairs(opts.commands or {}) do
    actions[fzf_key(command[1])] = {
      fn = function(selected)
        local changed = command[2]({
          item = chosen_of(selected)[1],
          items = items,
        })
        if changed then
          rerun = true
        end
      end,
      reload = true,
    }
  end

  local fzf_opts = vim.tbl_extend("force", {}, PREFIX_HIDDEN)
  if spec.many then
    fzf_opts["--multi"] = true
  end

  local pick_opts = {
    prompt = spec.prompt,
    fzf_opts = fzf_opts,
    actions = actions,
    winopts = {
      on_close = function()
        if cancel then
          cancel()
          cancel = nil
        end
      end,
    },
  }
  if spec.preview then
    pick_opts.preview = function(selected)
      local entry = chosen_of(selected)[1]
      if not entry or not spec.preview then
        return ""
      end
      local lines = spec.preview(entry)
      if not lines then
        return ""
      end
      return table.concat(lines, "\n")
    end
  end

  fzf().fzf_exec(content, pick_opts)
end

--- Pick from a plain list (no preview) on this engine: fzf-lua's own
--- ui_select implementation — the same function fzf-lua registers as a global
--- `vim.ui.select` override.
---@param items any[]
---@param opts vantage.NaiveOpts
---@param on_choice fun(item: any?, index?: integer)
function M.pick_naive(items, opts, on_choice)
  require("fzf-lua.providers.ui_select").ui_select(items, {
    prompt = opts.prompt,
    format_item = opts.format_item,
  }, on_choice)
end

return M
