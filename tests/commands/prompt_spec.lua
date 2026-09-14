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
end)
