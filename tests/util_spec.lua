---@module 'luassert'

describe("vantage.util", function()
  local Util = require("vantage.util")

  it("exposes the picker prompt glyph and the global cwd", function()
    assert.are.equal(vim.fn.nr2char(0xF105), Util.picker_prompt)
    assert.are.equal(vim.fs.normalize(vim.fn.fnamemodify(vim.fn.getcwd(-1, -1), ":p")), Util.cwd())
  end)

  describe("run_lines", function()
    --- Run a shell command to completion, collecting every line batch.
    ---@param script string
    ---@return string[] lines
    ---@return integer[] batches sizes
    ---@return integer code
    local function collect(script)
      local lines, batches, code = {}, {}, nil
      Util.run_lines({ "sh", "-c", script }, {}, function(batch)
        batches[#batches + 1] = #batch
        vim.list_extend(lines, batch)
      end, function(exit_code)
        code = exit_code
      end)
      vim.wait(5000, function()
        return code ~= nil
      end, 10)
      assert(code ~= nil, "command did not finish")
      return lines, batches, code
    end

    it("hands over complete lines and the exit code", function()
      local lines, batches, code = collect("printf 'a\\nb\\nc\\n'")
      assert.are.same({ "a", "b", "c" }, lines)
      assert.are.same({ 3 }, batches)
      assert.are.equal(0, code)
    end)

    it("carries a partial line across chunks and flushes it at exit", function()
      local lines, _, code = collect("printf 'ab'; /bin/sleep 0.05; printf 'c\\nd'")
      assert.are.same({ "abc", "d" }, lines)
      assert.are.equal(0, code)
    end)

    it("answers the failure code when the command cannot be spawned", function()
      local code
      Util.run_lines({ "vantage-no-such-command" }, {}, function() end, function(exit_code)
        code = exit_code
      end)
      assert.are.equal(-1, code)
    end)

    it("stops the command and still reports its exit", function()
      local finished = false
      local cancel = Util.run_lines({ "sh", "-c", "printf 'a\\n'; sleep 30 & wait" }, {}, function() end, function()
        finished = true
      end)
      cancel()
      vim.wait(5000, function()
        return finished
      end, 20)
      assert.is_true(finished)
    end)
  end)

  describe("interpolate", function()
    local allowed = { name = true, file = true }

    it("renders known placeholders and leaves unknown ones literal", function()
      local rendered, failed = Util.interpolate("hello {name} {file} {bogus}", allowed, function(key)
        if key == "name" then
          return "zach"
        end
        return "a.lua"
      end)
      assert.are.equal("hello zach a.lua {bogus}", rendered)
      assert.are.equal(nil, failed)
    end)

    it("returns the failing placeholder when a resolver yields nil", function()
      local rendered, failed = Util.interpolate("see {name}", allowed, function()
        return nil
      end)
      assert.are.equal(nil, rendered)
      assert.are.equal("name", failed)
    end)
  end)

  describe("shell_quote", function()
    it("quotes empty strings and ordinary arguments", function()
      assert.are.equal("''", Util.shell_quote(""))
      assert.are.equal("'claude'", Util.shell_quote("claude"))
    end)

    it("escapes embedded single quotes for POSIX sh", function()
      assert.are.equal("'a'\\''b'", Util.shell_quote("a'b"))
    end)

    it("joins an argv array with preserved argument boundaries", function()
      assert.are.equal("'sh' '-c' 'echo hello world'", Util.shell_join({ "sh", "-c", "echo hello world" }))
    end)
  end)

  describe("relpath", function()
    it("relativizes paths below cwd", function()
      assert.are.equal("src/a.lua", Util.relpath("/proj", "/proj/src/a.lua"))
    end)

    it("keeps absolute paths when the path escapes cwd", function()
      assert.are.equal("/elsewhere/a.lua", Util.relpath("/proj", "/elsewhere/a.lua"))
    end)
  end)

  describe("tilde", function()
    local home = vim.env.HOME

    after_each(function()
      vim.env.HOME = home
    end)

    it("folds the home directory and paths below it", function()
      vim.env.HOME = "/home/test"
      assert.are.equal("~", Util.tilde("/home/test"))
      assert.are.equal("~/src/a.lua", Util.tilde("/home/test/src/a.lua"))
    end)

    it("leaves paths outside home unchanged", function()
      vim.env.HOME = "/home/test"
      assert.are.equal("/home/testing/a.lua", Util.tilde("/home/testing/a.lua"))
    end)
  end)
end)
