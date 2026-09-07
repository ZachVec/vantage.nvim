---@module 'luassert'

local Helpers = require("helpers")

describe("vantage.select", function()
  local Annotation
  local Config
  local Select
  local backend
  local focused
  local agent_fixture
  local bufs = {}

  --- Hand an Agent row its flow-injected `after` and capture what it receives.
  --- Returns the Agent for non-focused rows; nil for focused rows (whose
  --- `activate` no-ops).
  local function agent_of(item)
    local agent
    item:activate(function(a)
      agent = a
    end)
    return agent
  end

  --- Ordered targets of the non-focused Agent rows (Tool rows and the pinned
  --- focused row are skipped).
  local function agent_targets(items)
    local out = {}
    for _, item in ipairs(items) do
      if item:group() ~= nil then
        local agent = agent_of(item)
        if agent then
          out[#out + 1] = agent.target
        end
      end
    end
    return out
  end

  --- Ordered Group names of the Agent rows (Tool rows are skipped).
  local function agent_groups(items)
    local out = {}
    for _, item in ipairs(items) do
      local group = item:group()
      if group ~= nil then
        out[#out + 1] = group
      end
    end
    return out
  end

  --- Ordered names of the Tool rows.
  local function tool_names(items)
    local out = {}
    for _, item in ipairs(items) do
      if item:group() == nil then
        out[#out + 1] = item:format():match("%S+$")
      end
    end
    return out
  end

  local function find_agent_entry(items, target)
    for _, item in ipairs(items) do
      if item:group() ~= nil then
        local agent = agent_of(item)
        if agent and agent.target == target then
          return item
        end
      end
    end
    error("agent entry not found: " .. target)
  end

  local function find_tool_entry(items, name)
    for _, item in ipairs(items) do
      if item:group() == nil and item:format():find(name, 1, true) then
        return item
      end
    end
    error("tool entry not found: " .. name)
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
    Annotation = require("vantage.annotation")
    Annotation.setup()
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
    function backend.snapshot(view)
      return {
        agents = backend.agents,
        groups = backend.groups_values or backend.groups,
        focused = view ~= nil and focused or nil,
      }
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
      view = "test-view",
    }
    Select = require("vantage.select")
  end)

  teardown(function()
    Helpers.reload_vantage()
  end)

  after_each(function()
    Annotation.clear()
    for _, buf in ipairs(bufs) do
      Helpers.wipe(buf)
    end
    bufs = {}
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
    local items = Select.agent_spec(false).items_provider()

    assert.are.same({ "@1", "@3", "@2", "@4" }, agent_targets(items))
    assert.are.same({ "alpha", "zeta" }, tool_names(items))
  end)

  it("pins the focused agent first and excludes it from the sorted rows", function()
    focus_target("@2")
    local items = Select.agent_spec(true).items_provider()

    assert.are.equal("a", items[1]:group())
    assert.is_true(vim.endswith(items[1]:format(), "(focused)"))
    assert.are.same({ "@1", "@3", "@4" }, agent_targets(items))
  end)

  it("formats rows with tool, group, and cwd", function()
    focused = nil
    local item = Select.agent_spec(false).items_provider()[1]
    assert.are.equal("zeta · a · /a", item:format():gsub("^.*  ", ""))
  end)

  it("filters the agent list to the focused agent's group, keeping tool rows", function()
    focus_target("@2")
    local spec = Select.agent_spec(true)
    local grouped = spec.group(spec.items_provider())

    assert.are.same({ "a", "a", "a" }, agent_groups(grouped))
    assert.are.equal(2, #grouped - #agent_groups(grouped))

    focused = nil
    local ungrouped = spec.group(spec.items_provider())
    assert.are.same({ "a", "a", "a", "z" }, agent_groups(ungrouped))
  end)

  it("delete removes non-focused agents only", function()
    focus_target("@2")
    local items = Select.agent_spec(true).items_provider()

    assert.is_false(items[1]:delete())
    assert.is_true(find_agent_entry(items, "@4"):delete())
    assert.is_false(find_tool_entry(items, "alpha"):delete())

    assert.are.same({ "@4" }, backend.killed)
  end)

  it("activate hands the domain object to the flow, no-op for focused", function()
    focus_target("@2")
    local items = Select.agent_spec(true).items_provider()

    local calls = {}
    items[1]:activate(function(agent)
      calls[#calls + 1] = agent.target
    end)
    assert.are.same({}, calls)

    find_agent_entry(items, "@4"):activate(function(agent)
      calls[#calls + 1] = agent.target
    end)
    assert.are.same({ "@4" }, calls)
  end)

  it("group accessor returns the agent's group and nil for tools", function()
    focused = nil
    local items = Select.agent_spec(false).items_provider()

    assert.are.equal("a", find_agent_entry(items, "@1"):group())
    assert.are.equal(nil, find_tool_entry(items, "alpha"):group())
  end)

  it("previews an agent pane and returns nil for tool rows", function()
    focused = nil
    local items = Select.agent_spec(false).items_provider()

    assert.are.same({ "line" }, find_agent_entry(items, "@4"):preview())
    assert.are.equal(nil, find_tool_entry(items, "alpha"):preview())
    assert.are.same({ "@4" }, backend.captured)
  end)

  it("builds annotation entries with format, preview, activate, and delete", function()
    local buf = Helpers.buffer({ "a", "b" }, "/tmp/ann/select.lua")
    bufs[#bufs + 1] = buf
    local annotation = Annotation.add(buf, 1, 1, "todo")

    local item = Select.annotation_spec(false).items_provider()[1]
    local received
    item:activate(function(a)
      received = a
    end)
    assert.are.equal(annotation.id, received.id)
    assert.is_true(item:format():find("/tmp/ann/select.lua:L1-1", 1, true) ~= nil)
    assert.is_true(#item:preview() > 0)
    assert.are.equal(true, item:delete())
    assert.are.equal(0, #Annotation.collect())
  end)

  it("builds kill rows as agents then groups", function()
    focused = nil
    backend.groups_values = { "g-a", "g-b" }
    local items = Select.kill_spec(false).items_provider()

    backend.killed = {}
    for _, item in ipairs(items) do
      item:delete()
    end
    assert.are.same({ "@4", "@2", "@3", "@1", "g-a", "g-b" }, backend.killed)
  end)
end)
