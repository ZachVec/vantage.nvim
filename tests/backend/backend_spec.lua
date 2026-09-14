---@module 'luassert'

local Helpers = require("helpers")

describe("vantage.backend", function()
  local Backend
  local Config
  local driver

  setup(function()
    Helpers.reload_vantage()
    Config = require("vantage.config")
    Config.options.cli.tools = {
      good = { cmd = { "sh" } },
    }
    driver = { created = {}, agent_list = {} }
    function driver.create(opts)
      driver.created[#driver.created + 1] = opts
      return { group = opts.group, tool = opts.tool, id = "@9" }
    end
    function driver.agents()
      return driver.agent_list, driver.agents_err
    end
    function driver.focus(pid)
      driver.focused_pid = pid
      -- A failure pre-empts the answer, like the tmux Driver's exec error path.
      if driver.focus_err then
        return nil, driver.focus_err
      end
      return driver.focused, driver.focus_reason
    end
    package.loaded["vantage.backend.driver"] = {
      get = function()
        return driver
      end,
    }
    Backend = require("vantage.backend")
  end)

  teardown(function()
    Helpers.reload_vantage()
  end)

  before_each(function()
    driver.created = {}
    driver.agent_list = {}
    driver.agents_err = nil
    driver.focused = nil
    driver.focus_reason = nil
    driver.focus_err = nil
    driver.focused_pid = nil
  end)

  it("creates through the driver with the resolved command", function()
    local agent, err = Backend.create({ group = "g", tool = "good", cwd = "/tmp" })
    assert.are.equal(nil, err)
    assert.are.equal("@9", agent.id)
    assert.are.equal("'sh'", driver.created[1].cmd)
  end)

  it("returns an error for an unknown tool", function()
    local agent, err = Backend.create({ group = "g", tool = "missing", cwd = "/tmp" })
    assert.are.equal(nil, agent)
    assert.are.equal("unknown tool 'missing'", err)
  end)

  it("derives groups once each, in the agents' order", function()
    driver.agent_list = {
      { id = "@1", group = "z" },
      { id = "@2", group = "a" },
      { id = "@3", group = "z" },
    }
    local inventory, err = Backend.inventory()
    assert.are.equal(nil, err)
    assert.are.same({ "z", "a" }, inventory.groups)
    assert.are.equal(3, #inventory.agents)
  end)

  it("reports no terminal as the reason when there is no pid", function()
    local agent, reason = Backend.focus(nil)
    assert.are.equal(nil, agent)
    assert.are.equal(Config.FOCUS_NO_TERMINAL, reason)
    -- "No Terminal" is the Frontend's own fact, so the Driver is not consulted.
    assert.are.equal(nil, driver.focused_pid)
  end)

  it("hands the pid to the Driver and returns the Focus it answers", function()
    driver.focused = { id = "@7", group = "g", tool = "good" }
    local agent, reason = Backend.focus(42)
    assert.are.equal(42, driver.focused_pid)
    assert.are.equal("@7", agent.id)
    assert.are.equal(nil, reason)
  end)

  it("passes the Driver's no-client reason through", function()
    driver.focus_reason = Config.FOCUS_NO_CLIENT
    local agent, reason = Backend.focus(42)
    assert.are.equal(nil, agent)
    assert.are.equal(Config.FOCUS_NO_CLIENT, reason)
  end)

  it("passes the Driver's no-focused-agent reason through", function()
    driver.focus_reason = Config.FOCUS_NO_FOCUS
    local agent, reason = Backend.focus(42)
    assert.are.equal(nil, agent)
    assert.are.equal(Config.FOCUS_NO_FOCUS, reason)
  end)

  it("passes a failed Focus read through with the Driver's own reason", function()
    driver.focus_err = "no server running on /tmp/vantage"
    local agent, reason = Backend.focus(42)
    assert.are.equal(nil, agent)
    assert.is_true(reason:find("no server running", 1, true) ~= nil)
  end)
end)
