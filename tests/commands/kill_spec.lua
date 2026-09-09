---@module 'luassert'

local Helpers = require("helpers")

describe("vantage.commands.kill", function()
  local Kill
  local bridge

  setup(function()
    Helpers.reload_vantage()
    bridge = { killed_agents = {}, killed_groups = {} }
    function bridge.agents()
      return {
        agents = {
          { group = "a", target = "@1", tool = "codex", cwd = "/a" },
          { group = "b", target = "@4", tool = "codex", cwd = "/b" },
        },
        groups = { "a", "b" },
      }
    end
    function bridge.kill_agent(agent)
      bridge.killed_agents[#bridge.killed_agents + 1] = agent.target
    end
    function bridge.kill_group(group)
      bridge.killed_groups[#bridge.killed_groups + 1] = group
    end

    package.loaded["vantage.backend.bridge"] = bridge
    Kill = require("vantage.commands.kill")
  end)

  teardown(function()
    Helpers.reload_vantage()
  end)

  it("lists agents in window order then groups in name order, and deletes them", function()
    local items = Kill.spec().items_provider()

    assert.are.equal(4, #items)
    for _, item in ipairs(items) do
      assert.are.equal(true, item:delete())
    end
    assert.are.same({ "@1", "@4" }, bridge.killed_agents)
    assert.are.same({ "a", "b" }, bridge.killed_groups)
  end)
end)
