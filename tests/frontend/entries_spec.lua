---@module 'luassert'

local Helpers = require("helpers")

describe("vantage.frontend.entries", function()
  local Config
  local Entries
  local Review
  local backend
  local tmp
  local bufs = {}

  local function named_buffer(name, lines)
    local buf = Helpers.buffer(lines, name)
    bufs[#bufs + 1] = buf
    return buf
  end

  --- A file on disk under the test's temp directory.
  ---@param relpath string
  ---@param lines string[]
  ---@return string absolute path
  local function write(relpath, lines)
    local path = vim.fs.joinpath(tmp, relpath)
    vim.fn.mkdir(vim.fn.fnamemodify(path, ":h"), "p")
    vim.fn.writefile(lines, path)
    return path
  end

  ---@param overrides? table
  ---@return vantage.Agent
  local function agent(overrides)
    return vim.tbl_extend("force", {
      id = "@1",
      seq = 1,
      group = "work",
      cmd = "codex",
      cwd = tmp,
      tool = "codex",
    }, overrides or {})
  end

  setup(function()
    Helpers.reload_vantage()
    Config = require("vantage.config")
    backend = { captured = {} }
    function backend.capture(target)
      backend.captured[#backend.captured + 1] = target.id
      if backend.capture_err then
        return nil, backend.capture_err
      end
      return { "pane line" }, nil
    end
    package.loaded["vantage.backend"] = backend
    Review = require("vantage.frontend.review")
    Review.setup()
    Entries = require("vantage.frontend.entries")
  end)

  teardown(function()
    Review.clear()
    Helpers.reload_vantage()
  end)

  before_each(function()
    backend.captured = {}
    backend.capture_err = nil
    Config.options.reviews.item = "{lines} {note}"
    Config.options.cli.tools = {}
    tmp = vim.fn.tempname()
    vim.fn.mkdir(tmp, "p")
  end)

  after_each(function()
    for _, buf in ipairs(bufs) do
      Helpers.wipe(buf)
    end
    bufs = {}
    vim.fn.delete(tmp, "rf")
  end)

  it("hands the Picker plain data, carrying no preview of its own", function()
    local path = vim.fs.joinpath(tmp, "a.lua")
    local review_buf = named_buffer(path, { "a", "b" })
    local entries = {
      Entries.agent(agent()), -- 1
      Entries.agent(agent(), true), -- 2
      Entries.tool("codex"), -- 3
      Entries.file(path, tmp), -- 4
      Entries.buffer(review_buf, path, tmp, false), -- 5
      Entries.review(Review.add(review_buf, 1, 2, "note"), tmp, nil), -- 6
    }

    for _, entry in ipairs(entries) do
      assert.are.equal("nil", type(getmetatable(entry)))
      assert.are.equal("string", type(entry.text))
      assert.are.equal("string", type(entry.kind))
      assert.is_nil(rawget(entry, "preview"))
    end
  end)

  it("previews through the one kind-keyed preview function", function()
    assert.is_nil(Entries.preview(Entries.tool("codex")))
  end)

  it("spells an Agent entry with its Tool, Group, and cwd, pinning the Focus", function()
    local plain = Entries.agent(agent())
    local pinned = Entries.agent(agent({ id = "@2" }), true)

    assert.are.equal("agent", plain.kind)
    assert.is_true(plain.text:find("codex · work · " .. tmp, 1, true) ~= nil)
    assert.are.equal("focused", pinned.kind)
    assert.are.equal(plain.text .. " (focused)", pinned.text)
    assert.are.equal("@2", pinned.agent.id)
  end)

  it("previews an Agent's pane, and the Driver's reason when the capture fails", function()
    local entry = Entries.agent(agent())

    assert.are.same({ "pane line" }, Entries.preview(entry))
    assert.are.same({ "@1" }, backend.captured)

    backend.capture_err = "no server running"
    assert.are.same({ "no server running" }, Entries.preview(entry))
  end)

  it("previews a file entry from disk", function()
    local path = write("sub/b.lua", { "b", "b2" })
    local entry = Entries.file(path, tmp)

    assert.are.equal("file", entry.kind)
    assert.are.equal("sub/b.lua", entry.text)
    assert.are.same({ "b", "b2" }, Entries.preview(entry))
  end)

  it("previews a buffer entry from the buffer, marking a modified one in its text", function()
    local path = write("a.lua", { "on disk" })
    local buf = named_buffer(path, { "in buffer" })
    local entry = Entries.buffer(buf, path, tmp, true)

    assert.are.equal("buffer", entry.kind)
    assert.are.equal("a.lua [+]", entry.text)
    assert.are.same({ "in buffer" }, Entries.preview(entry))
  end)

  it("falls back to the file when a buffer entry's buffer is gone", function()
    local path = write("a.lua", { "on disk" })
    local buf = named_buffer(path, { "in buffer" })
    local entry = Entries.buffer(buf, path, tmp, false)
    Helpers.wipe(buf)

    assert.are.same({ "on disk" }, Entries.preview(entry))
  end)

  it("spells a Review row through the one reference owner", function()
    local path = vim.fs.joinpath(tmp, "a.lua")
    local buf = named_buffer(path, { "a", "b" })
    local review = Review.add(buf, 1, 2, "note")
    local entry = Entries.review(review, tmp, nil)

    assert.are.equal("review", entry.kind)
    -- The row is the `{lines}` reference plus the note's first line; the
    -- preview renders what a `{reviews}` send would produce.
    assert.are.equal("a.lua :L1-2  note", entry.text)
    assert.are.same({ "a.lua :L1-2 note" }, Entries.preview(entry))
  end)

  it("spells a Review row in the focused Tool's dialect", function()
    local path = vim.fs.joinpath(tmp, "a.lua")
    local buf = named_buffer(path, { "a", "b" })
    local review = Review.add(buf, 1, 2, "note")
    Config.options.cli.tools = {
      dialect = {
        cmd = { "codex" },
        format = function(file, loc)
          return "@" .. file .. (loc and (" " .. loc) or "")
        end,
      },
    }
    local entry = Entries.review(review, tmp, "dialect")

    assert.are.equal("@a.lua :L1-2  note", entry.text)
    assert.are.same({ "@a.lua :L1-2 note" }, Entries.preview(entry))
  end)

  it("keeps a Review row readable when the Tool declines the reference", function()
    local path = vim.fs.joinpath(tmp, "a.lua")
    local buf = named_buffer(path, { "a", "b" })
    local review = Review.add(buf, 1, 2, "note")
    Config.options.cli.tools = {
      silent = {
        cmd = { "codex" },
        format = function()
          return ""
        end,
      },
    }
    local entry = Entries.review(review, tmp, "silent")

    -- The row falls back to the default dialect so the list stays navigable;
    -- the preview keeps the "no reference" answer a send would give.
    assert.are.equal("a.lua :L1-2  note", entry.text)
    assert.are.same({ "" }, Entries.preview(entry))
  end)
end)
