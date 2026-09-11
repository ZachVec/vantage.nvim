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

  it("runs on_close after a single choice", function()
    local item = {
      format = function()
        return "row"
      end,
    }
    vim.ui.select = function(_, _, on_choice)
      on_choice(item)
    end

    local chosen
    local closed = false
    local empty = Native.pick({
      prompt = "pick",
      items_provider = function()
        return { item }
      end,
    }, {
      on_choice = function(row)
        chosen = row
      end,
      on_close = function()
        closed = true
      end,
    })

    assert.is_false(empty)
    assert.are.equal(item, chosen)
    assert.is_true(closed)
  end)
end)
