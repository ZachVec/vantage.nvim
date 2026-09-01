--- snacks picker implementation. Drives snacks.picker directly; items carry a
--- `text` field and `format = "text"` renders it. `confirm` receives the
--- original item and must close the picker itself. Preview renders the agent
--- pane via Backend.capture_pane.
local Backend = require("vantage.backend")
local Items = require("vantage.picker.items")

local M = {}

---@class vantage.SnacksPreviewPane The snacks preview-object surface Vantage uses.
---@field reset fun(self: vantage.SnacksPreviewPane)
---@field set_title fun(self: vantage.SnacksPreviewPane, title: string)
---@field set_lines fun(self: vantage.SnacksPreviewPane, lines: string[])

---@class vantage.SnacksPreviewCtx
---@field item { agent?: vantage.Agent, annotation?: vantage.Annotation, text: string }
---@field preview vantage.SnacksPreviewPane

local function pick(source, opts)
  return require("snacks.picker").pick(source, opts)
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
    },
  })
end

--- Selected file paths as absolute paths. Delegates to the snacks `files`
--- source (fd → rg --files → find), so `.gitignore` and the source defaults
--- apply; multi-select uses snacks' built-in selection.
---@param callback fun(paths: string[])
function M.pick_files(callback)
  pick("files", {
    confirm = function(picker)
      local paths = {}
      for _, item in ipairs(picker:selected()) do
        local path = require("snacks.picker.util").path(item)
        if path then
          paths[#paths + 1] = path
        end
      end
      picker:close()
      vim.schedule(function()
        callback(paths)
      end)
    end,
  })
end

--- Selected buffer paths as absolute paths, filtered to real files via
--- `Items.buffer_file_path`. Delegates to the snacks `buffers` source.
---@param callback fun(paths: string[])
function M.pick_buffers(callback)
  pick("buffers", {
    confirm = function(picker)
      local paths = {}
      for _, item in ipairs(picker:selected()) do
        local path = Items.buffer_file_path(item.buf)
        if path then
          paths[#paths + 1] = path
        end
      end
      picker:close()
      vim.schedule(function()
        callback(paths)
      end)
    end,
  })
end

return M
