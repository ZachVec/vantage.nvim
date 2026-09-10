---@module 'luassert'

local Helpers = require("helpers")

describe("vantage.init", function()
  local Init
  local Config
  local Driver
  local Picker

  setup(function()
    Helpers.reload_vantage()
    Init = require("vantage")
    Config = require("vantage.config")
    Driver = require("vantage.backend.driver")
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
    assert.is_true(pcall(Driver.get))
    assert.are.same({ preview = false, command = false }, Picker.capabilities())
  end)

  it("fails fast before installing command side effects", function()
    pcall(vim.api.nvim_del_user_command, "Vantage")
    local ok, err = pcall(Init.setup, { backend = "missing" })

    assert.is_false(ok)
    assert.is_true(tostring(err):find("unknown backend 'missing'", 1, true) ~= nil)
    assert.are.equal(0, vim.fn.exists(":Vantage"))
    assert.is_false(pcall(Driver.get))
  end)

  it("fails fast when the driver violates the vantage.Driver contract", function()
    package.loaded["vantage.backend.driver.tmux"] = {}
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
