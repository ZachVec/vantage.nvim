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

  --- Close any open editing float so each test starts window-clean.
  local function close_floats()
    for _, win in ipairs(vim.api.nvim_list_wins()) do
      if vim.api.nvim_win_is_valid(win) and vim.api.nvim_win_get_config(win).relative ~= "" then
        pcall(vim.api.nvim_win_close, win, true)
      end
    end
  end

  --- Commit the current float through its `<Esc>` mapping.
  local function press_escape()
    vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("<Esc>", true, false, true), "x", false)
  end

  --- The number-column tint an extmark currently carries, or nil.
  ---@param buf integer
  ---@param id integer
  ---@return string?
  local function tint_of(buf, id)
    local pos =
      vim.api.nvim_buf_get_extmark_by_id(buf, vim.api.nvim_create_namespace("vantage_review"), id, { details = true })
    return pos[3] and pos[3].number_hl_group
  end

  setup(function()
    Helpers.reload_vantage()
    Config = require("vantage.config")
    Review = require("vantage.frontend.review")
    Review.setup()
  end)

  after_each(function()
    close_floats()
    vim.fn.confirm = nil
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

  it("sets a review's note text and deletes idempotently", function()
    local buf = named_buffer("/tmp/rev/one.lua", { "a", "b", "c" })
    local review = Review.add(buf, 1, 1, "old")

    Review.set_note(buf, review.id, "new")
    assert.are.equal("new", Review.get(buf, review.id).note)

    Review.delete(buf, review.id)
    assert.are.equal(nil, Review.get(buf, review.id))
    Review.delete(buf, review.id)
  end)

  it("edit jumps to the review and opens a float that commits its text", function()
    local buf = named_buffer("/tmp/rev/one.lua", { "a", "b", "c" })
    local review = Review.add(buf, 2, 3, "old")

    Review.edit(buf, review.id)

    local win = vim.api.nvim_get_current_win()
    local float = vim.api.nvim_win_get_buf(win)
    assert.are.equal("editor", vim.api.nvim_win_get_config(win).relative)
    assert.are.same({ "old" }, vim.api.nvim_buf_get_lines(float, 0, -1, false))
    assert.are.same({ 2, 0 }, vim.api.nvim_win_get_cursor(vim.fn.bufwinid(buf)))
    assert.are.equal("VantageReviewActive", tint_of(buf, review.id))

    vim.api.nvim_buf_set_lines(float, 0, -1, false, { "new", "text", "" })
    press_escape()

    assert.is_false(vim.api.nvim_win_is_valid(win))
    assert.are.equal("new\ntext", Review.get(buf, review.id).note)
    assert.are.equal("VantageReview", tint_of(buf, review.id))
  end)

  it("edit treats an empty commit as delete after confirmation", function()
    local buf = named_buffer("/tmp/rev/one.lua", { "a", "b" })
    local review = Review.add(buf, 1, 2, "old")

    vim.fn.confirm = function()
      return 2
    end
    Review.edit(buf, review.id)
    vim.api.nvim_buf_set_lines(vim.api.nvim_get_current_buf(), 0, -1, false, {})
    press_escape()
    assert.are.equal("old", Review.get(buf, review.id).note)

    vim.fn.confirm = function()
      return 1
    end
    Review.edit(buf, review.id)
    vim.api.nvim_buf_set_lines(vim.api.nvim_get_current_buf(), 0, -1, false, {})
    press_escape()
    assert.are.equal(nil, Review.get(buf, review.id))
  end)

  it("create asks for a new review over the range and discards an empty commit", function()
    local buf = named_buffer("/tmp/rev/one.lua", { "a", "b", "c" })

    Review.create(buf, 1, 2)
    local float = vim.api.nvim_get_current_buf()
    assert.are.equal("editor", vim.api.nvim_win_get_config(vim.api.nvim_get_current_win()).relative)
    assert.are.same({ "" }, vim.api.nvim_buf_get_lines(float, 0, -1, false))
    vim.api.nvim_buf_set_lines(float, 0, -1, false, { "hello" })
    press_escape()

    local review = Review.collect()[1]
    assert.are.equal(1, review.start_row)
    assert.are.equal(2, review.end_row)
    assert.are.equal("hello", review.note)

    Review.create(buf, 3, 3)
    press_escape()
    assert.are.equal(1, #Review.collect())
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

    assert.are.equal("one.lua :L2", Review.location(single, "/tmp/proj"))
    assert.are.equal("one.lua :L3-4", Review.location(range, "/tmp/proj"))
  end)

  it("spells locations through the Tool's reference formatter", function()
    local buf = named_buffer("/tmp/proj/one.lua", { "a", "b" })
    Review.add(buf, 2, 2, "note")
    Config.options.cli.tools = {
      dialect = {
        cmd = { "codex" },
        format = function(file, loc)
          return "@" .. file .. (loc and (" " .. loc) or "")
        end,
      },
      silent = { cmd = { "codex" }, format = function() end },
    }

    assert.are.equal("@one.lua :L2", Review.location(Review.collect()[1], "/tmp/proj", "dialect"))
    assert.are.equal("@one.lua :L2 note", Review.render("/tmp/proj", "dialect"))
    -- A declined reference leaves the preview blank but skips the whole render.
    assert.are.equal("", Review.render_item(Review.collect()[1], "/tmp/proj", "silent"))
    assert.are.equal(nil, Review.render("/tmp/proj", "silent"))
  end)

  it("renders the configured item template with every field", function()
    Config.options.reviews.item = "{lines} {note} | {file} {start}-{end} | {code}"
    local buf = named_buffer("/tmp/proj/src/one.lua", { "first", "", "third", "" })
    local review = Review.add(buf, 1, 4, "todo")

    assert.are.equal(
      "src/one.lua :L1-4 todo | src/one.lua 1-4 | first\n\nthird",
      Review.render_item(review, "/tmp/proj")
    )
  end)

  it("render concatenates items in collect order and returns nil when empty", function()
    local one = named_buffer("/tmp/proj/a.lua", { "a", "b" })
    local two = named_buffer("/tmp/proj/b.lua", { "x", "y" })
    Review.add(one, 2, 2, "A")
    Review.add(two, 1, 1, "B")

    assert.are.equal("proj/a.lua :L2 A\nproj/b.lua :L1 B", Review.render("/tmp"))
    Review.clear()
    assert.are.equal(nil, Review.render("/tmp"))
  end)
end)
