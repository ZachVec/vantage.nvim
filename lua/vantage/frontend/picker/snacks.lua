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
---@field main? integer the window snacks' close returns focus to

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

---@type vantage.PickerCapabilities
M.capabilities = {
  command = true,
}

--- The pick's item stream, driven through snacks' finder. snacks calls the
--- finder once per run — the opening pick, and again whenever a command
--- reports the list may have changed — and each emitted batch becomes finder
--- items. A source that ended within the finder call is shown as a static
--- list; a still-running one is drained from inside snacks' own async task,
--- the queue plus suspend/resume shape snacks' own `source/proc.lua` uses, so
--- `cb` is never called from a libuv callback.
---
--- One stream per pick; each `start` is one run of it and resets the fields a
--- run owns. Snacks aborts the previous run's task a tick after the next
--- finder call has already started a fresh run, so a run is stamped with its
--- `generation` and a stale abort stops nothing.
---@class vantage.SnacksStream
---@field source vantage.picker.Source the flow's stream, started once per run
---@field generation integer the run that owns the fields below
---@field items vantage.picker.Entry[] entries the current run has produced
---@field queue vantage.picker.Entry[] entries its drain has yet to hand to snacks
---@field finished boolean the current run's source has ended
---@field cancel fun()? stops the current run's source, when it is still going
---@field task vantage.SnacksPickerTask? the task draining the current run
local Stream = {}

Stream.__index = Stream

---@param source vantage.picker.Source
---@return vantage.SnacksStream
function Stream.new(source)
  return setmetatable({
    source = source,
    generation = 0,
    items = {},
    queue = {},
    finished = false,
  }, Stream)
end

--- Wake the current run's drain loop when it is parked with nothing queued.
function Stream:resume()
  if self.task then
    self.task:resume()
  end
end

--- Take a batch from the flow: keep it for the pick's commands and queue it
--- for the drain loop.
---@param chunk vantage.picker.Entry[]
function Stream:emit(chunk)
  vim.list_extend(self.items, chunk)
  vim.list_extend(self.queue, chunk)
  self:resume()
end

--- The flow's source ended, success or failure.
function Stream:finish()
  self.finished = true
  self:resume()
end

--- Start a fresh run, cancelling the source the previous run left going.
--- True when this run's source already ended within the call, so the finder
--- answers with the static list instead of a drain.
---@return boolean
function Stream:start()
  if self.cancel then
    self.cancel()
    self.cancel = nil
  end
  self.generation = self.generation + 1
  self.items, self.queue, self.finished = {}, {}, false
  self.cancel = self.source(function(chunk)
    self:emit(chunk)
  end, function()
    self:finish()
  end)
  return self.finished
end

--- snacks' finder: start this run and answer with its entries when it already
--- ended, or with a function draining it inside snacks' async task when it has
--- not.
---@param ctx vantage.SnacksFinderCtx
---@return any
function Stream:finder(ctx)
  if self:start() then
    return self.items
  end
  local generation = self.generation
  return function(cb)
    self:drain(ctx.async, cb, generation)
  end
end

--- Hand the run's batches to snacks from inside its own task, parking the loop
--- while the queue is empty. An abort names the run it belongs to: a run the
--- next finder call has already superseded stops nothing.
---@param task vantage.SnacksPickerTask
---@param cb fun(entry: vantage.picker.Entry)
---@param generation integer
function Stream:drain(task, cb, generation)
  self.task = task
  task:on("abort", function()
    if generation ~= self.generation then
      return
    end
    if self.cancel then
      self.cancel()
      self.cancel = nil
    end
    self.finished, self.queue = true, {}
  end)
  while not self.finished or #self.queue > 0 do
    if #self.queue == 0 then
      task:suspend()
    else
      local chunk = self.queue
      self.queue = {}
      for _, entry in ipairs(chunk) do
        cb(entry)
      end
    end
  end
  -- A newer run may already own the task; leave its handle alone.
  if self.task == task then
    self.task = nil
  end
end

--- The pick's confirm handler: take the choice, then close on the next tick.
--- Leaving insert mode now (the picker's input is a prompt buffer) puts the
--- mode change in an earlier event than the focus switch, so the Terminal's
--- own window-entry rule enters a settled window — a synchronous close runs
--- while the picker is still tearing down and the insert is dropped, stranding
--- the client in Normal (see docs/gotchas.md). Naming the invoked-from window
--- as the pick's main makes the picker's close focus it; `Picker:close()`
--- consumes `main` in the same pass, so it must be set first. The flow's
--- callback runs a tick after the close, when its UI changes are safe (see
--- `vantage.PickerImpl`). The deferred close leaves room for a second confirm,
--- which `committed` answers with nothing.
---@param spec vantage.PickSpec
---@param opts vantage.PickOpts
---@param terminal_win integer?
---@return fun(picker: vantage.SnacksPicker, item: vantage.picker.Entry?)
local function confirm_handler(spec, opts, terminal_win)
  local committed = false
  return function(picker, item)
    vim.cmd("stopinsert")
    local chosen = spec.many and picker:selected({ fallback = true }) or (item and { item } or {})
    if #chosen == 0 then
      picker:close()
      return
    end
    if committed then
      return
    end
    committed = true
    vim.schedule(function()
      if terminal_win then
        picker.main = terminal_win
      end
      picker:close()
      vim.schedule(function()
        opts.on_choices(chosen)
      end)
    end)
  end
end

--- The flow's commands as snacks actions, plus the keymaps that reach them
--- from the input and list panes. A command's `rhs` receives the highlighted
--- entry and the current run's entries; a true result refreshes the picker,
--- whose finder re-run replaces the run.
---@param commands vantage.PickerCommand[]
---@param stream vantage.SnacksStream
---@return table<string, fun(picker: vantage.SnacksPicker, item: vantage.picker.Entry?)>? actions
---@return table? input the input pane's `keys`
---@return table? list the list pane's `keys`
local function command_bindings(commands, stream)
  if #commands == 0 then
    return nil, nil, nil
  end
  local actions, input, list = {}, {}, {}
  for index, command in ipairs(commands) do
    local name = ("vantage_command_%d"):format(index)
    actions[name] = function(picker, item)
      local changed = command[2]({
        item = item,
        items = stream.items,
      })
      if changed then
        picker:refresh()
      end
    end
    input[command[1]] = { name, mode = { "i", "n" } }
    list[command[1]] = name
  end
  return actions, input, list
end

--- The pick's preview function. nil from the flow's own preview means
--- "nothing to preview", so the pane stays, empty.
---@param preview fun(entry: vantage.picker.Entry): string[]?
---@return fun(ctx: vantage.SnacksPreviewCtx)
local function preview_pane(preview)
  return function(ctx)
    ctx.preview:reset()
    local item = ctx.item
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
end

--- Render a streaming pick through snacks' own picker.
---@param spec vantage.PickSpec
---@param opts vantage.PickOpts
function M.pick_fancy(spec, opts)
  local terminal_win = terminal_window()
  if terminal_win then
    -- Leave terminal mode before the pick's windows take focus. A source that
    -- streams shows the pick from a callback a tick later, and Neovim drops a
    -- float's insert mode when it is focused out of terminal mode from there
    -- — the pick would sit in Normal with its input window dead (see
    -- docs/gotchas.md).
    vim.cmd("stopinsert")
  end

  local stream = Stream.new(spec.items)
  local pick_opts = {
    ---@param item vantage.picker.Entry
    format = function(item)
      return { { item.text, "" } }
    end,
    confirm = confirm_handler(spec, opts, terminal_win),
    finder = function(_, ctx)
      return stream:finder(ctx)
    end,
    win = {},
  }

  local actions, input_keys, list_keys = command_bindings(opts.commands or {}, stream)
  if actions then
    pick_opts.actions = actions
    pick_opts.win.input = { keys = input_keys }
    pick_opts.win.list = { keys = list_keys }
  end

  if spec.preview then
    pick_opts.preview = preview_pane(spec.preview)
    pick_opts.win.preview = { wo = NO_PREVIEW_LINENR }
  else
    -- No pane at all: snacks' layout carries a preview window whether or not
    -- a `preview` function is given, so hiding it takes the layout flag.
    pick_opts.layout = { preview = false }
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
    -- Hand terminal mode back before the choice handler runs: this callback is
    -- snacks' own post-close tick, so the insert lands on the settled window —
    -- and issued first, it stays pending across a cmdline the handler opens
    -- (the new-Group name prompt; see .agents/notes/implemented/bug-fix/
    -- 2026-09-05-snacks-new-group-terminal-mode.md).
    if terminal_win then
      vim.cmd("startinsert")
    end
    on_choice(item, idx)
  end)
end

return M
