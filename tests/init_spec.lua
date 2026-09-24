---@module 'luassert'

local Helpers = require("helpers")

describe("vantage.init", function()
  local Backend
  local Init
  local Config
  local Picker

  setup(function()
    Helpers.reload_vantage()
    Init = require("vantage")
    Config = require("vantage.config")
    Backend = require("vantage.backend")
    Picker = require("vantage.frontend.picker")
    pcall(vim.api.nvim_del_user_command, "Vantage")
  end)

  teardown(function()
    pcall(vim.api.nvim_del_user_command, "Vantage")
    Helpers.reload_vantage()
  end)

  it("resolves implementations and registers the command", function()
    Init.setup({ backend = "tmux", picker = "native" })

    assert.are.equal(2, vim.fn.exists(":Vantage"))
    assert.are.equal("tmux", Config.options.backend)
    assert.is_true(pcall(Backend.get))
    assert.are.same({ command = false }, Picker.capabilities())
  end)

  it("installs the terminal's action resolver", function()
    pcall(vim.api.nvim_del_user_command, "Vantage")
    Init.setup({ backend = "tmux", picker = "native" })

    -- Open the real Terminal the resolver was installed into and check that a
    -- configured token arrived as the action's function, not as its string.
    local Terminal = require("vantage.frontend.terminal")
    Config.options.cli.win.keys = { { "<c-h>", "hide", desc = "hide" } }
    local jobstart = vim.fn.jobstart
    vim.fn.jobstart = function()
      return 4242
    end
    local ok, opened = pcall(Terminal.open, { "attach" })
    vim.fn.jobstart = jobstart
    assert(ok, opened)
    assert.is_true(opened)

    local callback
    for _, map in ipairs(vim.api.nvim_buf_get_keymap(Terminal.buffer, "n")) do
      if map.lhs:lower() == "<c-h>" then
        callback = map.callback
      end
    end
    assert.are.equal("function", type(callback))

    Terminal.destroy()
    Config.options.cli.win.keys = {}
  end)

  it("fails fast before installing command side effects", function()
    pcall(vim.api.nvim_del_user_command, "Vantage")
    local ok, err = pcall(Init.setup, { backend = "missing" })

    assert.is_false(ok)
    assert.is_true(tostring(err):find("unknown backend 'missing'", 1, true) ~= nil)
    assert.are.equal(0, vim.fn.exists(":Vantage"))
    assert.is_false(pcall(Backend.get))
  end)

  it("fails fast when the driver violates the vantage.Driver contract", function()
    package.loaded["vantage.backend.tmux"] = {}
    local ok, err = pcall(Init.setup, { backend = "tmux" })
    assert.is_false(ok)
    assert.is_true(tostring(err):find("does not implement vantage.Driver", 1, true) ~= nil)
  end)

  it("checkhealth still reports after setup fails", function()
    pcall(Init.setup, { backend = "missing" })
    local Health = require("vantage.health")
    local ok, err = pcall(Health.check)
    assert.is_true(ok, tostring(err))
  end)
end)
