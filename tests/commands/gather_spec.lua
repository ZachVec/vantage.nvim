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
  local original_path
  local original_cwd
  local tmp
  local bufs = {}
  local bin_dirs = {}
  local roots = {}

  local function write(relpath, lines)
    local path = vim.fs.joinpath(tmp, relpath)
    vim.fn.mkdir(vim.fn.fnamemodify(path, ":h"), "p")
    vim.fn.writefile(lines or { "x" }, path)
    return path
  end

  ---@param items vantage.picker.Entry[]
  ---@return string[]
  local function texts(items)
    return vim.tbl_map(function(item)
      return item.text
    end, items)
  end

  --- The first entry whose text names `text`.
  ---@param items vantage.picker.Entry[]
  ---@param text string
  ---@return vantage.picker.Entry
  local function named(items, text)
    for _, item in ipairs(items) do
      if item.text == text then
        return item
      end
    end
    error(("no entry named '%s'"):format(text))
  end

  --- A directory of executable fake listers, one shell script per name.
  ---@param scripts table<string, string>
  ---@return string dir
  local function bins(scripts)
    local dir = vim.fn.tempname()
    vim.fn.mkdir(dir, "p")
    for name, body in pairs(scripts) do
      local path = vim.fs.joinpath(dir, name)
      vim.fn.writefile({ "#!/bin/sh", body }, path)
      vim.fn.setfperm(path, "rwxr-xr-x")
    end
    bin_dirs[#bin_dirs + 1] = dir
    return dir
  end

  --- Point PATH at the fakes; `keep_path` leaves the real PATH behind them, for
  --- a lister that needs a real command of its own.
  ---@param dir string
  ---@param keep_path? boolean
  local function use_bins(dir, keep_path)
    vim.env.PATH = keep_path and (dir .. ":" .. original_path) or dir
  end

  --- Run a flow without choosing rows; captures the spec and options.
  ---@param source "files"|"buffers"
  local function capture(source)
    pick_spec, pick_opts = nil, nil
    if source == "files" then
      Gather.files()
    else
      Gather.buffers()
    end
    assert.is_not_nil(pick_spec)
    return pick_spec, pick_opts
  end

  --- Drive a spec's source, counting the batches it emitted.
  ---@param spec vantage.PickSpec
  ---@return vantage.picker.Entry[] items
  ---@return integer batches
  local function drain(spec)
    local items, batches, finished = {}, 0, false
    spec.items(function(chunk)
      batches = batches + 1
      vim.list_extend(items, chunk)
    end, function()
      finished = true
    end)
    vim.wait(5000, function()
      return finished
    end, 10)
    assert(finished, "source did not finish")
    return items, batches
  end

  --- Run a flow and return the entries its source produces, plus the options
  --- the flow passed to the Picker.
  ---@param source "files"|"buffers"
  ---@return vantage.picker.Entry[]
  ---@return vantage.PickOpts
  local function run(source)
    local spec, opts = capture(source)
    return Helpers.entries(spec), opts
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
    original_path = vim.env.PATH
    original_cwd = vim.fn.getcwd()
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
    vim.env.PATH = original_path
    Config.options.cli.tools = {}
    Config.options.gather.join = "\n"
    tmp = vim.fn.tempname()
    vim.fn.mkdir(tmp, "p")
    -- `files` lists from Neovim's global cwd; pin it to the fixture root.
    vim.fn.chdir(tmp)
    focused = { id = "@1", seq = 1, group = "g", cmd = "codex", cwd = tmp, tool = "codex" }
  end)

  after_each(function()
    vim.env.PATH = original_path
    vim.fn.chdir(original_cwd)
    for _, buf in ipairs(bufs) do
      Helpers.wipe(buf)
    end
    bufs = {}
    vim.fn.delete(tmp, "rf")
    for _, dir in ipairs(roots) do
      vim.fn.delete(dir, "rf")
    end
    roots = {}
    for _, dir in ipairs(bin_dirs) do
      vim.fn.delete(dir, "rf")
    end
    bin_dirs = {}
  end)

  it("streams files under Neovim's cwd, relative to it", function()
    write("a.lua", { "a" })
    write("sub/b.lua", { "b" })

    local items = run("files")
    local listed = texts(items)
    table.sort(listed)

    assert.are.same({ "a.lua", "sub/b.lua" }, listed)
    assert.are.same({ "a" }, Entries.preview(named(items, "a.lua")))
  end)

  it("lists from Neovim's cwd and spells references against the agent's", function()
    local root = vim.fn.tempname()
    roots[#roots + 1] = root
    local sub = vim.fs.joinpath(root, "sub")
    vim.fn.mkdir(sub, "p")
    vim.fn.writefile({ "a" }, vim.fs.joinpath(root, "a.lua"))
    vim.fn.writefile({ "b" }, vim.fs.joinpath(sub, "b.lua"))
    vim.fn.chdir(root)
    focused.cwd = sub

    local items, opts = run("files")
    local listed = texts(items)
    table.sort(listed)
    -- Displayed relative to the tree that was listed.
    assert.are.same({ "a.lua", "sub/b.lua" }, listed)

    opts.on_choices({ named(items, "a.lua"), named(items, "sub/b.lua") })
    -- Outside the Agent's cwd escapes to an absolute path; inside is relative.
    assert.are.equal(vim.fs.normalize(vim.fs.joinpath(root, "a.lua")) .. "\nb.lua ", backend.sent[1].text)
  end)

  it("sends absolute references when the listed tree is outside the agent's cwd", function()
    local other = vim.fn.tempname()
    roots[#roots + 1] = other
    vim.fn.mkdir(other, "p")
    vim.fn.writefile({ "z" }, vim.fs.joinpath(other, "z.lua"))
    vim.fn.chdir(other)

    local items, opts = run("files")
    assert.are.same({ "z.lua" }, texts(items))

    opts.on_choices({ items[1] })
    assert.are.equal(vim.fs.normalize(vim.fs.joinpath(other, "z.lua")) .. " ", backend.sent[1].text)
  end)

  it("keeps the lister's own order and reads one batch per chunk", function()
    write("z.lua", { "z" })
    write("a.lua", { "a" })
    use_bins(bins({ fd = "printf 'z.lua\\na.lua\\n'" }))

    local items, batches = drain(capture("files"))

    assert.are.same({ "z.lua", "a.lua" }, texts(items))
    assert.are.equal(1, batches)
  end)

  it("gives way to the next lister when one fails before producing a line", function()
    use_bins(bins({
      fd = "exit 2",
      rg = "printf 'b.lua\\n'",
      find = "printf 'z.lua\\n'",
    }))

    assert.are.same({ "b.lua" }, texts(run("files")))
  end)

  it("keeps what a lister produced before failing", function()
    use_bins(bins({
      fd = "printf 'a.lua\\n'; exit 2",
      rg = "printf 'b.lua\\n'",
    }))

    assert.are.same({ "a.lua" }, texts(run("files")))
  end)

  it("takes rg's empty answer as final instead of falling through to find", function()
    -- rg exits 1 when it found no files; find would list the ignored ones.
    use_bins(bins({
      rg = "exit 1",
      find = "printf 'z.lua\\n'",
    }))

    assert.are.same({}, texts(run("files")))
  end)

  it("uses find when it is the only lister", function()
    use_bins(bins({ find = "printf 'c.lua\\n'" }))

    assert.are.same({ "c.lua" }, texts(run("files")))
  end)

  it("warns when no lister is installed", function()
    vim.env.PATH = ""

    assert.are.same({}, run("files"))
    assert.is_true(notified[1]:find("no file lister", 1, true) ~= nil)
  end)

  it("finishes the chain when the last lister fails from its exit callback", function()
    -- Neovim's default `vim.notify` calls `nvim_echo`, which raises E5560 in a
    -- libuv callback; the chain's warning comes from exactly there.
    local strict = vim.notify
    vim.notify = function(msg)
      notified[#notified + 1] = msg
      if vim.in_fast_event() then
        error("E5560: nvim_echo must not be called in a fast event context")
      end
    end

    local ok, result = pcall(function()
      use_bins(bins({ fd = "exit 2" }))
      return run("files")
    end)
    vim.wait(500, function()
      return #notified > 0
    end, 10)
    vim.notify = strict

    assert.is_true(ok, tostring(result))
    assert.are.same({}, result)
    assert.is_true(notified[1]:find("file listing failed", 1, true) ~= nil)
  end)

  it("stops the running lister when the source is cancelled", function()
    local marker = vim.fs.joinpath(tmp, "killed")
    -- `sleep & wait` so the TERM trap runs while the lister is still going.
    use_bins(
      bins({
        fd = ("trap 'echo x > %s; exit 0' TERM; echo a.lua; sleep 30 & wait"):format(marker),
      }),
      true
    )

    local spec = capture("files")
    local listed = false
    local cancel = spec.items(function()
      listed = true
    end, function() end)
    assert.is_not_nil(cancel)

    -- The script installs its trap before it prints, so waiting for the first
    -- line makes the cancel below land in the trap rather than at exec time.
    vim.wait(5000, function()
      return listed
    end, 10)
    assert.is_true(listed)

    cancel()
    vim.wait(5000, function()
      return vim.fn.filereadable(marker) == 1
    end, 20)
    assert.are.equal(1, vim.fn.filereadable(marker))
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
    opts.on_choices({ named(items, "a.lua"), named(items, "sub/b.lua") })

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
    opts.on_choices({ named(items, "a.lua"), named(items, "sub/b.lua") })
    assert.are.equal("@a.lua\n@sub/b.lua ", backend.sent[1].text)

    Config.options.gather.join = " "
    local spaced, spaced_opts = run("files")
    spaced_opts.on_choices({ named(spaced, "a.lua"), named(spaced, "sub/b.lua") })
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
