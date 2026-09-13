---@module 'luassert'

local Helpers = require("helpers")

describe("vantage.backend.bridge", function()
  local Bridge
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
    function driver.client_window(pid)
      -- A failure pre-empts the answer, like the tmux Driver's exec error path.
      if driver.window_err then
        return nil, driver.window_err
      end
      return driver.windows[pid], nil
    end
    package.loaded["vantage.backend.driver"] = {
      get = function()
        return driver
      end,
    }
    Bridge = require("vantage.backend.bridge")
  end)

  teardown(function()
    Helpers.reload_vantage()
  end)

  before_each(function()
    driver.created = {}
    driver.agent_list = {}
    driver.agents_err = nil
    driver.windows = {}
    driver.window_err = nil
  end)

  it("creates through the driver with the resolved command", function()
    local agent, err = Bridge.create({ group = "g", tool = "good", cwd = "/tmp" })
    assert.are.equal(nil, err)
    assert.are.equal("@9", agent.id)
    assert.are.equal("'sh'", driver.created[1].cmd)
  end)

  it("returns an error for an unknown tool", function()
    local agent, err = Bridge.create({ group = "g", tool = "missing", cwd = "/tmp" })
    assert.are.equal(nil, agent)
    assert.are.equal("unknown tool 'missing'", err)
  end)

  it("derives groups once each, in the agents' order", function()
    driver.agent_list = {
      { id = "@1", group = "z" },
      { id = "@2", group = "a" },
      { id = "@3", group = "z" },
    }
    local inventory, err = Bridge.inventory()
    assert.are.equal(nil, err)
    assert.are.same({ "z", "a" }, inventory.groups)
    assert.are.equal(3, #inventory.agents)
  end)

  it("reports no terminal as the reason when there is no pid", function()
    local agent, reason = Bridge.focus(nil)
    assert.are.equal(nil, agent)
    assert.are.equal(Config.FOCUS_NO_TERMINAL, reason)
  end)

  it("reports a client that is not on an agent window", function()
    driver.windows = { [42] = "@7" }
    driver.agent_list = { { id = "@1", group = "g" } }
    local agent, reason = Bridge.focus(42)
    assert.are.equal(nil, agent)
    assert.are.equal(Config.FOCUS_NO_FOCUS, reason)
  end)

  it("reports a pid the multiplexer has no client for", function()
    local agent, reason = Bridge.focus(42)
    assert.are.equal(nil, agent)
    assert.are.equal(Config.FOCUS_NO_CLIENT, reason)
  end)

  it("answers the display read from the client's window", function()
    driver.windows = { [42] = "@7" }
    driver.agent_list = { { id = "@7", group = "g", tool = "good" } }
    local agent, reason = Bridge.focus(42)
    assert.are.equal("@7", agent.id)
    assert.are.equal(nil, reason)
  end)

  it("passes the client's window read through", function()
    driver.windows = { [42] = "@7" }
    local window, err = Bridge.client_window(42)
    assert.are.equal("@7", window)
    assert.are.equal(nil, err)

    driver.window_err = "boom"
    local none, reason = Bridge.client_window(42)
    assert.are.equal(nil, none)
    assert.are.equal("boom", reason)
  end)

  it("passes a failed display read through with its own reason", function()
    driver.window_err = "no server running on /tmp/vantage"
    local agent, reason = Bridge.focus(42)
    assert.are.equal(nil, agent)
    assert.is_true(reason:find("no server running", 1, true) ~= nil)
  end)
end)
