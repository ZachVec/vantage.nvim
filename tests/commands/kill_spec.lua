---@module 'luassert'

local Helpers = require("helpers")

describe("vantage.commands.kill", function()
  local Kill
  local bridge
  local captured_spec

  setup(function()
    Helpers.reload_vantage()
    bridge = { killed_agents = {}, killed_groups = {} }
    function bridge.agents()
      return {
        agents = {
          { group = "a", id = "@1", seq = 1, tool = "codex", cwd = "/a" },
          { group = "b", id = "@4", seq = 4, tool = "codex", cwd = "/b" },
        },
        groups = { "a", "b" },
      },
        nil
    end
    function bridge.kill_agent(agent)
      bridge.killed_agents[#bridge.killed_agents + 1] = agent.id
      return true, nil
    end
    function bridge.kill_group(group)
      bridge.killed_groups[#bridge.killed_groups + 1] = group
      return true, nil
    end

    package.loaded["vantage.backend.bridge"] = bridge
    package.loaded["vantage.frontend.picker"] = {
      pick = function(spec)
        captured_spec = spec
        return false
      end,
    }
    Kill = require("vantage.commands.kill")
  end)

  teardown(function()
    Helpers.reload_vantage()
  end)

  it("lists agents in window order then groups in name order, and deletes them", function()
    captured_spec = nil
    Kill.run()
    assert.is_not_nil(captured_spec)
    local items = captured_spec.items_provider()

    assert.are.equal(4, #items)
    for _, item in ipairs(items) do
      assert.are.equal(true, item:delete())
    end
    assert.are.same({ "@1", "@4" }, bridge.killed_agents)
    assert.are.same({ "a", "b" }, bridge.killed_groups)
  end)
end)
