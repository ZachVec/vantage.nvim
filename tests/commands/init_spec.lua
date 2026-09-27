---@module 'luassert'

local Helpers = require("helpers")

describe("vantage.commands", function()
  local Commands

  setup(function()
    Helpers.reload_vantage()
    Commands = require("vantage.commands")
  end)

  teardown(function()
    Helpers.reload_vantage()
  end)

  it("resolves every built-in action token to a function", function()
    for _, token in ipairs({ "hide", "switch", "prompt", "files", "buffers" }) do
      assert.are.equal("function", type(Commands.resolve(token)), token)
    end
  end)

  it("leaves unknown strings, functions, and nil verbatim", function()
    for _, rhs in ipairs({ "<c-q>", "<cmd>MyCommand<CR>", "switchkeys" }) do
      assert.are.equal(rhs, Commands.resolve(rhs))
    end
    local fn = function() end
    assert.are.equal(fn, Commands.resolve(fn))
    assert.are.equal(nil, Commands.resolve(nil))
  end)
end)
