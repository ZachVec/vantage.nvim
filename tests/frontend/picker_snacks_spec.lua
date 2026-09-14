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
        kind = "agent",
        text = "agent row",
        preview = function()
          return nil
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

  it("reads the entry's text for matching and refresh, and leaves the entry alone", function()
    local before = vim.deepcopy(items[1])
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
    assert.are.same(before, items[1])
  end)

  it("confirms every marked entry for a multi pick", function()
    local chosen
    local empty = Snacks.pick_multi({
      prompt = "pick",
      items_provider = function()
        return items
      end,
    }, {
      on_choices = function(entries)
        chosen = entries
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
    assert.are.equal("agent row", chosen[1].text)
  end)

  it("answers empty, with the read's reason, without opening", function()
    captured = nil

    local empty, err = Snacks.pick({
      prompt = "pick",
      items_provider = function()
        return {}, "no server running"
      end,
    }, {
      on_choice = function() end,
    })

    assert.is_true(empty)
    assert.are.equal("no server running", err)
    assert.is_nil(captured)
  end)
end)
