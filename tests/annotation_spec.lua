---@module 'luassert'

local Helpers = require("helpers")

describe("vantage.annotation", function()
  local Annotation
  local Config
  local bufs = {}

  local function named_buffer(name, lines)
    local buf = Helpers.buffer(lines, name)
    bufs[#bufs + 1] = buf
    return buf
  end

  setup(function()
    Helpers.reload_vantage()
    Config = require("vantage.config")
    Annotation = require("vantage.annotation")
    Annotation.setup()
  end)

  after_each(function()
    Annotation.clear()
    for _, buf in ipairs(bufs) do
      Helpers.wipe(buf)
    end
    bufs = {}
  end)

  before_each(function()
    Config.options.annotations.item = "{lines} {note}"
  end)

  teardown(function()
    Annotation.clear()
    Helpers.reload_vantage()
  end)

  it("adds and reads an annotation over an extmark range", function()
    local buf = named_buffer("/tmp/ann/one.lua", { "a", "b", "c", "d" })
    local annotation = Annotation.add(buf, 2, 3, "note")

    assert.are.equal(buf, annotation.buf)
    assert.are.equal(2, annotation.start_row)
    assert.are.equal(3, annotation.end_row)
    assert.are.equal("note", annotation.note)
    assert.are.same(annotation, Annotation.get(buf, annotation.id))

    local position =
      vim.api.nvim_buf_get_extmark_by_id(buf, vim.api.nvim_create_namespace("vantage_annotation"), annotation.id, {})
    assert.are.same({ 1, 0 }, { position[1], position[2] })
  end)

  it("edits and deletes annotations", function()
    local buf = named_buffer("/tmp/ann/one.lua", { "a", "b", "c" })
    local annotation = Annotation.add(buf, 1, 1, "old")

    Annotation.edit(buf, annotation.id, "new")
    assert.are.equal("new", Annotation.get(buf, annotation.id).note)

    Annotation.delete(buf, annotation.id)
    assert.are.equal(nil, Annotation.get(buf, annotation.id))
    Annotation.delete(buf, annotation.id) -- idempotent
  end)

  it("collects live annotations sorted by buffer name and start row", function()
    local one = named_buffer("/tmp/ann/one.lua", { "a", "b", "c" })
    local two = named_buffer("/tmp/ann/two.lua", { "x", "y", "z" })
    local one_second = Annotation.add(one, 2, 2, "one-2")
    local two_first = Annotation.add(two, 1, 1, "two-1")
    local one_first = Annotation.add(one, 1, 1, "one-1")

    local collected = Annotation.collect()
    assert.are.same(
      {
        one_first.id,
        one_second.id,
        two_first.id,
      },
      vim.tbl_map(function(a)
        return a.id
      end, collected)
    )
  end)

  it("clear removes every annotation", function()
    local one = named_buffer("/tmp/ann/one.lua", { "a", "b" })
    local two = named_buffer("/tmp/ann/two.lua", { "x", "y" })
    Annotation.add(one, 1, 1, "one")
    Annotation.add(two, 2, 2, "two")

    Annotation.clear()
    assert.are.equal(0, #Annotation.collect())
  end)

  it("toggles the active highlight without losing the range", function()
    local buf = named_buffer("/tmp/ann/one.lua", { "a", "b", "c" })
    local annotation = Annotation.add(buf, 1, 2, "note")

    Annotation.set_active(buf, annotation.id, true)
    local position =
      vim.api.nvim_buf_get_extmark_by_id(buf, vim.api.nvim_create_namespace("vantage_annotation"), annotation.id, {})
    assert.are.same({ 0, 0 }, { position[1], position[2] })
  end)

  describe("rendering", function()
    it("renders {lines} with a single or ranged reference", function()
      local buf = named_buffer("/tmp/proj/one.lua", { "a", "b", "c", "d" })
      local single = Annotation.add(buf, 2, 2, "")
      local range = Annotation.add(buf, 3, 4, "")

      assert.are.equal("@one.lua :L2", Annotation.location(single, "/tmp/proj"))
      assert.are.equal("@one.lua :L3-4", Annotation.location(range, "/tmp/proj"))
    end)

    it("renders the configured item template with every field", function()
      Config.options.annotations.item = "{lines} {note} | {file} {start}-{end} | {code}"
      local buf = named_buffer("/tmp/proj/src/one.lua", { "first", "", "third", "" })
      local annotation = Annotation.add(buf, 1, 4, "todo")

      local rendered = Annotation.render_item(annotation, "/tmp/proj")
      assert.are.equal("@src/one.lua :L1-4 todo | src/one.lua 1-4 | first\n\nthird", rendered)
    end)

    it("leaves unknown item fields literal", function()
      local buf = named_buffer("/tmp/proj/one.lua", { "a" })
      local annotation = Annotation.add(buf, 1, 1, "note")
      Config.options.annotations.item = "{note} {bogus}"
      assert.are.equal("note {bogus}", Annotation.render_item(annotation, "/tmp/proj"))
    end)

    it("render concatenates items in collect order and returns nil when empty", function()
      local one = named_buffer("/tmp/proj/a.lua", { "a", "b" })
      local two = named_buffer("/tmp/proj/b.lua", { "x", "y" })
      Annotation.add(one, 2, 2, "A")
      Annotation.add(two, 1, 1, "B")

      assert.are.equal("@proj/a.lua :L2 A\n@proj/b.lua :L1 B", Annotation.render("/tmp"))
      Annotation.clear()
      assert.are.equal(nil, Annotation.render("/tmp"))
    end)
  end)
end)
