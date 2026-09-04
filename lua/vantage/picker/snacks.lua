--- snacks picker implementation. Drives snacks.picker directly; items carry a
--- `text` field and `format = "text"` renders it. `confirm` receives the
--- original item and must close the picker itself. Preview renders the agent
--- pane via Backend.capture_pane.
local Backend = require("vantage.backend")
local Items = require("vantage.picker.items")

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

--- Preview the current item's agent pane.
---@param ctx vantage.SnacksPreviewCtx
local function pane_preview(ctx)
  local item = ctx.item
  ctx.preview:reset()
  if not item then
    return
  end
  local agent = item.agent
  if not agent then
    return
  end
  ctx.preview:set_title(item.text)
  ctx.preview:set_lines(Backend.get().capture_pane(agent.target))
end

---@param callback fun(choice: { kind: "agent"|"new", agent?: vantage.Agent })
function M.pick_agent(callback)
  local items = Items.agent_items()
  if not items then
    return
  end
  pick({
    items = items,
    format = "text",
    preview = pane_preview,
    win = { preview = { wo = NO_PREVIEW_LINENR } },
    confirm = function(picker, item)
      picker:close()
      if item then
        vim.schedule(function()
          callback(item)
        end)
      end
    end,
  })
end

---@param callback fun(target: string)
function M.pick_kill(callback)
  local items = Items.kill_items()
  if not items then
    return
  end
  pick({
    items = items,
    format = "text",
    preview = pane_preview,
    win = { preview = { wo = NO_PREVIEW_LINENR } },
    confirm = function(picker, item)
      picker:close()
      if item then
        vim.schedule(function()
          callback(item.target)
        end)
      end
    end,
  })
end

--- Preview an annotation through the configured `item` template (WYSIWYG).
---@param ctx vantage.SnacksPreviewCtx
local function annotation_preview(ctx)
  local item = ctx.item
  ctx.preview:reset()
  if not item then
    return
  end
  local Annotation = require("vantage.annotation")
  ctx.preview:set_title(item.text)
  ctx.preview:set_lines(vim.split(Annotation.render_item(item.annotation, Items.annotation_cwd()), "\n"))
end

---@param opts { select: fun(annotation: vantage.Annotation), delete: fun(annotation: vantage.Annotation) }
function M.pick_annotation(opts)
  if not Items.annotation_items() then
    return
  end
  pick({
    finder = function()
      return Items.annotation_items(true) or {}
    end,
    format = "text",
    preview = annotation_preview,
    confirm = function(picker, item)
      picker:close()
      if item then
        vim.schedule(function()
          opts.select(item.annotation)
        end)
      end
    end,
    actions = {
      annotation_delete = function(picker, item)
        if item then
          opts.delete(item.annotation)
        end
        picker:refresh()
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
end

--- Pick from a plain list (no preview) on this engine: snacks' own select
--- implementation (its compact select layout, preview hidden, non-terminal) —
--- the same function snacks registers as a global `vim.ui.select` override.
---@param items any[]
---@param opts { prompt?: string, format_item?: fun(item: any): string }
---@param on_choice fun(item: any?, index?: integer)
function M.pick_plain(items, opts, on_choice)
  require("snacks.picker").select(items, {
    prompt = opts.prompt,
    format_item = opts.format_item,
  }, on_choice)
end

return M
