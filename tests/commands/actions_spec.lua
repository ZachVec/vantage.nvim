---@module 'luassert'

describe("vantage.commands.actions", function()
  local Actions = require("vantage.commands.actions")

  it("resolves every built-in action token to a function", function()
    for _, token in ipairs({ "toggle", "switch", "prompt", "files", "buffers" }) do
      assert.are.equal("function", type(Actions.resolve(token)), token)
    end
  end)

  it("leaves unknown strings, functions, and nil verbatim", function()
    for _, rhs in ipairs({ "<c-q>", "<cmd>MyCommand<CR>", "switchkeys" }) do
      assert.are.equal(rhs, Actions.resolve(rhs))
    end
    local fn = function() end
    assert.are.equal(fn, Actions.resolve(fn))
    assert.are.equal(nil, Actions.resolve(nil))
  end)
end)
