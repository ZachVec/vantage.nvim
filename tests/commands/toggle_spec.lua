---@module 'luassert'

describe("vantage.commands.toggle (keymap tokens)", function()
  local Toggle = require("vantage.commands.toggle")

  it("resolves every built-in action token to a function", function()
    for _, token in ipairs({ "toggle", "switch", "prompt" }) do
      assert.are.equal("function", type(Toggle.resolve(token)), token)
    end
  end)

  it("leaves unknown strings, functions, and nil verbatim", function()
    for _, rhs in ipairs({ "<c-q>", "<cmd>MyCommand<CR>", "switchkeys" }) do
      assert.are.equal(rhs, Toggle.resolve(rhs))
    end
    local fn = function() end
    assert.are.equal(fn, Toggle.resolve(fn))
    assert.are.equal(nil, Toggle.resolve(nil))
  end)
end)
