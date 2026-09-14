---@module 'luassert'

local Helpers = require("helpers")

describe("vantage.frontend.picker.fzf_lua", function()
  local Fzf
  local captured
  local items

  setup(function()
    Helpers.reload_vantage()
    items = {
      {
        text = "first",
        preview = function()
          return { "one" }
        end,
      },
      {
        text = "second",
        preview = function()
          return { "two" }
        end,
      },
    }
    package.loaded["fzf-lua"] = {
      fzf_exec = function(_, opts)
        captured = opts
      end,
    }
    Fzf = require("vantage.frontend.picker.fzf_lua")
  end)

  teardown(function()
    Helpers.reload_vantage()
  end)

  it("maps every returned entry back to its item for a multi pick", function()
    local chosen
    Fzf.pick_multi({
      prompt = "pick",
      items_provider = function()
        return items
      end,
    }, {
      on_choices = function(rows)
        chosen = rows
      end,
    })

    assert.is_true(captured.fzf_opts["--multi"])
    assert.are.equal("2..", captured.fzf_opts["--with-nth"])
    assert.is_nil(captured.fzf_opts["--nth"])
    assert.is_nil(captured.winopts)
    captured.actions.default({ "2. second", "1. first" })
    vim.wait(500, function()
      return chosen ~= nil
    end)

    assert.are.equal(2, #chosen)
    assert.are.equal("second", chosen[1].text)
    assert.are.equal("first", chosen[2].text)
  end)

  it("previews the entry under the cursor", function()
    Fzf.pick_multi({
      prompt = "pick",
      items_provider = function()
        return items
      end,
    }, {
      on_choices = function() end,
    })

    assert.are.equal("two", captured.preview({ "2. second" }))
  end)

  it("hides the index prefix on a single pick and maps the entry back", function()
    local chosen
    Fzf.pick({
      prompt = "pick",
      items_provider = function()
        return items
      end,
    }, {
      on_choice = function(item)
        chosen = item
      end,
    })

    assert.are.equal("2..", captured.fzf_opts["--with-nth"])
    assert.is_nil(captured.fzf_opts["--nth"])
    captured.actions.default({ "2. second" })
    vim.wait(500, function()
      return chosen ~= nil
    end)

    assert.are.equal("second", chosen.text)
  end)

  it("answers empty, with the read's reason, without opening", function()
    captured = nil

    local empty, err = Fzf.pick({
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
