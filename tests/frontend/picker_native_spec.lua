---@module 'luassert'

local Helpers = require("helpers")

describe("vantage.frontend.picker.native", function()
  local Native
  local original_select

  setup(function()
    Helpers.reload_vantage()
    Native = require("vantage.frontend.picker.native")
    original_select = vim.ui.select
  end)

  teardown(function()
    vim.ui.select = original_select
    Helpers.reload_vantage()
  end)

  it("drains a fancy pick and answers with the one choice vim.ui.select makes", function()
    local item = { kind = "agent", text = "an entry" }
    local formatted
    vim.ui.select = function(items, opts, on_choice)
      formatted = opts.format_item(items[1])
      on_choice(items[1])
    end

    local chosen
    Native.pick_fancy({
      prompt = "pick",
      many = true,
      items = function(emit, done)
        emit({ item })
        done()
      end,
    }, {
      on_choices = function(entries)
        chosen = entries
      end,
    })

    assert.are.equal("an entry", formatted)
    assert.are.same({ item }, chosen)
  end)

  it("waits for a stream that ends after the call", function()
    vim.ui.select = function(items, _, on_choice)
      on_choice(items[1])
    end

    local chosen
    Native.pick_fancy({
      prompt = "pick",
      many = false,
      items = function(emit, done)
        vim.defer_fn(function()
          emit({ { kind = "agent", text = "late" } })
          done()
        end, 5)
      end,
    }, {
      on_choices = function(entries)
        chosen = entries
      end,
    })

    assert.are.equal("late", chosen[1].text)
  end)

  it("opens an empty pick when the stream produced nothing", function()
    local opened = false
    vim.ui.select = function()
      opened = true
    end

    Native.pick_fancy({
      prompt = "pick",
      many = false,
      items = function(_, done)
        done()
      end,
    }, {
      on_choices = function() end,
    })

    assert.is_true(opened)
  end)

  it("picks from a plain list through the live vim.ui.select", function()
    local received
    vim.ui.select = function(items, opts, on_choice)
      received = { items = items, opts = opts, on_choice = on_choice }
    end

    local on_choice = function() end
    Native.pick_naive({ "a" }, { prompt = "pick", format_item = tostring }, on_choice)

    assert.are.same({ "a" }, received.items)
    assert.are.equal("pick", received.opts.prompt)
    assert.are.equal(tostring, received.opts.format_item)
    assert.are.equal(on_choice, received.on_choice)
  end)
end)
