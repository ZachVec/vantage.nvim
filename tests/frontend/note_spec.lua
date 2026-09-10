---@module 'luassert'

local Helpers = require("helpers")

describe("vantage.frontend.note", function()
  local Note

  setup(function()
    Helpers.reload_vantage()
    Note = require("vantage.frontend.note")
  end)

  teardown(function()
    for _, win in ipairs(vim.api.nvim_list_wins()) do
      if vim.api.nvim_win_is_valid(win) and vim.api.nvim_win_get_config(win).relative ~= "" then
        pcall(vim.api.nvim_win_close, win, true)
      end
    end
    Helpers.reload_vantage()
  end)

  it("opens an editable scratch float and runs on_close when wiped", function()
    local closed = false
    Note.open({
      text = "hello\nworld",
      title = "Note",
      footer = "<Esc> save",
      on_commit = function() end,
      on_close = function()
        closed = true
      end,
    })

    local win = vim.api.nvim_get_current_win()
    local buf = vim.api.nvim_win_get_buf(win)
    assert.are.equal("editor", vim.api.nvim_win_get_config(win).relative)
    assert.are.same({ "hello", "world" }, vim.api.nvim_buf_get_lines(buf, 0, -1, false))

    vim.api.nvim_buf_delete(buf, { force = true })
    assert.is_true(closed)
  end)
end)
