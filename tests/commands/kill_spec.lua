---@module 'luassert'

local Helpers = require("helpers")

describe("vantage.commands.kill", function()
  local Kill
  local backend
  local captured_spec
  local captured_opts

  setup(function()
    Helpers.reload_vantage()
    backend = { killed_agents = {} }
    function backend.inventory()
      return {
        agents = {
          { group = "a", id = "@1", seq = 1, tool = "codex", cwd = "/a" },
          { group = "b", id = "@4", seq = 4, tool = "codex", cwd = "/b" },
        },
        groups = { "b", "a" },
      },
        nil
    end
    function backend.kill_agent(agent)
      backend.killed_agents[#backend.killed_agents + 1] = agent.id
      return true, nil
    end
    package.loaded["vantage.backend"] = backend
    package.loaded["vantage.frontend.picker"] = {
      pick_fancy = function(spec, opts)
        captured_spec, captured_opts = spec, opts
      end,
    }
    Kill = require("vantage.commands.kill")
  end)

  teardown(function()
    Helpers.reload_vantage()
  end)

  it("lists every Agent in creation order and kills the chosen ones", function()
    captured_spec = nil
    Kill.run()
    assert.is_not_nil(captured_spec)
    local items = Helpers.entries(captured_spec)

    assert.are.equal(2, #items)
    assert.are.same(
      { "agent", "agent" },
      vim.tbl_map(function(entry)
        return entry.kind
      end, items)
    )
    assert.are.same(
      { "@1", "@4" },
      vim.tbl_map(function(entry)
        return entry.agent.id
      end, items)
    )
    captured_opts.on_choices(items)
    assert.are.same({ "@1", "@4" }, backend.killed_agents)
  end)

  it("warns the read's reason from its own source", function()
    local notified = {}
    local original_notify = vim.notify
    vim.notify = function(msg)
      notified[#notified + 1] = msg
    end
    backend.inventory = function()
      return nil, "no server running"
    end

    Kill.run()
    local items = Helpers.entries(captured_spec)
    vim.notify = original_notify

    assert.are.same({}, items)
    assert.are.same({ "vantage: no server running" }, notified)
  end)
end)
