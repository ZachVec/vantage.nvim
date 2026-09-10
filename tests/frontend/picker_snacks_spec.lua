---@module 'luassert'

local Helpers = require("helpers")

describe("vantage.frontend.picker.snacks", function()
  local Snacks
  local captured
  local items

  setup(function()
    Helpers.reload_vantage()
    items = {
      {
        format = function()
          return "agent row"
        end,
      },
    }
    package.loaded["snacks.picker"] = {
      pick = function(opts)
        captured = opts
      end,
    }
    Snacks = require("vantage.frontend.picker.snacks")
  end)

  teardown(function()
    Helpers.reload_vantage()
  end)

  it("populates item.text for snacks matching and refresh", function()
    local empty = Snacks.pick({
      prompt = "pick",
      items_provider = function()
        return items
      end,
    }, {
      on_choice = function() end,
      commands = {
        {
          "<C-g>",
          function()
            return true
          end,
        },
      },
    })

    assert.is_false(empty)
    assert.is_not_nil(captured)
    assert.are.equal("agent row", captured.finder()[1].text)

    local picker = {
      refresh = function() end,
      close = function() end,
    }
    captured.actions.vantage_command_1(picker, items[1])
    assert.are.equal("agent row", items[1].text)
  end)
end)
