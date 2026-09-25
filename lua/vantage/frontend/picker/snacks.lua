--- snacks picker implementation. Drives snacks.picker directly; an entry's
--- `text` is what snacks matches on and renders, and its preview title comes
--- from the same field. `confirm` receives the original entry and must close
--- the picker itself.
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

---@class vantage.SnacksPickerTask The slice of snacks' async task surface Vantage drives.
---@field resume fun(self: vantage.SnacksPickerTask)
---@field suspend fun(self: vantage.SnacksPickerTask)
---@field on fun(self: vantage.SnacksPickerTask, event: string, cb: fun())

---@class vantage.SnacksPicker The slice of the snacks picker surface Vantage drives.
---@field close fun(self: vantage.SnacksPicker)
---@field refresh fun(self: vantage.SnacksPicker)
---@field selected fun(self: vantage.SnacksPicker, opts: { fallback?: boolean }): any[]

---@class vantage.SnacksFinderCtx
---@field async vantage.SnacksPickerTask

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

--- Re-assert the window a pick was invoked from, when the picker's own
--- teardown lost it: Neovim's float-close fallback returns to `prevwin` or the
--- first *tiled* window (never to a sibling float), so from a floating Client
--- the focus lands on the editor behind it. Called from inside a scheduled
--- callback — the tick is what makes the entry land in a settled window (see
--- docs/gotchas.md).
---@param terminal_win integer
local function reassert_window(terminal_win)
  if vim.api.nvim_win_is_valid(terminal_win) and vim.api.nvim_get_current_win() ~= terminal_win then
    pcall(vim.api.nvim_set_current_win, terminal_win)
  end
end

--- Re-enter terminal mode when a snacks picker closes back onto the vantage
--- terminal in terminal-normal mode. Snacks pickers deliberately close into
--- Normal (their input is a prompt buffer, not a terminal — see
--- docs/gotchas.md), so a cancel (Esc) or a confirm that lands back on the
--- terminal would otherwise strand the client in Normal. The plain select
--- path (`pick_naive`) owns its close through this check alone: it runs the
--- choice handler after queueing it, so the pending insert survives the Group
--- name cmdline (see .agents/notes/implemented/bug-fix/
--- 2026-09-05-snacks-new-group-terminal-mode.md).
---@param terminal_win? integer
local function restore_terminal_mode(terminal_win)
  vim.schedule(function()
    if terminal_win then
      reassert_window(terminal_win)
    end
    if vim.api.nvim_get_mode().mode == "nt" then
      vim.cmd("startinsert")
    end
  end)
end

--- Arm the terminal-mode restore for a pick that opened from the vantage
--- terminal: entering that window during the pick's life puts the client back
--- in terminal mode. The pick's close re-asserts the window on the next tick,
--- which is what makes the entry (and so this restore) land in a settled
--- window; a synchronous re-assert enters while the picker is still tearing
--- down, and the insert is dropped (see docs/gotchas.md).
---@param terminal_win integer
---@return fun() disarm
local function arm_terminal_restore(terminal_win)
  local group = vim.api.nvim_create_augroup("vantage_picker_restore", { clear = true })
  vim.api.nvim_create_autocmd("WinEnter", {
    group = group,
    callback = function()
      if vim.api.nvim_get_current_win() == terminal_win then
        vim.cmd("startinsert")
      end
    end,
  })
  return function()
    pcall(vim.api.nvim_del_augroup_by_id, group)
  end
end

---@type vantage.PickerCapabilities
M.capabilities = {
  command = true,
}

--- The engine's own `on_close`: hand the terminal the pick opened from back,
--- window first and mode through the pick's own window-entry restore. The flow
--- takes no part in the close (see `vantage.PickerImpl`).
---@param terminal_win? integer
---@param disarm? fun()
---@return fun()
local function close_handler(terminal_win, disarm)
  return function()
    if terminal_win then
      vim.schedule(function()
        reassert_window(terminal_win)
        if disarm then
          disarm()
        end
      end)
    end
  end
end

--- Render a streaming pick: snacks calls the finder once per run, and each
--- emitted batch becomes finder items. A source that ended within the finder
--- call is a static list; a still-running one is drained from inside snacks'
--- own async task — the queue plus suspend/resume shape snacks' own
--- `source/proc.lua` uses, so `cb` is never called from a libuv callback.
---@param spec vantage.PickSpec
---@param opts vantage.PickOpts
function M.pick_fancy(spec, opts)
  local terminal_win = terminal_window()
  ---@type fun()?
  local disarm
  if terminal_win then
    -- Leave terminal mode before the pick's windows take focus. A source that
    -- streams shows the pick from a callback a tick later, and Neovim drops a
    -- float's insert mode when it is focused out of terminal mode from there
    -- — the pick would sit in Normal with its input window dead (see
    -- docs/gotchas.md).
    disarm = arm_terminal_restore(terminal_win)
    vim.cmd("stopinsert")
  end
  local items, queue = {}, {}
  local finished = false
  local task ---@type vantage.SnacksPickerTask?
  local cancel ---@type fun()?
  -- Which `start` owns `items`/`queue`/`finished`/`cancel`. Snacks aborts the
  -- previous task a tick after the next finder call has already started a
  -- fresh run, so a run's abort handler must check it is still the current one.
  local generation = 0

  --- Start a fresh run. True when the flow's source finished within the call.
  ---@return boolean
  local function start()
    if cancel then
      cancel()
      cancel = nil
    end
    generation = generation + 1
    items, queue, finished = {}, {}, false
    cancel = spec.items(function(chunk)
      vim.list_extend(items, chunk)
      vim.list_extend(queue, chunk)
      if task then
        task:resume()
      end
    end, function()
      finished = true
      if task then
        task:resume()
      end
    end)
    return finished
  end

  ---@param _ table
  ---@param ctx vantage.SnacksFinderCtx
  ---@return any
  local function finder(_, ctx)
    if start() then
      return items
    end
    local own_generation = generation
    return function(cb)
      task = ctx.async
      ctx.async:on("abort", function()
        if own_generation ~= generation then
          return
        end
        if cancel then
          cancel()
          cancel = nil
        end
        finished, queue = true, {}
      end)
      while not finished or #queue > 0 do
        if #queue == 0 then
          ctx.async:suspend()
        else
          local chunk = queue
          queue = {}
          for _, entry in ipairs(chunk) do
            cb(entry)
          end
        end
      end
      task = nil
    end
  end

  local pick_opts = {
    format = function(item)
      return { { item.text, "" } }
    end,
    on_close = close_handler(terminal_win, disarm),
    confirm = function(picker, item)
      picker:close()
      local chosen = spec.many and picker:selected({ fallback = true }) or (item and { item } or {})
      if #chosen > 0 then
        vim.schedule(function()
          opts.on_choices(chosen)
        end)
      end
    end,
    finder = finder,
    win = { preview = { wo = NO_PREVIEW_LINENR } },
  }

  local actions = {}
  for index, command in ipairs(opts.commands or {}) do
    local action = ("vantage_command_%d"):format(index)
    actions[action] = function(picker, item)
      local changed = command[2]({
        item = item,
        items = items,
      })
      if changed then
        -- The refresh re-enters the finder, which cancels this run and starts
        -- a fresh one.
        picker:refresh()
      end
    end
    pick_opts.win.input = pick_opts.win.input or { keys = {} }
    pick_opts.win.list = pick_opts.win.list or { keys = {} }
    pick_opts.win.input.keys[command[1]] = { action, mode = { "i", "n" } }
    pick_opts.win.list.keys[command[1]] = action
  end
  if next(actions) ~= nil then
    pick_opts.actions = actions
  end

  if spec.preview then
    --- Preview the highlighted entry through the pick's own preview function;
    --- nil means "nothing to preview", so the pane stays, empty.
    ---@type fun(entry: vantage.picker.Entry): string[]?
    local preview = spec.preview
    ---@type fun(ctx: vantage.SnacksPreviewCtx)
    pick_opts.preview = function(ctx)
      local item = ctx.item
      ctx.preview:reset()
      if not item then
        return
      end
      local lines = preview(item)
      if not lines then
        return
      end
      ctx.preview:set_title(item.text)
      ctx.preview:set_lines(lines)
    end
  else
    -- No pane at all: snacks hides the layout's preview window.
    pick_opts.layout = { preview = false }
    pick_opts.win.preview = nil
  end

  require("snacks.picker").pick(pick_opts)
end

--- Pick from a plain list (no preview) on this engine: snacks' own select
--- implementation (its compact select layout, preview hidden, non-terminal).
---@param items any[]
---@param opts vantage.NaiveOpts
---@param on_choice fun(item: any?, index?: integer)
function M.pick_naive(items, opts, on_choice)
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
