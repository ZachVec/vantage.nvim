---@module 'luassert'

local Helpers = require("helpers")

describe("vantage.commands.review", function()
  local Config
  local Review
  local ReviewCmd
  local Util
  local attachment
  local backend
  local captured_spec
  local tmp
  local bufs = {}

  --- A named buffer registered as a Review of lines 1-2.
  ---@param path string
  local function review_at(path)
    local buf = Helpers.buffer({ "a", "b" }, path)
    bufs[#bufs + 1] = buf
    return Review.add(buf, 1, 2, "note")
  end

  --- The Review list rows the flow builds.
  ---@return vantage.picker.Entry[]
  local function rows()
    captured_spec = nil
    ReviewCmd.run("list", 1, 1)
    assert.is_not_nil(captured_spec)
    return Helpers.entries(captured_spec)
  end

  setup(function()
    Helpers.reload_vantage()
    Config = require("vantage.config")
    Util = require("vantage.util")
    Review = require("vantage.frontend.review")
    Review.setup()

    backend = {}
    attachment = {}
    function attachment.focus()
      attachment.called = true
      return backend.focused, backend.focus_reason
    end
    package.loaded["vantage.backend"] = backend
    package.loaded["vantage.frontend.picker"] = {
      pick_fancy = function(spec)
        captured_spec = spec
      end,
    }
    package.loaded["vantage.frontend.terminal"] = { attachment = attachment }
    ReviewCmd = require("vantage.commands.review")
  end)

  before_each(function()
    backend.focused = nil
    backend.focus_reason = nil
    attachment.called = false
    Config.options.reviews.item = "{lines} {note}"
    Config.options.cli.tools = {}
    tmp = vim.fn.tempname()
    vim.fn.mkdir(tmp, "p")
  end)

  after_each(function()
    Review.clear()
    for _, buf in ipairs(bufs) do
      Helpers.wipe(buf)
    end
    bufs = {}
    vim.fn.delete(tmp, "rf")
  end)

  teardown(function()
    Review.clear()
    Helpers.reload_vantage()
  end)

  it("spells rows against Neovim's cwd and the default dialect, reading no Focus", function()
    backend.focused = { cwd = tmp, tool = "dialect", id = "@1" }
    Config.options.cli.tools = {
      dialect = {
        cmd = { "codex" },
        format = function(file, loc)
          return "@" .. file .. (loc and (" " .. loc) or "")
        end,
      },
    }
    review_at(vim.fs.joinpath(Util.cwd(), "scratch", "a.lua"))

    local items = rows()

    -- The list is a display, not a send: it never reads the Focus, so a live
    -- Focus's cwd and dialect do not change the row.
    assert.is_false(attachment.called)
    assert.are.equal("scratch/a.lua :L1-2  note", items[1].text)
  end)

  it("spells rows without a Focus the same way", function()
    backend.focus_reason = Config.FOCUS_NO_FOCUS
    review_at(vim.fs.joinpath(Util.cwd(), "scratch", "a.lua"))

    local items = rows()

    assert.is_false(attachment.called)
    assert.are.equal("scratch/a.lua :L1-2  note", items[1].text)
  end)

  it("clears Reviews that are invalidated and hidden from the list", function()
    local path = vim.fs.joinpath(tmp, "a.lua")
    local buf = Helpers.buffer({ "a", "b", "c" }, path)
    bufs[#bufs + 1] = buf
    Review.add(buf, 1, 1, "note")
    -- Deleting the reviewed line invalidates the Review: it leaves the list
    -- but stays registered, and a clear still has to reach it.
    vim.api.nvim_buf_set_lines(buf, 0, 1, false, {})
    assert.are.same({}, rows())

    local original_confirm = vim.fn.confirm
    vim.fn.confirm = function()
      return 1
    end
    ReviewCmd.run("clear", 1, 1)
    vim.fn.confirm = original_confirm

    assert.are.equal(0, Review.count())
    assert.are.same({}, rows())
  end)
end)
