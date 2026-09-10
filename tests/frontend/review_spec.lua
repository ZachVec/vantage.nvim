---@module 'luassert'

local Helpers = require("helpers")

describe("vantage.frontend.review", function()
  local Review
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
    Review = require("vantage.frontend.review")
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
    Config.options.reviews.item = "{lines} {note}"
  end)

  teardown(function()
    Review.clear()
    Helpers.reload_vantage()
  end)

  it("adds and reads a review over an extmark range", function()
    local buf = named_buffer("/tmp/rev/one.lua", { "a", "b", "c", "d" })
    local review = Review.add(buf, 2, 3, "note")

    assert.are.equal(buf, review.buf)
    assert.are.equal(2, review.start_row)
    assert.are.equal(3, review.end_row)
    assert.are.equal("note", review.note)
    assert.are.same(review, Review.get(buf, review.id))

    local position =
      vim.api.nvim_buf_get_extmark_by_id(buf, vim.api.nvim_create_namespace("vantage_review"), review.id, {})
    assert.are.same({ 1, 0 }, { position[1], position[2] })
  end)

  it("edits and deletes reviews idempotently", function()
    local buf = named_buffer("/tmp/rev/one.lua", { "a", "b", "c" })
    local review = Review.add(buf, 1, 1, "old")

    Review.edit(buf, review.id, "new")
    assert.are.equal("new", Review.get(buf, review.id).note)

    Review.delete(buf, review.id)
    assert.are.equal(nil, Review.get(buf, review.id))
    Review.delete(buf, review.id)
  end)

  it("collects live reviews sorted by buffer name and start row", function()
    local one = named_buffer("/tmp/rev/one.lua", { "a", "b", "c" })
    local two = named_buffer("/tmp/rev/two.lua", { "x", "y", "z" })
    local one_second = Review.add(one, 2, 2, "one-2")
    local two_first = Review.add(two, 1, 1, "two-1")
    local one_first = Review.add(one, 1, 1, "one-1")

    assert.are.same(
      { one_first.id, one_second.id, two_first.id },
      vim.tbl_map(function(r)
        return r.id
      end, Review.collect())
    )
  end)

  it("clear removes every review", function()
    local one = named_buffer("/tmp/rev/one.lua", { "a", "b" })
    local two = named_buffer("/tmp/rev/two.lua", { "x", "y" })
    Review.add(one, 1, 1, "one")
    Review.add(two, 2, 2, "two")

    Review.clear()
    assert.are.equal(0, #Review.collect())
  end)

  it("renders {lines} with a single or ranged reference", function()
    local buf = named_buffer("/tmp/proj/one.lua", { "a", "b", "c", "d" })
    local single = Review.add(buf, 2, 2, "")
    local range = Review.add(buf, 3, 4, "")

    assert.are.equal("@one.lua :L2", Review.location(single, "/tmp/proj"))
    assert.are.equal("@one.lua :L3-4", Review.location(range, "/tmp/proj"))
  end)

  it("renders the configured item template with every field", function()
    Config.options.reviews.item = "{lines} {note} | {file} {start}-{end} | {code}"
    local buf = named_buffer("/tmp/proj/src/one.lua", { "first", "", "third", "" })
    local review = Review.add(buf, 1, 4, "todo")

    assert.are.equal(
      "@src/one.lua :L1-4 todo | src/one.lua 1-4 | first\n\nthird",
      Review.render_item(review, "/tmp/proj")
    )
  end)

  it("render concatenates items in collect order and returns nil when empty", function()
    local one = named_buffer("/tmp/proj/a.lua", { "a", "b" })
    local two = named_buffer("/tmp/proj/b.lua", { "x", "y" })
    Review.add(one, 2, 2, "A")
    Review.add(two, 1, 1, "B")

    assert.are.equal("@proj/a.lua :L2 A\n@proj/b.lua :L1 B", Review.render("/tmp"))
    Review.clear()
    assert.are.equal(nil, Review.render("/tmp"))
  end)
end)
