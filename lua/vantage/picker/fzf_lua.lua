--- fzf-lua picker implementation. Drives fzf-lua's native `fzf_exec`; because
--- fzf-lua returns display strings rather than the original objects, each entry
--- carries a numeric prefix that round-trips the item index — the same scheme
--- fzf-lua's own ui_select shim uses. Preview renders the agent pane.
local Backend = require("vantage.backend")
local Items = require("vantage.picker.items")

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

---@param callback fun(choice: { kind: "agent"|"new", agent?: vantage.Agent })
function M.pick_agent(callback)
  local items = Items.agent_items()
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
            callback(item)
          end)
        end
      end,
    },
    preview = pane_preview(items),
  })
end

---@param callback fun(tool_name: string)
function M.pick_tool(callback)
  local items = Items.tool_items()
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
            callback(item.name)
          end)
        end
      end,
    },
  })
end

---@param callback fun(group: string)
function M.pick_group(callback)
  local items = Items.group_items()
  if not items then
    Items.prompt_new_group(callback)
    return
  end
  fzf().fzf_exec(entries(items), {
    prompt = Items.prompt,
    actions = {
      ["default"] = function(selected)
        local item = items[index_of(selected)]
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
    },
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

  -- Re-read the items and provide them to fzf; re-invoked on `reload`.
  local function content(cb)
    state.items = Items.annotation_items(true) or {}
    cb(entries(state.items))
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

return M
