---@module 'luassert'

local Helpers = require("helpers")

describe("vantage.select", function()
  local Config
  local Select
  local backend
  local focused
  local agent_fixture

  local function targets(items)
    return vim.tbl_map(
      function(item)
        return item.agent.target
      end,
      vim.tbl_filter(function(item)
        return item.kind == "agent"
      end, items)
    )
  end

  local function focus_target(target)
    for _, agent in ipairs(backend.agents) do
      if agent.target == target then
        focused = agent
        return
      end
    end
    error("fixture agent not found: " .. target)
  end

  setup(function()
    Helpers.reload_vantage()
    Config = require("vantage.config")
    Config.options.cli.tools = {
      zeta = { cmd = { "zeta" } },
      alpha = { cmd = { "alpha" } },
    }

    agent_fixture = {
      { group = "z", cwd = "/z", tool = "codex", target = "@4", cmd = "codex" },
      { group = "a", cwd = "/b", tool = "codex", target = "@2", cmd = "codex" },
      { group = "a", cwd = "/a", tool = "zeta", target = "@3", cmd = "zeta" },
      { group = "a", cwd = "/a", tool = "zeta", target = "@1", cmd = "zeta" },
    }
    backend = {
      agents = vim.deepcopy(agent_fixture),
      groups = { "g-a", "g-b" },
      killed = {},
      captured = {},
    }
    function backend.list()
      return backend.agents
    end
    function backend.groups()
      return backend.groups_values or backend.groups
    end
    function backend.capture_pane(target)
      backend.captured[#backend.captured + 1] = target
      return { "line" }
    end
    function backend.kill(target)
      backend.killed[#backend.killed + 1] = target
    end

    package.loaded["vantage.backend"] = {
      get = function()
        return backend
      end,
    }
    package.loaded["vantage.client"] = {
      last_agent_alive = function()
        return focused
      end,
    }
    Select = require("vantage.select")
  end)

  teardown(function()
    Helpers.reload_vantage()
  end)

  before_each(function()
    focused = nil
    backend.agents = vim.deepcopy(agent_fixture)
    backend.killed = {}
    backend.captured = {}
    backend.groups_values = nil
  end)

  it("orders agent rows by group, cwd, tool, then window id", function()
    focused = nil
    local spec = Select.agent_spec(false)
    local items = spec.items_provider()

    assert.are.same({ "@1", "@3", "@2", "@4" }, targets(items))
    assert.are.same(
      { "alpha", "zeta" },
      vim.tbl_map(
        function(item)
          return item.tool
        end,
        vim.tbl_filter(function(item)
          return item.kind == "tool"
        end, items)
      )
    )
  end)

  it("pins the focused agent first and excludes it from the sorted rows", function()
    focus_target("@2")
    local spec = Select.agent_spec(true)
    local items = spec.items_provider()

    assert.are.equal(true, items[1].focused)
    assert.are.equal("@2", items[1].agent.target)
    assert.is_true(vim.endswith(items[1].text, "(focused)"))
    local unpinned = vim.tbl_filter(function(item)
      return not item.focused
    end, items)
    assert.are.same({ "@1", "@3", "@4" }, targets(unpinned))
  end)

  it("formats rows with tool, group, and cwd", function()
    focused = nil
    local item = Select.agent_spec(false).items_provider()[1]
    assert.are.equal("zeta · a · /a", item.text:gsub("^.*  ", ""))
  end)

  it("scopes the agent list to the focused agent's group, keeping tool rows", function()
    focus_target("@2")
    local spec = Select.agent_spec(true)
    local scoped = spec.scope(spec.items_provider())

    assert.are.same({ "@2", "@1", "@3" }, targets(scoped))
    assert.are.equal(2, #vim.tbl_filter(function(item)
      return item.kind == "tool"
    end, scoped))

    focused = nil
    local unscoped = spec.scope(spec.items_provider())
    assert.are.same(4, #targets(unscoped))
  end)

  it("kill on_delete ignores focused rows and tool rows and kills agents", function()
    focus_target("@2")
    local spec = Select.agent_spec(true)
    spec.on_delete({ kind = "agent", agent = backend.agents[1], focused = false })
    spec.on_delete({ kind = "agent", agent = backend.agents[2], focused = true })
    spec.on_delete({ kind = "tool", tool = "alpha" })

    assert.are.same({ "@4" }, backend.killed)
  end)

  it("previews an agent pane and returns nil for tool rows", function()
    focused = nil
    local spec = Select.agent_spec(false)
    assert.are.same({ "line" }, spec.preview({ agent = backend.agents[1] }))
    assert.are.equal(nil, spec.preview({ kind = "tool" }))
    assert.are.same({ "@4" }, backend.captured)
  end)

  it("builds kill rows as agents then groups", function()
    focused = nil
    backend.groups_values = { "g-a", "g-b" }
    local items = Select.kill_spec(false).items_provider()
    assert.are.same(
      { "@4", "@2", "@3", "@1", "g-a", "g-b" },
      vim.tbl_map(function(item)
        return item.target
      end, items)
    )
  end)
end)
