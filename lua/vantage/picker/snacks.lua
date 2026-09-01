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
---@field item { agent?: vantage.Agent, text: string }
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

return M
