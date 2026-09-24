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
      if driver.agents_err then
        return nil, driver.agents_err
      end
      return driver.agent_list, nil
    end
    -- The facade resolves the configured Driver through its whitelist, so the
    -- fake stands in for the tmux module and must satisfy the whole contract.
    function driver.attach(agent, launch)
      driver.attached = { agent = agent, launch = launch }
      return driver.attachment, driver.attach_err
    end
    function driver.kill_agent() end
    function driver.kill_group() end
    function driver.send_keys() end
    function driver.capture_pane() end
    function driver.status() end
    function driver.health() end
    package.loaded["vantage.backend.tmux"] = driver
    Backend = require("vantage.backend")
    Backend.setup()
  end)

  teardown(function()
    Helpers.reload_vantage()
  end)

  before_each(function()
    driver.created = {}
    driver.agent_list = {}
    driver.agents_err = nil
    driver.attached = nil
    driver.attachment = nil
    driver.attach_err = nil
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

  it("passes a failed inventory read's reason through", function()
    driver.agents_err = "no server running"
    local inventory, err = Backend.inventory()
    assert.are.equal(nil, inventory)
    assert.are.equal("no server running", err)
  end)

  it("hands the launch callback to the Driver and returns its Attachment", function()
    local launch = function() end
    driver.attachment = { focus = function() end, retarget = function() end }
    local agent = { id = "@1", group = "g" }

    local attachment, err = Backend.attach(agent, launch)
    assert.are.equal(nil, err)
    assert.are.equal(driver.attachment, attachment)
    assert.are.equal(agent, driver.attached.agent)
    assert.are.equal(launch, driver.attached.launch)
  end)
end)
