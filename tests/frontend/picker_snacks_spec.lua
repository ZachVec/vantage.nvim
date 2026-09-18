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

  it("picks a plain list through snacks' own select", function()
    local on_choice = function() end
    Snacks.pick_naive({ "a" }, { prompt = "pick", format_item = tostring }, on_choice)

    assert.are.same({ "a" }, selected.items)
    assert.are.equal("pick", selected.opts.prompt)
    assert.are.equal(tostring, selected.opts.format_item)
    assert.is_not_nil(selected.on_choice)
  end)
end)
