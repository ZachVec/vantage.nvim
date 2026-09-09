--- snacks picker implementation. Drives snacks.picker directly; previewable
--- rows format via `item:format()`. `confirm` receives the original item and
--- must close the picker itself.
local M = {}

---@type string
M.requires = "snacks.picker"

--- Preview-pane window options for every preview-capable pick. Snacks renders
--- its picker preview window with the number column on by default; that gutter
--- reads as a code view, wrong for a captured terminal pane or a rendered
--- review template, so Vantage's previews pin it off (relative numbers too).
local NO_PREVIEW_LINENR = { number = false, relativenumber = false }

---@class vantage.SnacksPreviewPane The snacks preview-object surface Vantage uses.
---@field reset fun(self: vantage.SnacksPreviewPane)
---@field set_title fun(self: vantage.SnacksPreviewPane, title: string)
---@field set_lines fun(self: vantage.SnacksPreviewPane, lines: string[])

---@class vantage.SnacksPreviewCtx
---@field item any
---@field preview vantage.SnacksPreviewPane

local function pick(opts)
  return require("snacks.picker").pick(opts)
end

--- Preview the current item's content (pane lines or rendered review)
--- through the item's `preview()`; nil means "nothing to preview".
---@return fun(ctx: vantage.SnacksPreviewCtx)
local function preview()
  return function(ctx)
    local item = ctx.item
    ctx.preview:reset()
    if not item then
      return
    end
    local lines = item:preview()
    if not lines then
      return
    end
    ctx.preview:set_title(item:format())
    ctx.preview:set_lines(lines)
  end
end

--- The terminal window the pick opens from, when the current window is the
--- vantage terminal (runtime fact; there is no caller-declared flag).
---@return integer? window id
local function terminal_window()
  local win = vim.api.nvim_get_current_win()
  local buf = vim.api.nvim_win_get_buf(win)
  if vim.bo[buf].filetype == "vantage_terminal" then
    return win
  end
  return nil
end

--- Re-enter terminal mode when a snacks picker closes back onto the vantage
--- terminal in terminal-normal mode. Snacks pickers deliberately close into
--- Normal (their input is a prompt buffer, not a terminal — see
--- docs/gotchas.md), so a cancel (Esc) or a confirm that lands back on the
--- terminal would otherwise strand the client in Normal. The picker's float
--- teardown also loses window focus on its own: Neovim's float-close fallback
--- returns to `prevwin` or the first *tiled* window (never to a sibling
--- float), so from a floating Client the focus lands on the editor behind it
--- and the terminal window must be re-asserted explicitly.
---@param terminal_win? integer
local function restore_terminal_mode(terminal_win)
  vim.schedule(function()
    if terminal_win and vim.api.nvim_win_is_valid(terminal_win) and vim.api.nvim_get_current_win() ~= terminal_win then
      pcall(vim.api.nvim_set_current_win, terminal_win)
    end
    if vim.api.nvim_get_mode().mode == "nt" then
      vim.cmd("startinsert")
    end
  end)
end

---@type vantage.PickerCapabilities
M.capabilities = {
  preview = true,
  command = true,
}

--- Render a preview-capable pick and bind the flow's neutral commands to both
--- the snacks input and list surfaces.
---@param spec vantage.PickSpec
---@param opts vantage.PickOpts
---@return boolean empty
function M.pick(spec, opts)
  local terminal_win = terminal_window()

  local list = spec.items_provider()
  if #list == 0 then
    return true
  end

  local function refresh(picker, reread)
    if reread then
      list = spec.items_provider()
    end
    if #list == 0 then
      picker:close()
    else
      picker:refresh()
    end
  end

  local pick_opts = {
    format = function(item)
      return { { item:format(), "" } }
    end,
    preview = preview(),
    on_close = terminal_win and function()
      restore_terminal_mode(terminal_win)
    end or nil,
    confirm = function(picker, item)
      picker:close()
      if item then
        vim.schedule(function()
          opts.on_choice(item)
        end)
      end
    end,
    finder = function()
      return list
    end,
  }

  local actions = {}
  local win = { preview = { wo = NO_PREVIEW_LINENR } }
  for index, command in ipairs(opts.commands or {}) do
    local action = ("vantage_command_%d"):format(index)
    actions[action] = function(picker, item)
      local changed = command[2]({
        item = item,
        items = list,
      })
      if changed then
        refresh(picker, true)
      end
    end
    win.input = win.input or { keys = {} }
    win.list = win.list or { keys = {} }
    win.input.keys[command[1]] = action
    win.list.keys[command[1]] = action
  end
  if next(actions) ~= nil then
    pick_opts.actions = actions
  end

  pick_opts.win = win

  pick(pick_opts)
  return false
end

--- Pick from a plain list (no preview) on this engine: snacks' own select
--- implementation (its compact select layout, preview hidden, non-terminal).
---@param items any[]
---@param opts vantage.PlainSelectOpts
---@param on_choice fun(item: any?, index?: integer)
function M.pick_plain(items, opts, on_choice)
  local terminal_win = terminal_window()
  require("snacks.picker").select(items, {
    prompt = opts.prompt,
    format_item = opts.format_item,
  }, function(item, idx)
    if terminal_win then
      restore_terminal_mode(terminal_win)
    end
    on_choice(item, idx)
  end)
end

return M
