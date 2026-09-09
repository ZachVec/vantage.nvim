---@module 'luassert'

local Helpers = require("helpers")

describe("vantage.frontend.picker", function()
  local Config
  local Picker

  setup(function()
    Helpers.reload_vantage()
    Config = require("vantage.config")
    Picker = require("vantage.frontend.picker")
  end)

  teardown(function()
    Helpers.reload_vantage()
  end)

  it("fails fast on an unknown picker", function()
    Config.options.picker = "missing"
    local ok, err = pcall(Picker.setup)
    assert.is_false(ok)
    assert.is_true(tostring(err):find("unknown picker 'missing'", 1, true) ~= nil)
  end)

  it("fails fast when the configured picker dependency is missing", function()
    package.loaded["vantage.frontend.picker.native"] = {
      requires = "vantage-no-such-picker",
      capabilities = { preview = true, command = true },
      pick = function()
        return false
      end,
      pick_plain = function() end,
    }
    Config.options.picker = "native"
    local ok, err = pcall(Picker.setup)
    assert.is_false(ok)
    assert.is_true(tostring(err):find("requires 'vantage-no-such-picker'", 1, true) ~= nil)
  end)

  it("fails fast when an implementation violates the PickerImpl contract", function()
    package.loaded["vantage.frontend.picker.native"] = {
      capabilities = { preview = true, command = true },
      pick = function()
        return false
      end,
    }
    Config.options.picker = "native"
    local ok, err = pcall(Picker.setup)
    assert.is_false(ok)
    assert.is_true(tostring(err):find("does not implement vantage.PickerImpl", 1, true) ~= nil)
  end)

  it("returns capabilities and does not expose get()", function()
    package.loaded["vantage.frontend.picker.native"] = {
      capabilities = { preview = false, command = false },
      pick = function()
        return false
      end,
      pick_plain = function() end,
    }
    Config.options.picker = "native"
    Picker.setup()

    assert.are.same({ preview = false, command = false }, Picker.capabilities())
    assert.are.equal(nil, Picker.get)
  end)

  it("omits commands when the implementation has no command capability", function()
    local received
    package.loaded["vantage.frontend.picker.native"] = {
      capabilities = { preview = false, command = false },
      pick = function(_, opts)
        received = opts
        return false
      end,
      pick_plain = function() end,
    }
    Config.options.picker = "native"
    Picker.setup()

    local spec = { prompt = "pick", items_provider = function() end }
    local empty = Picker.pick(spec, {
      on_choice = function() end,
      commands = { {
        "<C-x>",
        function()
          return true
        end,
      } },
    })

    assert.is_false(empty)
    assert.are.equal(nil, received.commands)
  end)

  it("passes commands through when the implementation supports them", function()
    local received
    local command = {
      "<C-x>",
      function()
        return true
      end,
      desc = "delete",
    }
    package.loaded["vantage.frontend.picker.native"] = {
      capabilities = { preview = true, command = true },
      pick = function(_, opts)
        received = opts
        return false
      end,
      pick_plain = function() end,
    }
    Config.options.picker = "native"
    Picker.setup()

    Picker.pick({ prompt = "pick", items_provider = function() end }, {
      on_choice = function() end,
      commands = { command },
    })

    assert.are.same({ command }, received.commands)
  end)

  it("rejects duplicate command lhs values", function()
    package.loaded["vantage.frontend.picker.native"] = {
      capabilities = { preview = true, command = true },
      pick = function()
        return false
      end,
      pick_plain = function() end,
    }
    Config.options.picker = "native"
    Picker.setup()

    local ok, err = pcall(Picker.pick, { prompt = "pick", items_provider = function() end }, {
      on_choice = function() end,
      commands = {
        {
          "<C-x>",
          function()
            return true
          end,
        },
        {
          "<C-x>",
          function()
            return true
          end,
        },
      },
    })
    assert.is_false(ok)
    assert.is_true(tostring(err):find("duplicate picker command", 1, true) ~= nil)
  end)
end)
