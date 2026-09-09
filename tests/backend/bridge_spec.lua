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
      return { group = opts.group, tool = opts.tool, target = "@9" }
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
    local agent = Bridge.create({ group = "g", tool = "good", cwd = "/tmp" })
    assert.are.equal("@9", agent.target)
    assert.are.equal("'sh'", driver.created[1].cmd)
  end)
end)
