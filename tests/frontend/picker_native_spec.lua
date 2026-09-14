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

  it("renders an entry's text and returns the choice", function()
    local item = {
      kind = "agent",
      text = "an entry",
      preview = function()
        return nil
      end,
    }
    local formatted
    vim.ui.select = function(items, opts, on_choice)
      formatted = opts.format_item(items[1])
      on_choice(items[1])
    end

    local chosen
    local empty, err = Native.pick({
      prompt = "pick",
      items_provider = function()
        return { item }
      end,
    }, {
      on_choice = function(entry)
        chosen = entry
      end,
    })

    assert.is_false(empty)
    assert.is_nil(err)
    assert.are.equal("an entry", formatted)
    assert.are.equal(item, chosen)
  end)

  it("answers empty, with the read's reason, without opening", function()
    local opened = false
    vim.ui.select = function()
      opened = true
    end

    local empty, err = Native.pick({
      prompt = "pick",
      items_provider = function()
        return {}, "no server running"
      end,
    }, {
      on_choice = function() end,
    })

    assert.is_true(empty)
    assert.are.equal("no server running", err)
    assert.is_false(opened)
  end)
end)
