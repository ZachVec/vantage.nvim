--- snacks picker implementation. Drives snacks.picker directly; previewable
--- rows are domain objects and snacks formats them via `item:format()`.
--- `confirm` receives the original item and must close the picker itself.
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
---@field item any
---@field preview vantage.SnacksPreviewPane

local function pick(opts)
  return require("snacks.picker").pick(opts)
end

---@class vantage.SnacksRenderOpts Internal renderer options for the snacks picker.
---@field dynamic boolean
---@field on_choice fun(item: any)
---@field delete_action? string
---@field group_action? string

--- Preview the current item's content (pane lines or rendered annotation)
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

--- Re-enter terminal mode when a snacks picker closes back onto the vantage
--- terminal in terminal-normal mode. Snacks pickers deliberately close into
--- Normal (their input is a prompt buffer, not a terminal — see
--- docs/gotchas.md), so a cancel (Esc) or a confirm that lands back on the
--- terminal — including the no-op pinned `(focused)` row — would otherwise
--- strand the client in Normal. The picker's float teardown also loses window
--- focus on its own: Neovim's float-close fallback returns to `prevwin` or the
--- first *tiled* window (never to a sibling float), so from a floating Client
--- the focus lands on the editor behind it and the terminal window must be
--- re-asserted explicitly. Every snacks pick restores: the three
--- preview-capable picks pass `on_close = spec.from_terminal and
--- restore_terminal_mode`, `pick_plain` calls it from a wrapped `on_choice`
--- (snacks' select shim owns its own `on_close`) *before* the choice handler
--- runs. The new-Group name prompt (a cmdline `input()`) opens from inside
--- the choice handler and the scheduler keeps running across it, so a check
--- queued after the handler would see the cmdline's `c` mode, skip, and
--- strand the terminal in Normal once the prompt closes; queued first, the
--- `startinsert` stays pending across the cmdline and lands when it closes.
--- Scheduled for the tick after snacks' close has returned focus.
---@param terminal_win? integer the window the pick was invoked from (the
---   Client window); nil skips the focus re-assert, keeping the call mode-only
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

--- The shared snacks renderer for the three preview-capable picks. Public
--- methods keep their distinct result types; this helper owns only the
--- engine-specific presentation and live-list/refresh machinery.
---@param spec vantage.PickSpec
---@param opts vantage.SnacksRenderOpts
---@return boolean empty
local function render(spec, opts)
  local group_on = opts.group_action ~= nil and spec.group ~= nil
  local terminal_win = spec.from_terminal and vim.api.nvim_get_current_win() or nil

  local function read()
    local all = spec.items_provider()
    if group_on then
      return spec.group(all)
    end
    return all
  end

  local list = read()
  if #list == 0 then
    return true
  end

  local function refresh(picker)
    list = read()
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
    on_close = spec.from_terminal and function()
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
  }

  if opts.dynamic then
    pick_opts.finder = function()
      return list
    end
  else
    pick_opts.items = list
  end

  local actions = {}
  if opts.delete_action then
    actions[opts.delete_action] = function(picker, item)
      if item and item:delete() then
        refresh(picker)
      end
    end
  end
  if opts.group_action then
    actions[opts.group_action] = function(picker)
      group_on = not group_on
      refresh(picker)
    end
  end
  if next(actions) ~= nil then
    pick_opts.actions = actions
  end

  local win = { preview = { wo = NO_PREVIEW_LINENR } }
  if opts.delete_action or opts.group_action then
    win.input = { keys = {} }
    win.list = { keys = {} }
  end
  if opts.delete_action then
    win.input.keys["<C-x>"] = { opts.delete_action, mode = { "n", "i" } }
    win.list.keys["<C-x>"] = opts.delete_action
  end
  if opts.group_action then
    win.input.keys["<C-g>"] = { opts.group_action, mode = { "n", "i" } }
    win.list.keys["<C-g>"] = opts.group_action
  end
  pick_opts.win = win

  pick(pick_opts)
  return false
end

---@param spec vantage.PickSpec
---@param on_choice fun(item: any)
---@return boolean empty
function M.pick_agent(spec, on_choice)
  return render(spec, {
    dynamic = true,
    on_choice = on_choice,
    delete_action = "agent_kill",
    group_action = "agent_group_toggle",
  })
end

---@param spec vantage.PickSpec
---@param on_choice fun(item: any)
---@return boolean empty
function M.pick_kill(spec, on_choice)
  return render(spec, {
    dynamic = false,
    on_choice = on_choice,
  })
end

---@param spec vantage.PickSpec
---@param on_choice fun(item: any)
---@return boolean empty
function M.pick_annotation(spec, on_choice)
  return render(spec, {
    dynamic = true,
    on_choice = on_choice,
    delete_action = "annotation_delete",
  })
end

--- Pick from a plain list (no preview) on this engine: snacks' own select
--- implementation (its compact select layout, preview hidden, non-terminal) —
--- the same function snacks registers as a global `vim.ui.select` override.
---@param items any[]
---@param opts vantage.PlainSelectOpts
---@param on_choice fun(item: any?, index?: integer)
function M.pick_plain(items, opts, on_choice)
  local terminal_win = opts.from_terminal and vim.api.nvim_get_current_win() or nil
  require("snacks.picker").select(items, {
    prompt = opts.prompt,
    format_item = opts.format_item,
  }, function(item, idx)
    if opts.from_terminal then
      restore_terminal_mode(terminal_win)
    end
    on_choice(item, idx)
  end)
end

return M
