---@module 'luassert'

local Helpers = require("helpers")

describe("vantage.commands.gather", function()
  local Config
  local Entries
  local Gather
  local backend
  local picker
  local pick_spec
  local pick_opts
  local focused
  local notified
  local original_notify
  local tmp
  local bufs = {}

  local function write(relpath, lines)
    local path = vim.fs.joinpath(tmp, relpath)
    vim.fn.mkdir(vim.fn.fnamemodify(path, ":h"), "p")
    vim.fn.writefile(lines or { "x" }, path)
    return path
  end

  --- Run a flow without choosing rows and return the entries its source
  --- produces, plus the options the flow passed to the Picker.
  ---@param source "files"|"buffers"
  ---@return vantage.picker.Entry[]
  ---@return vantage.PickOpts
  local function run(source)
    pick_spec = nil
    pick_opts = nil
    if source == "files" then
      Gather.files()
    else
      Gather.buffers()
    end
    assert.is_not_nil(pick_spec)
    return Helpers.entries(pick_spec), pick_opts
  end

  --- A listed, on-disk buffer that starts out unmodified.
  ---@param path string
  ---@param lines string[]
  ---@return integer
  local function listed_buffer(path, lines)
    local buf = vim.fn.bufadd(path)
    vim.fn.bufload(buf)
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
    vim.bo[buf].buflisted = true
    vim.bo[buf].modified = false
    bufs[#bufs + 1] = buf
    return buf
  end

  setup(function()
    Helpers.reload_vantage()
    Config = require("vantage.config")
    original_notify = vim.notify
    vim.notify = function(msg)
      notified[#notified + 1] = msg
    end
    notified = {}

    backend = { sent = {} }
    function backend.focus(pid)
      if pid == nil then
        return nil, Config.FOCUS_NO_TERMINAL
      end
      if focused == nil then
        return nil, Config.FOCUS_NO_FOCUS
      end
      return focused, nil
    end
    function backend.send(agent, text)
      backend.sent[#backend.sent + 1] = { agent = agent, text = text }
      return true, nil
    end

    picker = {}
    function picker.pick_fancy(spec, opts)
      pick_spec, pick_opts = spec, opts
    end

    package.loaded["vantage.backend"] = backend
    package.loaded["vantage.frontend.picker"] = picker
    -- Only the job pid is needed; the flows read the Focus through the Backend.
    package.loaded["vantage.frontend.terminal"] = {
      pid = function()
        return 42
      end,
    }
    Gather = require("vantage.commands.gather")
    Entries = require("vantage.frontend.entries")
  end)

  teardown(function()
    vim.notify = original_notify
    Helpers.reload_vantage()
  end)

  before_each(function()
    notified = {}
    backend.sent = {}
    pick_spec = nil
    pick_opts = nil
    Config.options.cli.tools = {}
    Config.options.gather.join = "\n"
    tmp = vim.fn.tempname()
    vim.fn.mkdir(tmp, "p")
    focused = { id = "@1", seq = 1, group = "g", cmd = "codex", cwd = tmp, tool = "codex" }
  end)

  after_each(function()
    for _, buf in ipairs(bufs) do
      Helpers.wipe(buf)
    end
    bufs = {}
    vim.fn.delete(tmp, "rf")
  end)

  it("lists files under the agent cwd, sorted and relative", function()
    write("a.lua", { "a" })
    write("sub/b.lua", { "b" })

    local items = run("files")
    assert.are.equal(2, #items)
    assert.are.equal("a.lua", items[1].text)
    assert.are.equal("sub/b.lua", items[2].text)
    assert.are.same({ "a" }, Entries.preview(items[1]))
  end)

  it("falls back to a Lua walk when no lister is available", function()
    write("a.lua", { "a" })
    write("sub/b.lua", { "b" })
    write(".git/HEAD", { "ref: refs/heads/main" })

    local path_env = vim.env.PATH
    vim.env.PATH = ""
    local ok, items = pcall(run, "files")
    vim.env.PATH = path_env

    assert.is_true(ok)
    assert.are.equal(2, #items)
    assert.are.equal("a.lua", items[1].text)
    assert.are.equal("sub/b.lua", items[2].text)
  end)

  it("lists on-disk listed buffers and marks modified ones", function()
    local a = write("a.lua", { "a" })
    local b = write("b.lua", { "b", "b2" })
    listed_buffer(a, { "a" })
    local dirty = listed_buffer(b, { "b", "b2" })
    vim.bo[dirty].modified = true

    local items = run("buffers")
    assert.are.equal(2, #items)
    assert.are.equal("a.lua", items[1].text)
    assert.are.equal("b.lua [+]", items[2].text)
    assert.are.same({ "b", "b2" }, Entries.preview(items[2]))
  end)

  it("skips unnamed, unlisted, and off-disk buffers", function()
    local path = write("a.lua", { "a" })
    listed_buffer(path, { "a" })
    Helpers.buffer({ "scratch" }, vim.fs.joinpath(tmp, "gone.lua"))

    local items = run("buffers")
    assert.are.equal(1, #items)
    assert.are.equal("a.lua", items[1].text)
  end)

  it("sends chosen references one per line with a trailing space", function()
    write("a.lua", { "a" })
    write("sub/b.lua", { "b" })

    local items, opts = run("files")
    opts.on_choices({ items[1], items[2] })

    assert.are.equal("a.lua\nsub/b.lua ", backend.sent[1].text)
    assert.are.equal(focused, backend.sent[1].agent)
  end)

  it("adds the dialect prefix per reference and joins them", function()
    write("a.lua", { "a" })
    write("sub/b.lua", { "b" })
    Config.options.cli.tools = {
      codex = {
        cmd = { "codex" },
        format = function(file, loc)
          assert.are.equal(nil, loc) -- gathered entries are whole-file references
          return "@" .. file
        end,
      },
    }

    local items, opts = run("files")
    opts.on_choices({ items[1], items[2] })
    assert.are.equal("@a.lua\n@sub/b.lua ", backend.sent[1].text)

    Config.options.gather.join = " "
    local spaced, spaced_opts = run("files")
    spaced_opts.on_choices({ spaced[1], spaced[2] })
    assert.are.equal("@a.lua @sub/b.lua ", backend.sent[2].text)
  end)

  it("drops the send and warns when the format hook returns nothing", function()
    write("a.lua", { "a" })
    for _, declined in ipairs({
      function()
        return nil
      end,
      function()
        return ""
      end,
    }) do
      Config.options.cli.tools = { codex = { cmd = { "codex" }, format = declined } }
      local items, opts = run("files")
      opts.on_choices({ items[1] })
    end

    assert.are.equal(0, #backend.sent)
    assert.is_true(notified[1]:find("format hook", 1, true) ~= nil)
  end)

  it("warns instead of picking when no agent is focused", function()
    focused = nil

    Gather.files()

    assert.are.equal(nil, pick_spec)
    assert.is_true(notified[1]:find("no focused agent", 1, true) ~= nil)
  end)

  it("opens the picker with nothing when a source has no candidates", function()
    local items = run("buffers")

    assert.are.equal(0, #items)
    assert.are.same({}, notified)
  end)
end)
