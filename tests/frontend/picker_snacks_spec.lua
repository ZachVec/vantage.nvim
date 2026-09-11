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
    assert.are.equal("vantage_command_1", captured.win.input.keys["<C-g>"][1])
    assert.are.same({ "i", "n" }, captured.win.input.keys["<C-g>"].mode)

    local picker = {
      refresh = function() end,
      close = function() end,
    }
    captured.actions.vantage_command_1(picker, items[1])
    assert.are.equal("agent row", items[1].text)
  end)

  it("confirms every marked row for a multi pick", function()
    local chosen
    local empty = Snacks.pick_multi({
      prompt = "pick",
      items_provider = function()
        return items
      end,
    }, {
      on_choices = function(rows)
        chosen = rows
      end,
    })

    assert.is_false(empty)
    assert.is_not_nil(captured)
    assert.are.equal("agent row", captured.finder()[1].text)

    local picker = {
      selected = function()
        return vim.deepcopy(items)
      end,
      close = function() end,
    }
    captured.confirm(picker)
    vim.wait(500, function()
      return chosen ~= nil
    end)

    assert.are.equal(1, #chosen)
    assert.are.equal("agent row", chosen[1]:format())
  end)
end)
