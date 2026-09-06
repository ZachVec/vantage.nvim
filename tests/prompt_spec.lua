---@module 'luassert'

local Helpers = require("helpers")

describe("vantage.prompt", function()
  local Annotation
  local Config
  local Prompt
  local bufs = {}

  local function context(buf, row, cwd)
    return { buf = buf, row = row, col = 1, cwd = cwd }
  end

  setup(function()
    Helpers.reload_vantage()
    Config = require("vantage.config")
    Annotation = require("vantage.annotation")
    Prompt = require("vantage.prompt")
    Annotation.setup()
  end)

  after_each(function()
    Annotation.clear()
    for _, buf in ipairs(bufs) do
      Helpers.wipe(buf)
    end
    bufs = {}
  end)

  teardown(function()
    Annotation.clear()
    Helpers.reload_vantage()
  end)

  it("renders {file} relative to the agent cwd", function()
    local buf = Helpers.buffer({ "local x = 1" }, "/tmp/proj/src/a.lua")
    bufs[#bufs + 1] = buf
    local rendered = Prompt.render("{file}", context(buf, 1, "/tmp/proj"))
    assert.are.equal("@src/a.lua", rendered)
  end)

  it("renders {line} with the cursor row", function()
    local buf = Helpers.buffer({ "a", "b", "c" }, "/tmp/proj/src/a.lua")
    bufs[#bufs + 1] = buf
    local rendered = Prompt.render("{line}", context(buf, 3, "/tmp/proj"))
    assert.are.equal("@src/a.lua :L3", rendered)
  end)

  it("keeps paths absolute when they escape the agent cwd", function()
    local buf = Helpers.buffer({ "a" }, "/elsewhere/a.lua")
    bufs[#bufs + 1] = buf
    local rendered = Prompt.render("{file}", context(buf, 1, "/tmp/proj"))
    assert.are.equal("@/elsewhere/a.lua", rendered)
  end)

  it("renders multiline templates line by line", function()
    local buf = Helpers.buffer({ "a" }, "/tmp/proj/a.lua")
    bufs[#bufs + 1] = buf
    local rendered = Prompt.render("Review {file}\nAt {line}", context(buf, 1, "/tmp/proj"))
    assert.are.equal("Review @a.lua\nAt @a.lua :L1", rendered)
  end)

  it("leaves unknown placeholders literal", function()
    local buf = Helpers.buffer({ "a" }, "/tmp/proj/a.lua")
    bufs[#bufs + 1] = buf
    local rendered, failed = Prompt.render("before {bogus} after", context(buf, 1, "/tmp/proj"))
    assert.are.equal("before {bogus} after", rendered)
    assert.are.equal(nil, failed)
  end)

  it("fails when {file} has no buffer name", function()
    local buf = Helpers.buffer({ "a" })
    bufs[#bufs + 1] = buf
    local rendered, failed = Prompt.render("{file}", context(buf, 1, "/tmp/proj"))
    assert.are.equal(nil, rendered)
    assert.are.equal("file", failed)
  end)

  it("fails when {annotations} is empty", function()
    local buf = Helpers.buffer({ "a" }, "/tmp/proj/a.lua")
    bufs[#bufs + 1] = buf
    local rendered, failed = Prompt.render("{annotations}", context(buf, 1, "/tmp/proj"))
    assert.are.equal(nil, rendered)
    assert.are.equal("annotations", failed)
  end)

  it("renders {annotations} through the annotation item template", function()
    local buf = Helpers.buffer({ "a", "b", "c" }, "/tmp/proj/src/a.lua")
    bufs[#bufs + 1] = buf
    Annotation.add(buf, 2, 2, "fix this")

    local rendered = Prompt.render("Notes:\n{annotations}", context(buf, 1, "/tmp/proj"))
    assert.are.equal("Notes:\n@src/a.lua :L2 fix this", rendered)
  end)

  it("fails {function} and {class} when textobjects are unavailable", function()
    local buf = Helpers.buffer({ "local x = 1" }, "/tmp/proj/a.lua")
    bufs[#bufs + 1] = buf
    for _, placeholder in ipairs({ "function", "class" }) do
      local rendered, failed = Prompt.render("{" .. placeholder .. "}", context(buf, 1, "/tmp/proj"))
      assert.are.equal(nil, rendered)
      assert.are.equal(placeholder, failed)
    end
  end)
end)
