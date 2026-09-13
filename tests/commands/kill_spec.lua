---@module 'luassert'

local Helpers = require("helpers")

describe("vantage.commands.kill", function()
  local Kill
  local bridge
  local captured_spec
  local captured_opts

  setup(function()
    Helpers.reload_vantage()
    bridge = { killed_agents = {}, killed_groups = {} }
    function bridge.inventory()
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
      pick = function(spec, opts)
        captured_spec = spec
        captured_opts = opts
        -- Answer the way an implementation does: the opening read carries the
        -- reason when the list could not be read.
        local items, err = spec.items_provider()
        return #items == 0, err
      end,
    }
    Kill = require("vantage.commands.kill")
  end)

  teardown(function()
    Helpers.reload_vantage()
  end)

  it("lists agents in window order then groups in name order, and kills them", function()
    captured_spec = nil
    Kill.run()
    assert.is_not_nil(captured_spec)
    local items = captured_spec.items_provider()

    assert.are.equal(4, #items)
    assert.are.same(
      { "agent", "agent", "group", "group" },
      vim.tbl_map(function(entry)
        return entry.kind
      end, items)
    )
    for _, entry in ipairs(items) do
      captured_opts.on_choice(entry)
    end
    assert.are.same({ "@1", "@4" }, bridge.killed_agents)
    assert.are.same({ "a", "b" }, bridge.killed_groups)
  end)

  it("warns the read's reason instead of the empty list message", function()
    local notified = {}
    local original_notify = vim.notify
    vim.notify = function(msg)
      notified[#notified + 1] = msg
    end
    bridge.inventory = function()
      return nil, "no server running"
    end

    Kill.run()
    vim.notify = original_notify

    assert.are.same({ "vantage: no server running" }, notified)
  end)
end)
