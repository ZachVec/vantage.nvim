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
      capabilities = { preview = true, command = true, multi = false },
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

  it("accepts a dependency loadable through require even when it is not on runtimepath", function()
    local dep = "vantage-test-picker-dependency"
    package.preload[dep] = function()
      return { loaded = true }
    end
    package.loaded[dep] = nil
    package.loaded["vantage.frontend.picker.native"] = {
      requires = dep,
      capabilities = { preview = true, command = true, multi = false },
      pick = function()
        return false
      end,
      pick_plain = function() end,
    }
    Config.options.picker = "native"

    assert.is_true(pcall(Picker.setup))
    package.preload[dep] = nil
    package.loaded[dep] = nil
  end)

  it("fails fast when an implementation violates the PickerImpl contract", function()
    package.loaded["vantage.frontend.picker.native"] = {
      capabilities = { preview = true, command = true, multi = false },
      pick = function()
        return false
      end,
    }
    Config.options.picker = "native"
    local ok, err = pcall(Picker.setup)
    assert.is_false(ok)
    assert.is_true(tostring(err):find("does not implement vantage.PickerImpl", 1, true) ~= nil)
  end)

  it("fails fast when a multi-capable implementation lacks pick_multi", function()
    package.loaded["vantage.frontend.picker.native"] = {
      capabilities = { preview = true, command = true, multi = true },
      pick = function()
        return false
      end,
      pick_plain = function() end,
    }
    Config.options.picker = "native"
    local ok, err = pcall(Picker.setup)
    assert.is_false(ok)
    assert.is_true(tostring(err):find("does not implement vantage.PickerImpl", 1, true) ~= nil)
  end)

  it("returns capabilities and does not expose get()", function()
    package.loaded["vantage.frontend.picker.native"] = {
      capabilities = { preview = false, command = false, multi = false },
      pick = function()
        return false
      end,
      pick_plain = function() end,
    }
    Config.options.picker = "native"
    Picker.setup()

    assert.are.same({ preview = false, command = false, multi = false }, Picker.capabilities())
    assert.are.equal(nil, Picker.get)
  end)

  it("omits commands when the implementation has no command capability", function()
    local received
    package.loaded["vantage.frontend.picker.native"] = {
      capabilities = { preview = false, command = false, multi = false },
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
      capabilities = { preview = true, command = true, multi = false },
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
      capabilities = { preview = true, command = true, multi = false },
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

  it("requires on_choices for a multi pick", function()
    Config.options.picker = "native"
    Picker.setup()

    local ok, err = pcall(Picker.pick_multi, { prompt = "pick", items_provider = function() end }, {})
    assert.is_false(ok)
    assert.is_true(tostring(err):find("on_choices", 1, true) ~= nil)
  end)

  it("passes a multi pick to an implementation with the multi capability", function()
    local received
    package.loaded["vantage.frontend.picker.native"] = {
      capabilities = { preview = true, command = true, multi = true },
      pick = function()
        return false
      end,
      pick_multi = function(_, opts)
        received = opts
        return false
      end,
      pick_plain = function() end,
    }
    Config.options.picker = "native"
    Picker.setup()

    local on_close = function() end
    local empty = Picker.pick_multi({ prompt = "pick", items_provider = function() end }, {
      on_choices = function() end,
      on_close = on_close,
    })

    assert.is_false(empty)
    assert.are.equal("function", type(received.on_choices))
    assert.are.equal(on_close, received.on_close)
  end)

  it("degrades a multi pick to one choice without the multi capability", function()
    local received
    local chosen
    package.loaded["vantage.frontend.picker.native"] = {
      capabilities = { preview = false, command = false, multi = false },
      pick = function(_, opts)
        received = opts
        return false
      end,
      pick_plain = function() end,
    }
    Config.options.picker = "native"
    Picker.setup()

    Picker.pick_multi({ prompt = "pick", items_provider = function() end }, {
      on_choices = function(items)
        chosen = items
      end,
    })
    received.on_choice("row")

    assert.are.same({ "row" }, chosen)
  end)
end)
