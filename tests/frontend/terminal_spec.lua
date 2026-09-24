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

  --- Open the Terminal with a stubbed job — no client starts, but `open` runs
  --- to completion. Returns its answer.
  ---@param resolve? fun(rhs: any): any
  ---@return boolean
  local function open(resolve)
    local jobstart = vim.fn.jobstart
    vim.fn.jobstart = function()
      return 4242
    end
    local ok, opened = pcall(Terminal.open, { "attach" }, resolve or function(rhs)
      return rhs
    end)
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
    local buf = Helpers.buffer({ "terminal" })
    local win = Terminal.open_win(buf)

    assert.is_true(vim.api.nvim_win_is_valid(win))
    assert.are.equal("editor", vim.api.nvim_win_get_config(win).relative)

    pcall(vim.api.nvim_win_close, win, true)
    Helpers.wipe(buf)
  end)

  it("opens the full layout in a dedicated tab", function()
    Config.options.cli.win.layout = "full"
    local before = #vim.api.nvim_list_tabpages()
    local buf = Helpers.buffer({ "terminal" })
    local win = Terminal.open_win(buf)

    assert.is_true(vim.api.nvim_win_is_valid(win))
    assert.are.equal(before + 1, #vim.api.nvim_list_tabpages())

    vim.cmd("tabclose")
    Helpers.wipe(buf)
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
