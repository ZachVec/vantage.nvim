---@module 'luassert'

local Helpers = require("helpers")

describe("vantage.commands.prompt", function()
  local Config
  local Prompt
  local Review
  local bufs = {}

  local function context(buf, row, cwd)
    return { buf = buf, row = row, cwd = cwd }
  end

  setup(function()
    Helpers.reload_vantage()
    Config = require("vantage.config")
    Review = require("vantage.frontend.review")
    Prompt = require("vantage.commands.prompt")
    Review.setup()
  end)

  after_each(function()
    Review.clear()
    for _, buf in ipairs(bufs) do
      Helpers.wipe(buf)
    end
    bufs = {}
  end)

  before_each(function()
    -- A test that rewrites `prompts` must not leak its table into the next one.
    Config.options.prompts = { ["{file}"] = "{file}", ["{line}"] = "{line}", ["{reviews}"] = "{reviews}" }
  end)

  teardown(function()
    Review.clear()
    Helpers.reload_vantage()
  end)

  it("renders {file} and {line} relative to the agent cwd", function()
    local buf = Helpers.buffer({ "a", "b", "c" }, "/tmp/proj/src/a.lua")
    bufs[#bufs + 1] = buf
    assert.are.equal("src/a.lua", Prompt.render("{file}", context(buf, 1, "/tmp/proj")))
    assert.are.equal("src/a.lua :L3", Prompt.render("{line}", context(buf, 3, "/tmp/proj")))
  end)

  it("spells locations through the Tool's reference formatter", function()
    local buf = Helpers.buffer({ "a" }, "/tmp/proj/src/a.lua")
    bufs[#bufs + 1] = buf
    local seen = {}
    Config.options.cli.tools = {
      dialect = {
        cmd = { "codex" },
        format = function(file, loc)
          seen[#seen + 1] = ("%s|%s"):format(file, tostring(loc))
          return "@" .. file .. (loc and (" " .. loc) or "")
        end,
      },
    }

    assert.are.equal("@src/a.lua :L1", Prompt.render("{line}", context(buf, 1, "/tmp/proj"), "dialect"))
    assert.are.equal("@src/a.lua", Prompt.render("{file}", context(buf, 1, "/tmp/proj"), "dialect"))
    assert.are.same({ "src/a.lua|:L1", "src/a.lua|nil" }, seen)
  end)

  it("skips a prompt when the Tool's formatter declines a location", function()
    local buf = Helpers.buffer({ "a" }, "/tmp/proj/src/a.lua")
    bufs[#bufs + 1] = buf
    Config.options.cli.tools = {
      silent = { cmd = { "codex" }, format = function() end },
      blank = {
        cmd = { "codex" },
        format = function()
          return ""
        end,
      },
    }

    for _, tool in ipairs({ "silent", "blank" }) do
      local rendered, failed = Prompt.render("{file}", context(buf, 1, "/tmp/proj"), tool)
      assert.are.equal(nil, rendered)
      assert.are.equal("file", failed)
    end
  end)

  it("keeps paths absolute when they escape the agent cwd", function()
    local buf = Helpers.buffer({ "a" }, "/elsewhere/a.lua")
    bufs[#bufs + 1] = buf
    assert.are.equal("/elsewhere/a.lua", Prompt.render("{file}", context(buf, 1, "/tmp/proj")))
  end)

  it("leaves unknown placeholders literal and fails empty resolvers", function()
    local buf = Helpers.buffer({ "a" }, "/tmp/proj/a.lua")
    bufs[#bufs + 1] = buf
    assert.are.equal("before {bogus} after", Prompt.render("before {bogus} after", context(buf, 1, "/tmp/proj")))

    local unnamed = Helpers.buffer({ "a" })
    bufs[#bufs + 1] = unnamed
    local rendered, failed = Prompt.render("{file}", context(unnamed, 1, "/tmp/proj"))
    assert.are.equal(nil, rendered)
    assert.are.equal("file", failed)
  end)

  it("renders {reviews} through the review item template and fails when empty", function()
    local buf = Helpers.buffer({ "a", "b", "c" }, "/tmp/proj/src/a.lua")
    bufs[#bufs + 1] = buf
    local rendered, failed = Prompt.render("{reviews}", context(buf, 1, "/tmp/proj"))
    assert.are.equal(nil, rendered)
    assert.are.equal("reviews", failed)

    Review.add(buf, 2, 2, "fix this")
    assert.are.equal("Notes:\nsrc/a.lua :L2 fix this", Prompt.render("Notes:\n{reviews}", context(buf, 1, "/tmp/proj")))
  end)

  it("does not re-scan a resolved value for placeholders", function()
    local buf = Helpers.buffer({ "a", "b" }, "/tmp/proj/src/a.lua")
    bufs[#bufs + 1] = buf
    Review.add(buf, 1, 1, "{file} stays literal")

    assert.are.equal("src/a.lua :L1 {file} stays literal", Prompt.render("{reviews}", context(buf, 1, "/tmp/proj")))
  end)

  it("reads the most recent named normal-file window, skipping special buffers", function()
    local dir = vim.fn.tempname()
    local path = vim.fs.joinpath(dir, "file.lua")
    vim.fn.mkdir(dir, "p")
    vim.fn.writefile({ "a", "b", "c" }, path)
    local filebuf = vim.fn.bufadd(path)
    vim.fn.bufload(filebuf)
    bufs[#bufs + 1] = filebuf

    local tab = vim.api.nvim_get_current_tabpage()
    vim.cmd("tabnew")
    vim.api.nvim_win_set_buf(0, filebuf)
    vim.api.nvim_win_set_cursor(0, { 2, 0 })

    -- A scratch float was visited later; a special buffer is not a file source.
    local scratch = Helpers.buffer({ "" })
    bufs[#bufs + 1] = scratch
    local float = vim.api.nvim_open_win(scratch, true, {
      relative = "editor",
      row = 1,
      col = 1,
      width = 10,
      height = 3,
    })

    local ctx = Prompt.context({ cwd = dir })

    assert.are.equal(filebuf, ctx.buf)
    assert.are.equal(2, ctx.row)

    vim.api.nvim_win_close(float, true)
    vim.api.nvim_set_current_tabpage(tab)
  end)

  it("warns at setup about a template naming an unknown placeholder", function()
    local notified = {}
    local original_notify = vim.notify
    vim.notify = function(msg)
      notified[#notified + 1] = msg
    end
    Config.options.prompts = { bad = "{file} {bogus}" }

    Prompt.setup()
    vim.notify = original_notify

    assert.is_true(notified[1]:find("{bogus}", 1, true) ~= nil)
  end)

  it("clears every Review, hidden ones included, after a successful {reviews} send", function()
    local path = "/tmp/proj/src/a.lua"
    local buf = Helpers.buffer({ "a", "b", "c", "d" }, path)
    bufs[#bufs + 1] = buf
    Review.add(buf, 1, 1, "kept")
    Review.add(buf, 3, 3, "doomed")
    vim.api.nvim_buf_call(buf, function()
      vim.cmd("let &l:undolevels = &l:undolevels")
    end)
    -- Deleting line 3 invalidates the second Review, which leaves the send.
    vim.api.nvim_buf_set_lines(buf, 2, 3, false, {})
    assert.are.equal(2, Review.count())
    assert.are.equal(1, #Review.collect())

    local sent
    package.loaded["vantage.backend"] = {
      send = function(agent, text)
        sent = { agent = agent, text = text }
        return true, nil
      end,
    }
    package.loaded["vantage.frontend.terminal"] = {
      attachment = {
        focus = function()
          return { id = "@1", cwd = "/tmp/proj", tool = "codex" }, nil
        end,
      },
    }
    package.loaded["vantage.frontend.picker"] = {
      pick_naive = function(_, _, on_choice)
        on_choice("{reviews}")
      end,
    }
    package.loaded["vantage.commands.prompt"] = nil
    local fresh = require("vantage.commands.prompt")
    fresh.run()

    assert.are.same({ text = "src/a.lua :L1 kept" }, { text = sent.text })
    -- clear_on_send (default true) clears the whole registry, hidden included.
    assert.are.equal(0, Review.count())

    for _, name in ipairs({
      "vantage.backend",
      "vantage.frontend.terminal",
      "vantage.frontend.picker",
      "vantage.commands.prompt",
    }) do
      package.loaded[name] = nil
    end
  end)
end)
