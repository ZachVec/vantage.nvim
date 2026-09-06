---@module 'luassert'

describe("vantage.keys", function()
  local Keys = require("vantage.keys")

  it("resolves every built-in action token to a function", function()
    for _, token in ipairs({ "toggle", "switch", "kill", "prompt" }) do
      assert.are.equal("function", type(Keys.resolve(token)), token)
    end
  end)

  it("leaves unknown strings verbatim", function()
    for _, rhs in ipairs({ "<c-q>", "<cmd>MyCommand<CR>", "switchkeys" }) do
      assert.are.equal(rhs, Keys.resolve(rhs))
    end
  end)

  it("leaves Lua functions verbatim", function()
    local fn = function() end
    assert.are.equal(fn, Keys.resolve(fn))
  end)

  it("leaves nil verbatim", function()
    assert.are.equal(nil, Keys.resolve(nil))
  end)
end)
