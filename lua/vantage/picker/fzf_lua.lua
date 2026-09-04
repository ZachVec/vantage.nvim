--- fzf-lua picker implementation. Drives fzf-lua's native `fzf_exec`; because
--- fzf-lua returns display strings rather than the original objects, each entry
--- carries a numeric prefix that round-trips the item index — the same scheme
--- fzf-lua's own ui_select shim uses. Preview renders the agent pane.
local Backend = require("vantage.backend")
local Items = require("vantage.picker.items")
local Util = require("vantage.util")

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

--- Preview the selected item's agent pane as plain text.
---@param items table[]
---@return fun(selected: string[]): string
local function pane_preview(items)
  return function(selected)
    local item = items[index_of(selected)]
    if not item or not item.agent then
      return ""
    end
    return table.concat(Backend.get().capture_pane(item.agent.target), "\n")
  end
end

---@param callback fun(choice: { kind: "agent"|"tool", agent?: vantage.Agent, tool?: string, focused?: boolean })
function M.pick_agent(callback)
  local items = Items.agent_items()
  if #items == 0 then
    Util.warn("no agents and no tools configured (cli.tools)")
    return
  end
  fzf().fzf_exec(entries(items), {
    prompt = Items.prompt,
    actions = {
      ["default"] = function(selected)
        local item = items[index_of(selected)]
        if item then
          vim.schedule(function()
            callback(item)
          end)
        end
      end,
    },
    preview = pane_preview(items),
  })
end

---@param callback fun(target: string)
function M.pick_kill(callback)
  local items = Items.kill_items()
  if not items then
    return
  end
  fzf().fzf_exec(entries(items), {
    prompt = Items.prompt,
    actions = {
      ["default"] = function(selected)
        local item = items[index_of(selected)]
        if item then
          vim.schedule(function()
            callback(item.target)
          end)
        end
      end,
    },
    preview = pane_preview(items),
  })
end

---@param opts { select: fun(annotation: vantage.Annotation), delete: fun(annotation: vantage.Annotation) }
function M.pick_annotation(opts)
  local state = { items = Items.annotation_items() }
  if not state.items then
    return
  end
  local Annotation = require("vantage.annotation")

  -- Re-read the items and provide them to fzf; re-invoked on `reload`. `cb`
  -- writes one entry at a time (and `cb(nil)` signals the end of input).
  local function content(cb)
    state.items = Items.annotation_items(true) or {}
    for _, entry in ipairs(entries(state.items)) do
      cb(entry)
    end
    cb(nil)
  end

  local function item_of(selected)
    return state.items[index_of(selected)]
  end

  fzf().fzf_exec(content, {
    prompt = Items.prompt,
    actions = {
      ["default"] = function(selected)
        local item = item_of(selected)
        if item then
          vim.schedule(function()
            opts.select(item.annotation)
          end)
        end
      end,
      ["ctrl-x"] = {
        fn = function(selected)
          local item = item_of(selected)
          if item then
            opts.delete(item.annotation)
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
      return Annotation.render_item(item.annotation, Items.annotation_cwd())
    end,
  })
end

--- Pick from a plain list (no preview) on this engine: fzf-lua's own
--- ui_select implementation — the same function fzf-lua registers as a global
--- `vim.ui.select` override — so the wizard stays on the fzf renderer family.
---@param items any[]
---@param opts { prompt?: string, format_item?: fun(item: any): string }
---@param on_choice fun(item: any?, index?: integer)
function M.pick_plain(items, opts, on_choice)
  require("fzf-lua.providers.ui_select").ui_select(items, {
    prompt = opts.prompt,
    format_item = opts.format_item,
  }, on_choice)
end

return M
