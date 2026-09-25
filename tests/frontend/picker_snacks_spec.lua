---@module 'luassert'

local Helpers = require("helpers")

describe("vantage.frontend.picker.snacks", function()
  local Snacks
  local captured
  local selected
  local items

  --- A source that emits its list at once.
  ---@param list vantage.picker.Entry[]
  ---@return vantage.picker.Source
  local function source(list)
    return function(emit, done)
      emit(list)
      done()
    end
  end

  --- A picker surface just wide enough for the adapter.
  ---@param marked? vantage.picker.Entry[]
  ---@return vantage.SnacksPicker
  local function picker(marked)
    return {
      close = function() end,
      refresh = function() end,
      selected = function()
        return vim.deepcopy(marked or items)
      end,
    }
  end

  --- A snacks-like async task driving one drain run: `suspend` parks the drain
  --- coroutine, `resume` re-enters it, and `fire_abort` calls the handler the
  --- adapter registered. Snacks delivers a run's abort a tick after the finder
  --- call that superseded it, so the test fires it by hand at that moment.
  ---@return table
  local function async_task()
    local self = { suspended = false }
    local co
    function self.suspend()
      self.suspended = true
      coroutine.yield()
    end
    function self.resume()
      if co and self.suspended then
        self.suspended = false
        coroutine.resume(co)
      end
    end
    function self.on(_, event, cb)
      if event == "abort" then
        self.abort_handler = cb
      end
    end
    function self.fire_abort()
      if self.abort_handler then
        self.abort_handler()
      end
    end
    function self.drain(drain)
      co = coroutine.create(drain)
      coroutine.resume(co)
      return self
    end
    return self
  end

  setup(function()
    Helpers.reload_vantage()
    items = {
      { kind = "agent", text = "agent row" },
    }
    package.loaded["snacks.picker"] = {
      pick = function(opts)
        captured = opts
      end,
      select = function(list, opts, on_choice)
        selected = { items = list, opts = opts, on_choice = on_choice }
      end,
    }
    Snacks = require("vantage.frontend.picker.snacks")
  end)

  teardown(function()
    Helpers.reload_vantage()
  end)

  it("renders a source that ended in the finder call as a static list, and leaves entries alone", function()
    local before = vim.deepcopy(items[1])
    Snacks.pick_fancy({ prompt = "pick", many = false, items = source(items) }, { on_choices = function() end })

    local list = captured.finder({}, {})
    assert.are.equal("agent row", list[1].text)
    assert.are.same(before, items[1])
  end)

  it("confirms every marked entry when the flow acts on several", function()
    local chosen
    Snacks.pick_fancy({ prompt = "pick", many = true, items = source(items) }, {
      on_choices = function(entries)
        chosen = entries
      end,
    })

    captured.confirm(picker())
    vim.wait(500, function()
      return chosen ~= nil
    end)

    assert.are.equal(1, #chosen)
    assert.are.equal("agent row", chosen[1].text)
  end)

  it("confirms the entry under the cursor when the flow acts on one", function()
    local chosen
    Snacks.pick_fancy({ prompt = "pick", many = false, items = source(items) }, {
      on_choices = function(entries)
        chosen = entries
      end,
    })

    captured.confirm(picker(), items[1])
    vim.wait(500, function()
      return chosen ~= nil
    end)

    assert.are.equal("agent row", chosen[1].text)
  end)

  it("previews the highlighted entry when the flow asked for a preview", function()
    local rendered
    Snacks.pick_fancy({
      prompt = "pick",
      many = false,
      preview = function()
        return { "line" }
      end,
      items = source(items),
    }, { on_choices = function() end })

    assert.is_not_nil(captured.preview)
    assert.is_not_nil(captured.win.preview.wo)
    captured.preview({
      item = items[1],
      preview = {
        reset = function() end,
        set_title = function() end,
        set_lines = function(_, lines)
          rendered = lines
        end,
      },
    })
    assert.are.same({ "line" }, rendered)
  end)

  it("hides the preview pane without a preview function", function()
    Snacks.pick_fancy({ prompt = "pick", many = false, items = source(items) }, { on_choices = function() end })

    assert.is_nil(captured.preview)
    assert.is_false(captured.layout.preview)
    assert.is_nil(captured.win.preview)
  end)

  it("refreshes through a command that changed the list, and does nothing otherwise", function()
    local changed = true
    local refreshed = false
    Snacks.pick_fancy({ prompt = "pick", many = false, items = source(items) }, {
      on_choices = function() end,
      commands = { {
        "<C-g>",
        function()
          return changed
        end,
      } },
    })

    assert.are.equal("vantage_command_1", captured.win.input.keys["<C-g>"][1])
    assert.are.same({ "i", "n" }, captured.win.input.keys["<C-g>"].mode)

    local surface = picker()
    surface.refresh = function()
      refreshed = true
    end
    captured.actions.vantage_command_1(surface, items[1])
    assert.is_true(refreshed)

    refreshed = false
    changed = false
    captured.actions.vantage_command_1(surface, items[1])
    assert.is_false(refreshed)
  end)

  it("streams a live source inside snacks' async task", function()
    local emit, done
    Snacks.pick_fancy({
      prompt = "pick",
      many = false,
      items = function(emit_, done_)
        emit, done = emit_, done_
      end,
    }, { on_choices = function() end })

    -- The slice of snacks' task surface the adapter drives: suspend yields out
    -- of the task, resume re-enters it.
    local co
    local task = {
      suspend = function()
        coroutine.yield()
      end,
      resume = function()
        coroutine.resume(co)
      end,
      on = function() end,
    }
    local received = {}
    co = coroutine.create(function()
      captured.finder({}, { async = task })(function(item)
        received[#received + 1] = item.text
      end)
    end)
    coroutine.resume(co)

    emit({ { kind = "agent", text = "first" } })
    emit({ { kind = "agent", text = "second" } })
    done()

    assert.are.same({ "first", "second" }, received)
  end)

  it("stops a live source when the task aborts", function()
    local abort
    local cancelled = false
    Snacks.pick_fancy({
      prompt = "pick",
      many = false,
      items = function(emit)
        emit({ { kind = "agent", text = "first" } })
        return function()
          cancelled = true
        end
      end,
    }, { on_choices = function() end })

    local co
    local task = {
      suspend = function()
        coroutine.yield()
      end,
      resume = function()
        coroutine.resume(co)
      end,
      on = function(_, event, cb)
        if event == "abort" then
          abort = cb
        end
      end,
    }
    co = coroutine.create(function()
      captured.finder({}, { async = task })(function() end)
    end)
    coroutine.resume(co)

    abort()
    assert.is_true(cancelled)
  end)

  it("ignores a superseded run's abort and keeps the re-run's source streaming", function()
    local sources = {}
    Snacks.pick_fancy({
      prompt = "pick",
      many = false,
      items = function(emit, done)
        local source = { emit = emit, done = done, cancelled = false }
        function source.cancel()
          source.cancelled = true
        end
        sources[#sources + 1] = source
        return source.cancel
      end,
    }, { on_choices = function() end })

    local received = {}
    local function cb(item)
      received[#received + 1] = item.text
    end

    -- Run 1's live source parks the drain with an empty queue.
    local first = async_task()
    first.drain(function()
      captured.finder({}, { async = first })(cb)
    end)
    assert.is_false(sources[1].cancelled)

    -- A finder re-run (snacks' toggle keys) starts run 2, abandoning run 1.
    local second = async_task()
    second.drain(function()
      captured.finder({}, { async = second })(cb)
    end)
    assert.is_true(sources[1].cancelled)

    -- Snacks delivers run 1's abort only after run 2 has started.
    first.fire_abort()
    assert.is_false(sources[2].cancelled)

    -- Run 2's stream is intact: its batches still arrive and it ends on done.
    sources[2].emit({ { kind = "agent", text = "fresh" } })
    sources[2].done()
    assert.are.same({ "fresh" }, received)
  end)

  it("picks a plain list through snacks' own select", function()
    local on_choice = function() end
    Snacks.pick_naive({ "a" }, { prompt = "pick", format_item = tostring }, on_choice)

    assert.are.same({ "a" }, selected.items)
    assert.are.equal("pick", selected.opts.prompt)
    assert.are.equal(tostring, selected.opts.format_item)
    assert.is_not_nil(selected.on_choice)
  end)

  --- Run `body` with `vim.cmd` recorded, restoring it afterwards. Returns the
  --- commands issued, in order — the mode transitions themselves are invisible
  --- under `--headless` (see docs/gotchas.md), so specs pin the ordering.
  ---@param body fun()
  ---@return string[]
  local function commands_during(body)
    local commands = {}
    local cmd = vim.cmd
    vim.cmd = function(command)
      commands[#commands + 1] = command
      return cmd(command)
    end
    local ok, err = pcall(body)
    vim.cmd = cmd
    assert(ok, err)
    return commands
  end

  it("closes a terminal-origin pick onto the terminal window, with no pick-lifetime restore", function()
    local term_buf = Helpers.buffer({ "" })
    vim.bo[term_buf].filetype = "vantage_terminal"
    vim.api.nvim_set_current_buf(term_buf)
    local term_win = vim.api.nvim_get_current_win()

    local chosen
    Snacks.pick_fancy({ prompt = "pick", many = false, items = source(items) }, {
      on_choices = function(entries)
        chosen = entries
      end,
    })

    -- The Terminal owns the mode now: the pick arms no restore of its own.
    assert.are.equal(0, vim.fn.exists("#vantage_picker_restore#WinEnter"))

    local closed = false
    local surface = picker()
    surface.close = function()
      closed = true
    end
    captured.confirm(surface, items[1])
    vim.wait(500, function()
      return chosen ~= nil
    end)

    assert.is_true(closed)
    assert.are.equal(term_win, surface.main) -- the close hands the terminal back
    assert.are.equal("agent row", chosen[1].text)
    Helpers.wipe(term_buf)
  end)

  it("leaves a pick that did not open from the terminal alone", function()
    local plain = Helpers.buffer({ "" })
    vim.api.nvim_set_current_buf(plain)

    local chosen
    Snacks.pick_fancy({ prompt = "pick", many = false, items = source(items) }, {
      on_choices = function(entries)
        chosen = entries
      end,
    })
    local surface = picker()
    surface.close = function() end
    captured.confirm(surface, items[1])
    vim.wait(500, function()
      return chosen ~= nil
    end)

    assert.is_nil(surface.main)
    assert.are.equal("agent row", chosen[1].text)
    Helpers.wipe(plain)
  end)

  it("hands terminal mode back before a plain pick's choice handler runs", function()
    local term_buf = Helpers.buffer({ "" })
    vim.bo[term_buf].filetype = "vantage_terminal"
    vim.api.nvim_set_current_buf(term_buf)

    local events = {}
    Snacks.pick_naive({ "a" }, { prompt = "pick" }, function()
      events[#events + 1] = "choice"
    end)

    local commands = commands_during(function()
      selected.on_choice("a", 1)
    end)

    -- Issued first, the insert stays pending across a cmdline the handler opens.
    assert.are.same({ "startinsert" }, commands)
    assert.are.same({ "choice" }, events)
    Helpers.wipe(term_buf)
  end)

  it("runs a plain pick's choice handler untouched when it did not open from the terminal", function()
    local plain = Helpers.buffer({ "" })
    vim.api.nvim_set_current_buf(plain)

    local events = {}
    Snacks.pick_naive({ "a" }, { prompt = "pick" }, function()
      events[#events + 1] = "choice"
    end)

    local commands = commands_during(function()
      selected.on_choice("a", 1)
    end)

    assert.are.same({}, commands)
    assert.are.same({ "choice" }, events)
    Helpers.wipe(plain)
  end)
end)
