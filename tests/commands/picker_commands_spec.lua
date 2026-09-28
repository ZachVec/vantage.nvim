---@module 'luassert'

local Helpers = require("helpers")

--- The picker-command contract lives here, not in the facade: the Picker
--- passes a flow's commands to its renderer verbatim, and a renderer binds
--- them by `lhs`, so a collision silently shadows one of them. Drive every
--- command-bearing flow and assert the descriptors are well-formed and unique.
describe("vantage flow picker commands", function()
  local captured

  --- Run `flow` with the Picker stubbed to capture one pick's opts.
  ---@param flow fun()
  ---@return vantage.PickerCommand[]
  local function commands_of(flow)
    captured = nil
    flow()
    assert.is_not_nil(captured)
    local commands = captured.commands
    assert.is_not_nil(commands)
    assert.is_true(#commands > 0)
    return commands
  end

  ---@param commands vantage.PickerCommand[]
  local function assert_well_formed(commands)
    local seen = {}
    for _, command in ipairs(commands) do
      assert.are.equal("string", type(command[1]))
      assert.is_true(#command[1] > 0)
      assert.are.equal("function", type(command[2]))
      assert.is_nil(seen[command[1]], ("duplicate picker command lhs '%s'"):format(command[1]))
      seen[command[1]] = true
    end
  end

  setup(function()
    Helpers.reload_vantage()
    require("vantage.config").options.cli.tools = {}
    package.loaded["vantage.backend"] = {
      inventory = function()
        return { agents = {}, groups = {} }, nil
      end,
    }
    package.loaded["vantage.frontend.terminal"] = {
      show = function()
        return false
      end,
      attachment = nil,
    }
    package.loaded["vantage.frontend.picker"] = {
      pick_fancy = function(_, opts)
        captured = opts
      end,
      pick_naive = function() end,
    }
  end)

  teardown(function()
    Helpers.reload_vantage()
  end)

  it("attach's show and switch picks", function()
    local Attach = require("vantage.commands.attach")
    assert_well_formed(commands_of(Attach.show))

    package.loaded["vantage.frontend.terminal"].attachment = {}
    assert_well_formed(commands_of(Attach.switch))
  end)

  it("the review list pick", function()
    local ReviewCmd = require("vantage.commands.review")
    assert_well_formed(commands_of(function()
      ReviewCmd.run("list", 1, 1)
    end))
  end)
end)
