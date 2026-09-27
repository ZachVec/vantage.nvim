---@module 'luassert'

local Helpers = require("helpers")

describe("vantage.frontend.picker", function()
  local Config
  local Picker

  --- Install a fake implementation under the `native` registry entry.
  ---@param impl table
  local function impl(impl)
    package.loaded["vantage.frontend.picker.native"] = impl
    Config.options.picker = "native"
  end

  --- A spec whose source finishes at once.
  ---@param overrides? table
  ---@return vantage.PickSpec
  local function pick_spec(overrides)
    return vim.tbl_extend("force", {
      prompt = "pick",
      many = false,
      items = function(_, done)
        done()
      end,
    }, overrides or {})
  end

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
    impl({
      requires = "vantage-no-such-picker",
      capabilities = { command = true },
      pick_fancy = function() end,
      pick_naive = function() end,
    })
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
    impl({
      requires = dep,
      capabilities = { command = true },
      pick_fancy = function() end,
      pick_naive = function() end,
    })

    assert.is_true(pcall(Picker.setup))
    package.preload[dep] = nil
    package.loaded[dep] = nil
  end)

  it("fails fast when an implementation violates the PickerImpl contract", function()
    impl({
      capabilities = { command = true },
      pick_fancy = function() end,
    })
    local ok, err = pcall(Picker.setup)
    assert.is_false(ok)
    assert.is_true(tostring(err):find("does not implement vantage.PickerImpl", 1, true) ~= nil)
  end)

  it("returns capabilities and does not expose get()", function()
    impl({
      capabilities = { command = false },
      pick_fancy = function() end,
      pick_naive = function() end,
    })
    Picker.setup()

    assert.are.same({ command = false }, Picker.capabilities())
    assert.are.equal(nil, Picker.get)
  end)

  it("omits commands when the implementation has no command capability", function()
    local received
    impl({
      capabilities = { command = false },
      pick_fancy = function(_, opts)
        received = opts
      end,
      pick_naive = function() end,
    })
    Picker.setup()

    Picker.pick_fancy(pick_spec(), {
      on_choices = function() end,
      commands = { {
        "<C-x>",
        function()
          return true
        end,
      } },
    })

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
    impl({
      capabilities = { command = true },
      pick_fancy = function(_, opts)
        received = opts
      end,
      pick_naive = function() end,
    })
    Picker.setup()

    Picker.pick_fancy(pick_spec(), {
      on_choices = function() end,
      commands = { command },
    })

    assert.are.same({ command }, received.commands)
    assert.is_nil(received.on_close)
  end)

  it("forwards a fancy pick unchanged and answers nothing of its own", function()
    local received_spec, received_opts
    impl({
      capabilities = { command = false },
      pick_fancy = function(spec, opts)
        received_spec, received_opts = spec, opts
        return "ignored"
      end,
      pick_naive = function() end,
    })
    Picker.setup()

    local spec = pick_spec()
    local on_choices = function() end
    assert.is_nil(Picker.pick_fancy(spec, { on_choices = on_choices }))
    assert.are.equal(spec, received_spec)
    assert.are.equal(on_choices, received_opts.on_choices)
  end)

  it("forwards a plain selection to the implementation", function()
    local received
    impl({
      capabilities = { command = false },
      pick_fancy = function() end,
      pick_naive = function(items, opts, on_choice)
        received = { items = items, opts = opts, on_choice = on_choice }
      end,
    })
    Picker.setup()

    local on_choice = function() end
    Picker.pick_naive({ "a" }, { prompt = "p" }, on_choice)

    assert.are.same({ "a" }, received.items)
    assert.are.equal("p", received.opts.prompt)
    assert.are.equal(on_choice, received.on_choice)
  end)
end)
