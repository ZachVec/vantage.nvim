---@module 'luassert'

describe("vantage.util", function()
  local Util = require("vantage.util")

  it("exposes the picker prompt glyph", function()
    assert.are.equal(vim.fn.nr2char(0xF105), Util.picker_prompt)
  end)

  describe("relpath", function()
    it("relativizes paths below cwd", function()
      assert.are.equal("src/a.lua", Util.relpath("/proj", "/proj/src/a.lua"))
    end)

    it("keeps an absolute path when the path escapes cwd", function()
      local outside = Util.relpath("/proj", "/elsewhere/a.lua")
      assert.are.equal("/elsewhere/a.lua", outside)
    end)

    it("keeps the absolute path when relativization is empty", function()
      local cwd = "/proj"
      assert.are.equal(cwd, Util.relpath(cwd, cwd))
    end)
  end)

  describe("tilde", function()
    local home = vim.env.HOME

    after_each(function()
      vim.env.HOME = home
    end)

    it("folds the home directory itself", function()
      vim.env.HOME = "/home/test"
      assert.are.equal("~", Util.tilde("/home/test"))
    end)

    it("folds paths below home", function()
      vim.env.HOME = "/home/test"
      assert.are.equal("~/src/a.lua", Util.tilde("/home/test/src/a.lua"))
    end)

    it("leaves paths outside home unchanged", function()
      vim.env.HOME = "/home/test"
      assert.are.equal("/home/testing/a.lua", Util.tilde("/home/testing/a.lua"))
    end)

    it("leaves paths unchanged when HOME is unset", function()
      vim.env.HOME = vim.NIL
      assert.are.equal("/home/test/a.lua", Util.tilde("/home/test/a.lua"))
    end)
  end)
end)
