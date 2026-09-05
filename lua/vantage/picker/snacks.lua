--- snacks picker implementation. Drives snacks.picker directly; items carry a
--- `text` field and `format = "text"` renders it. `confirm` receives the
--- original item and must close the picker itself.
local M = {}

--- Preview-pane window options for every preview-capable pick. Snacks renders
--- its picker preview window with the number column on by default; that gutter
--- reads as a code view, wrong for a captured terminal pane or a rendered
--- annotation template, so Vantage's previews pin it off (relative numbers
--- too, so a future snacks default change cannot reintroduce either).
local NO_PREVIEW_LINENR = { number = false, relativenumber = false }

---@class vantage.SnacksPreviewPane The snacks preview-object surface Vantage uses.
---@field reset fun(self: vantage.SnacksPreviewPane)
---@field set_title fun(self: vantage.SnacksPreviewPane, title: string)
---@field set_lines fun(self: vantage.SnacksPreviewPane, lines: string[])

---@class vantage.SnacksPreviewCtx
---@field item { agent?: vantage.Agent, annotation?: vantage.Annotation, text: string }
---@field preview vantage.SnacksPreviewPane

local function pick(opts)
  return require("snacks.picker").pick(opts)
end

--- Preview the current item's content (pane lines or rendered annotation)
--- through the spec's preview thunk; nil means "nothing to preview".
---@param spec vantage.PickSpec
---@return fun(ctx: vantage.SnacksPreviewCtx)
local function preview(spec)
  return function(ctx)
    local item = ctx.item
    ctx.preview:reset()
    if not item then
      return
    end
    local lines = spec.preview and spec.preview(item)
    if not lines then
      return
    end
    ctx.preview:set_title(item.text)
    ctx.preview:set_lines(lines)
  end
end

--- Re-enter terminal mode when a snacks picker closes back onto the vantage
--- terminal in terminal-normal mode. Snacks pickers deliberately close into
--- Normal (their input is a prompt buffer, not a terminal — see
--- docs/gotchas.md), so a cancel (Esc) or a confirm that lands back on the
--- terminal — including the no-op pinned `(focused)` row — would otherwise
--- strand the client in Normal. Every snacks pick restores: the three
--- preview-capable picks pass `on_close = spec.invoked_from_terminal and
--- restore_terminal_mode`, `pick_plain` calls it from a wrapped `on_choice`
--- (snacks' select shim owns its own `on_close`). Scheduled for the tick after
--- snacks' close has returned focus.
local function restore_terminal_mode()
  vim.schedule(function()
    if vim.api.nvim_get_mode().mode == "nt" then
      vim.cmd("startinsert")
    end
  end)
end

---@param spec vantage.PickSpec
---@param on_choice fun(choice: { kind: "agent"|"tool", agent?: vantage.Agent, tool?: string, focused?: boolean })
---@return boolean empty
function M.pick_agent(spec, on_choice)
  local items = spec.items_provider()
  if #items == 0 then
    return true
  end
  pick({
    items = items,
    format = "text",
    preview = preview(spec),
    on_close = spec.invoked_from_terminal and restore_terminal_mode or nil,
    win = { preview = { wo = NO_PREVIEW_LINENR } },
    confirm = function(picker, item)
      picker:close()
      if item then
        vim.schedule(function()
          on_choice(item)
        end)
      end
    end,
  })
  return false
end

---@param spec vantage.PickSpec
---@param on_choice fun(target: string)
---@return boolean empty
function M.pick_kill(spec, on_choice)
  local items = spec.items_provider()
  if #items == 0 then
    return true
  end
  pick({
    items = items,
    format = "text",
    preview = preview(spec),
    on_close = spec.invoked_from_terminal and restore_terminal_mode or nil,
    win = { preview = { wo = NO_PREVIEW_LINENR } },
    confirm = function(picker, item)
      picker:close()
      if item then
        vim.schedule(function()
          on_choice(item.target)
        end)
      end
    end,
  })
  return false
end

---@param spec vantage.PickSpec
---@param on_choice fun(annotation: vantage.Annotation)
---@return boolean empty
function M.pick_annotation(spec, on_choice)
  local items = spec.items_provider()
  if #items == 0 then
    return true
  end
  pick({
    finder = function()
      return items
    end,
    format = "text",
    preview = preview(spec),
    on_close = spec.invoked_from_terminal and restore_terminal_mode or nil,
    confirm = function(picker, item)
      picker:close()
      if item then
        vim.schedule(function()
          on_choice(item.annotation)
        end)
      end
    end,
    actions = {
      annotation_delete = function(picker, item)
        if item then
          spec.on_delete(item.annotation)
        end
        items = spec.items_provider()
        if #items == 0 then
          picker:close()
        else
          picker:refresh()
        end
      end,
    },
    win = {
      input = {
        keys = {
          ["<C-x>"] = { "annotation_delete", mode = { "n", "i" } },
        },
      },
      list = {
        keys = {
          ["<C-x>"] = "annotation_delete",
        },
      },
      preview = { wo = NO_PREVIEW_LINENR },
    },
  })
  return false
end

--- Pick from a plain list (no preview) on this engine: snacks' own select
--- implementation (its compact select layout, preview hidden, non-terminal) —
--- the same function snacks registers as a global `vim.ui.select` override.
---@param items any[]
---@param opts vantage.PlainSelectOpts
---@param on_choice fun(item: any?, index?: integer)
function M.pick_plain(items, opts, on_choice)
  require("snacks.picker").select(items, {
    prompt = opts.prompt,
    format_item = opts.format_item,
  }, function(item, idx)
    on_choice(item, idx)
    if opts.invoked_from_terminal then
      restore_terminal_mode()
    end
  end)
end

return M
