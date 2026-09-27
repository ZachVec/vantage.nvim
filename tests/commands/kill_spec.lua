---@module 'luassert'

local Helpers = require("helpers")

describe("vantage.commands.kill", function()
  local Kill
  local backend
  local captured_spec
  local captured_opts

  setup(function()
    Helpers.reload_vantage()
    backend = { killed_agents = {}, killed_groups = {} }
    function backend.inventory()
      return {
        agents = {
          { group = "a", id = "@1", seq = 1, tool = "codex", cwd = "/a" },
          { group = "b", id = "@4", seq = 4, tool = "codex", cwd = "/b" },
        },
        -- Deliberately not the Agents' order: the kill list sorts names.
        groups = { "b", "a" },
      },
        nil
    end
    function backend.kill_agent(agent)
      backend.killed_agents[#backend.killed_agents + 1] = agent.id
      return true, nil
    end
    function backend.kill_group(group)
      backend.killed_groups[#backend.killed_groups + 1] = group
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

  it("lists agents in window order then groups in name order, and kills them", function()
    captured_spec = nil
    Kill.run()
    assert.is_not_nil(captured_spec)
    local items = Helpers.entries(captured_spec)

    assert.are.equal(4, #items)
    assert.are.same(
      { "agent", "agent", "group", "group" },
      vim.tbl_map(function(entry)
        return entry.kind
      end, items)
    )
    assert.are.same(
      { "a", "b" },
      vim.tbl_map(function(entry)
        return entry.group
      end, { items[3], items[4] })
    )
    captured_opts.on_choices(items)
    assert.are.same({ "@1", "@4" }, backend.killed_agents)
    assert.are.same({ "a", "b" }, backend.killed_groups)
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
