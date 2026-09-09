---@module 'luassert'

local Helpers = require("helpers")

describe("vantage.commands.switch", function()
  local Config
  local Switch
  local bridge
  local focused
  local agent_fixture
  local picker

  --- Capture what a row hands to its target continuation.
  ---@param item vantage.SwitchEntry
  ---@return vantage.Agent?
  local function resolved(item)
    local agent
    item:target(function(a)
      agent = a
    end)
    return agent
  end

  local function agent_rows(items)
    local out = {}
    for _, item in ipairs(items) do
      if item.group ~= nil then
        out[#out + 1] = item
      end
    end
    return out
  end

  local function tool_names(items)
    local out = {}
    for _, item in ipairs(items) do
      if item.group == nil then
        out[#out + 1] = item:format():match("%S+$")
      end
    end
    return out
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
    bridge = { created = {}, captured = {} }
    function bridge.agents(pid)
      return {
        agents = vim.deepcopy(agent_fixture),
        groups = { "a", "z" },
        focused = (pid ~= nil and focused) or nil,
      }
    end
    function bridge.capture(agent)
      bridge.captured[#bridge.captured + 1] = agent.target
      return { "line" }
    end
    function bridge.create(opts)
      bridge.created[#bridge.created + 1] = opts
      return { group = opts.group, tool = opts.tool, target = "@9" }
    end

    picker = {
      pick_plain = function(_, _, on_choice)
        on_choice("z")
      end,
    }
    package.loaded["vantage.backend.bridge"] = bridge
    package.loaded["vantage.frontend.picker"] = {
      get = function()
        return picker
      end,
    }
    package.loaded["vantage.frontend.terminal"] = {
      pid = function()
        return nil
      end,
    }
    Switch = require("vantage.commands.switch")
  end)

  teardown(function()
    Helpers.reload_vantage()
  end)

  before_each(function()
    focused = nil
    bridge.created = {}
    bridge.captured = {}
  end)

  it("orders agent rows by group, cwd, tool, then window id, and tools by name", function()
    local items = Switch.spec(nil).items_provider()
    local rows = agent_rows(items)

    assert.are.same(
      { "@1", "@3", "@2", "@4" },
      vim.tbl_map(function(r)
        return resolved(r).target
      end, rows)
    )
    assert.are.same({ "alpha", "zeta" }, tool_names(items))
  end)

  it("pins the focused agent first, excluded from the sorted rows, and its resolve no-ops", function()
    focused = agent_fixture[2]
    local items = Switch.spec(42).items_provider()

    assert.is_true(vim.endswith(items[1]:format(), "(focused)"))
    assert.are.equal(nil, resolved(items[1]))
    local rest = {}
    for i = 2, #items do
      if items[i].group ~= nil then
        rest[#rest + 1] = items[i]
      end
    end
    assert.are.same(
      { "@1", "@3", "@4" },
      vim.tbl_map(function(r)
        return resolved(r).target
      end, rest)
    )
  end)

  it("scopes the list to the focused agent's group, keeping tool rows", function()
    focused = agent_fixture[2]
    local spec = Switch.spec(42)
    local grouped = spec.group(spec.items_provider())

    assert.are.equal(5, #grouped) -- pinned + 2 group-mates + 2 tools
    assert.are.equal(3, #agent_rows(grouped))
  end)

  it("formats rows with tool, group, and cwd", function()
    local item = Switch.spec(nil).items_provider()[1]
    assert.are.equal("zeta · a · /a", item:format():gsub("^.*  ", ""))
  end)

  it("previews agent panes and returns nil for tool rows", function()
    local items = Switch.spec(nil).items_provider()
    local rows = agent_rows(items)

    assert.are.same({ "line" }, rows[1]:preview())
    assert.are.equal(nil, items[#items]:preview())
    assert.are.same({ "@1" }, bridge.captured)
  end)

  it("tool rows ask for a group and create the agent there", function()
    local items = Switch.spec(42).items_provider()
    local tool = items[#items]
    assert.are.equal("z", resolved(tool).group)
    assert.are.equal("z", bridge.created[1].group)
  end)
end)
