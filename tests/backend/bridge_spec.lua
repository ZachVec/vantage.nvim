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
    driver = { created = {} }
    function driver.create(opts)
      driver.created[#driver.created + 1] = opts
      return { group = opts.group, tool = opts.tool, id = "@9" }
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
end)
