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

---@param callback fun(tool_name: string)
function M.pick_tool(callback)
  local items = Items.tool_items()
  if not items then
    return
  end
  pick({
    items = items,
    format = "text",
    confirm = function(picker, item)
      picker:close()
      if item then
        vim.schedule(function()
          callback(item.name)
        end)
      end
    end,
  })
end

---@param callback fun(group: string)
function M.pick_group(callback)
  local items = Items.group_items()
  if not items then
    Items.prompt_new_group(callback)
    return
  end
  pick({
    items = items,
    format = "text",
    confirm = function(picker, item)
      picker:close()
      if not item then
        return
      end
      vim.schedule(function()
        if item.name == "+ new group" then
          Items.prompt_new_group(callback)
        else
          callback(item.name)
        end
      end)
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
  local items = Items.annotation_items()
  if not items then
    return
  end
  pick({
    items = items,
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
        picker:close()
        if item then
          vim.schedule(function()
            opts.delete(item.annotation)
            M.pick_annotation(opts) -- re-open with the updated list
          end)
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
    },
  })
end

return M
