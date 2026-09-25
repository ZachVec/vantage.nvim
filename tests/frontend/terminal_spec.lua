---@module 'luassert'

local Helpers = require("helpers")

describe("vantage.frontend.terminal", function()
  local Config
  local Terminal

  setup(function()
    Helpers.reload_vantage()
    Config = require("vantage.config")
    Terminal = require("vantage.frontend.terminal")
  end)

  teardown(function()
    for _, win in ipairs(vim.api.nvim_list_wins()) do
      if vim.api.nvim_win_is_valid(win) and vim.api.nvim_win_get_config(win).relative ~= "" then
        pcall(vim.api.nvim_win_close, win, true)
      end
    end
    Helpers.reload_vantage()
  end)

  --- Install `resolve` the way the composition root does, then open the
  --- Terminal with a stubbed job — no client starts, but `open` runs to
  --- completion. Returns `open`'s answer.
  ---@param resolve? fun(rhs: any): any
  ---@return boolean
  local function open(resolve)
    local jobstart = vim.fn.jobstart
    vim.fn.jobstart = function()
      return 4242
    end
    Terminal.setup(resolve or function(rhs)
      return rhs
    end)
    local ok, opened = pcall(Terminal.open, { "attach" })
    vim.fn.jobstart = jobstart
    assert(ok, opened)
    return opened
  end

  --- The buffer-local keymap bound to `lhs` in `mode`, or nil.
  ---@param buffer integer
  ---@param lhs string
  ---@param mode? string
  ---@return table?
  local function mapped(buffer, lhs, mode)
    for _, map in ipairs(vim.api.nvim_buf_get_keymap(buffer, mode or "n")) do
      if map.lhs:lower() == lhs:lower() then
        return map
      end
    end
    return nil
  end

  it("opens the configured float layout", function()
    Config.options.cli.win.layout = "float"

    assert.is_true(open())

    local win = Terminal.window
    assert.is_true(vim.api.nvim_win_is_valid(win))
    assert.are.equal("editor", vim.api.nvim_win_get_config(win).relative)
    Terminal.destroy()
  end)

  it("opens the full layout in a dedicated tab", function()
    Config.options.cli.win.layout = "full"
    local before = #vim.api.nvim_list_tabpages()

    assert.is_true(open())

    assert.is_true(vim.api.nvim_win_is_valid(Terminal.window))
    assert.are.equal(before + 1, #vim.api.nvim_list_tabpages())
    Terminal.destroy()
    assert.are.equal(before, #vim.api.nvim_list_tabpages())
  end)

  it("hides the window but keeps the buffer and the job", function()
    assert.is_true(open())
    local buffer, job = Terminal.buffer, Terminal.job

    Terminal.hide()

    assert.is_nil(Terminal.window)
    assert.is_true(vim.api.nvim_buf_is_valid(buffer))
    assert.are.equal(job, Terminal.job)
    Terminal.destroy()
  end)

  it("shows the hidden buffer again, focused", function()
    assert.is_true(open())
    local buffer, job = Terminal.buffer, Terminal.job
    Terminal.hide()

    assert.is_true(Terminal.show())

    assert.are.equal(buffer, Terminal.buffer)
    assert.are.equal(job, Terminal.job)
    assert.are.equal(Terminal.window, vim.api.nvim_get_current_win())
    assert.are.equal(buffer, vim.api.nvim_win_get_buf(Terminal.window))
    Terminal.destroy()
  end)

  it("answers false from show with no client, and ignores a stray hide", function()
    Terminal.destroy()

    assert.is_false(Terminal.show())
    assert.is_true(pcall(Terminal.hide))
    assert.is_nil(Terminal.window)
  end)

  it("owns the mode with one window-entry rule, installed once", function()
    Terminal.setup(function(rhs)
      return rhs
    end)
    Terminal.setup(function(rhs)
      return rhs
    end)

    assert.are.equal(1, vim.fn.exists("#vantage_terminal_mode#WinEnter"))
  end)

  it("installs the configured keys on the buffer it opened, resolving each rhs", function()
    local switched = function() end
    Config.options.cli.win.keys = { { "<c-s>", "switch", desc = "switch Agent" } }

    assert.is_true(open(function(rhs)
      return rhs == "switch" and switched or rhs
    end))

    local map = mapped(Terminal.buffer, "<c-s>")
    assert.is_not_nil(map, "no <c-s> mapping on the terminal buffer")
    assert.are.equal(switched, map.callback)
    assert.are.equal("switch Agent", map.desc)
    Terminal.destroy()
  end)

  it("binds a non-action rhs verbatim in every mode the entry names", function()
    Config.options.cli.win.keys = { { "<c-q>", "zzz", mode = { "n", "t" } } }

    assert.is_true(open())

    assert.are.equal("zzz", mapped(Terminal.buffer, "<c-q>", "n").rhs)
    assert.are.equal("zzz", mapped(Terminal.buffer, "<c-q>", "t").rhs)
    Terminal.destroy()
  end)

  it("binds a token verbatim when no resolver was installed", function()
    -- Reload so this runs against a Terminal that no spec has called
    -- `setup` on — the identity default is the state under test.
    Helpers.reload_vantage()
    local Fresh = require("vantage.frontend.terminal")
    local FreshConfig = require("vantage.config")
    FreshConfig.options.cli.win.keys = { { "<c-s>", "switch" } }

    local jobstart = vim.fn.jobstart
    vim.fn.jobstart = function()
      return 4242
    end
    local ok, opened = pcall(Fresh.open, { "attach" })
    vim.fn.jobstart = jobstart
    assert(ok, opened)
    assert.is_true(opened)

    assert.are.equal("switch", mapped(Fresh.buffer, "<c-s>").rhs)
    Fresh.destroy()
  end)

  it("warns on a malformed entry and keeps installing the rest", function()
    local notified = {}
    local notify = vim.notify
    vim.notify = function(msg, level)
      notified[#notified + 1] = { msg, level }
    end
    Config.options.cli.win.keys = { { "<c-x>" }, { "<c-y>", "yy" } }

    local ok, opened = pcall(open)
    vim.notify = notify

    assert(ok, opened)
    assert.is_true(opened)
    assert.are.equal(
      "vantage: keymap entry must be a 4-tuple { lhs, rhs, mode?, desc? }",
      notified[1] and notified[1][1]
    )
    assert.are.equal(vim.log.levels.WARN, notified[1] and notified[1][2])
    assert.is_nil(mapped(Terminal.buffer, "<c-x>"))
    assert.are.equal("yy", mapped(Terminal.buffer, "<c-y>").rhs)
    Terminal.destroy()
  end)
end)
