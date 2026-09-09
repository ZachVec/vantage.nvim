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
end)
