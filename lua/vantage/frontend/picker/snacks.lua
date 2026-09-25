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

---@type vantage.PickerCapabilities
M.capabilities = {
  command = true,
}

--- Render a streaming pick: snacks calls the finder once per run, and each
--- emitted batch becomes finder items. A source that ended within the finder
--- call is a static list; a still-running one is drained from inside snacks'
--- own async task — the queue plus suspend/resume shape snacks' own
--- `source/proc.lua` uses, so `cb` is never called from a libuv callback.
---@param spec vantage.PickSpec
---@param opts vantage.PickOpts
function M.pick_fancy(spec, opts)
  local terminal_win = terminal_window()
  local committed = false
  if terminal_win then
    -- Leave terminal mode before the pick's windows take focus. A source that
    -- streams shows the pick from a callback a tick later, and Neovim drops a
    -- float's insert mode when it is focused out of terminal mode from there
    -- — the pick would sit in Normal with its input window dead (see
    -- docs/gotchas.md).
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
    confirm = function(picker, item)
      -- Take the choice, then close on the next tick. Leaving insert mode now
      -- (the picker's input is a prompt buffer) puts the mode change in an
      -- earlier event than the focus switch, so the Terminal's own window-entry
      -- rule enters a settled window — a synchronous close runs while the
      -- picker is still tearing down and the insert is dropped, stranding the
      -- client in Normal (see docs/gotchas.md). Naming the invoked-from window
      -- as the pick's main makes the picker's close focus it; `Picker:close()`
      -- consumes `main` in the same pass, so it must be set first. The flow's
      -- callback runs a tick after the close, when its UI changes are safe
      -- (see `vantage.PickerImpl`).
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
