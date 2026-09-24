---@module 'luassert'

local Helpers = require("helpers")

describe("vantage.config", function()
  local Config

  setup(function()
    Helpers.reload_vantage()
    Config = require("vantage.config")
  end)

  teardown(function()
    Helpers.reload_vantage()
  end)

  it("sanitize_tools keeps valid tools and drops invalid ones with reasons", function()
    local tools = {
      good = { cmd = { "codex" } },
      no_cmd = { format = function() end },
      empty_cmd = { cmd = {} },
      missing_cmd = { cmd = { "vantage-no-such-tool-xyz" } },
      not_table = "codex",
    }
    tools[""] = { cmd = { "codex" } }
    local dropped = {}
    Config.sanitize_tools(tools, dropped)

    assert.are.same({ "good" }, vim.tbl_keys(tools))
    assert.are.equal("empty name", dropped[""])
    assert.are.equal("value is not a table", dropped.not_table)
    assert.are.equal("cmd is missing or empty", dropped.no_cmd)
    assert.are.equal("cmd is missing or empty", dropped.empty_cmd)
    assert.are.equal("command 'vantage-no-such-tool-xyz' not found", dropped.missing_cmd)
  end)

  it("apply applies defaults with no options", function()
    local util = require("vantage.util")
    local original_warn = util.warn
    util.warn = function() end
    Config.apply({})
    util.warn = original_warn

    assert.are.equal("tmux", Config.options.backend)
    assert.are.equal("vantage", Config.options.backend_opts.tmux.socket)
    assert.are.equal("native", Config.options.picker)
    local prompt_names = vim.tbl_keys(Config.options.prompts)
    table.sort(prompt_names)
    assert.are.same({ "{file}", "{line}", "{reviews}" }, prompt_names)
    assert.are.same({}, Config.options.cli.tools)
    assert.are.equal("{lines} {note}", Config.options.reviews.item)
  end)

  it("merges user options over defaults and records dropped tools", function()
    local util = require("vantage.util")
    local original_warn = util.warn
    util.warn = function() end
    Config.apply({
      picker = "snacks",
      backend_opts = { tmux = { socket = "custom" } },
      prompts = { review = "Review {file}" },
      reviews = { item = "{lines} {note} custom" },
      cli = {
        tools = {
          good = { cmd = { "codex" } },
          bad = { cmd = {} },
        },
      },
    })
    util.warn = original_warn

    assert.are.equal("snacks", Config.options.picker)
    assert.are.equal("custom", Config.options.backend_opts.tmux.socket)
    assert.are.equal("Review {file}", Config.options.prompts.review)
    assert.are.equal("{file}", Config.options.prompts["{file}"])
    assert.are.same({ "good" }, vim.tbl_keys(Config.options.cli.tools))
    assert.are.equal("cmd is missing or empty", Config.dropped_tools.bad)
    assert.are.equal("{lines} {note} custom", Config.options.reviews.item)
    assert.are.equal("float", Config.options.cli.win.layout)
  end)

  it("apply gives every surviving tool a reference spelling", function()
    local util = require("vantage.util")
    local original_warn = util.warn
    util.warn = function() end
    local custom = function(file)
      return "@" .. file
    end
    Config.apply({
      cli = {
        tools = {
          plain = { cmd = { "codex" } },
          dialect = { cmd = { "codex" }, format = custom },
        },
      },
    })
    util.warn = original_warn

    assert.are.equal(custom, Config.options.cli.tools.dialect.format)
    assert.are.equal("function", type(Config.options.cli.tools.plain.format))
    assert.are.equal("@src/a.lua", Config.tool_reference("dialect", "/proj", "/proj/src/a.lua"))
  end)

  it("tool_reference spells a location through the Tool and falls back for an unknown Tool", function()
    local util = require("vantage.util")
    local original_warn = util.warn
    util.warn = function() end
    local custom = function(file, loc)
      return "@" .. file .. (loc and (" " .. loc) or "")
    end
    Config.apply({
      cli = {
        tools = {
          dialect = { cmd = { "codex" }, format = custom },
          plain = { cmd = { "codex" } },
        },
      },
    })
    util.warn = original_warn

    assert.are.equal("@src/a.lua :L4", Config.tool_reference("dialect", "/proj", "/proj/src/a.lua", 4))
    assert.are.equal("src/a.lua :L4", Config.tool_reference("plain", "/proj", "/proj/src/a.lua", 4))
    assert.are.equal("src/a.lua :L4", Config.tool_reference("dropped-later", "/proj", "/proj/src/a.lua", 4))
    assert.are.equal("src/a.lua", Config.tool_reference(nil, "/proj", "/proj/src/a.lua"))
  end)

  it("tool_reference spells whole files, single lines, and ranges", function()
    assert.are.equal("src/a.lua", Config.tool_reference(nil, "/proj", "/proj/src/a.lua"))
    assert.are.equal("src/a.lua :L4", Config.tool_reference(nil, "/proj", "/proj/src/a.lua", 4))
    assert.are.equal("src/a.lua :L4", Config.tool_reference(nil, "/proj", "/proj/src/a.lua", 4, 4))
    assert.are.equal("src/a.lua :L2-4", Config.tool_reference(nil, "/proj", "/proj/src/a.lua", 2, 4))
    assert.are.equal("/elsewhere/a.lua", Config.tool_reference(nil, "/proj", "/elsewhere/a.lua"))
  end)

  it("tool_reference has no reference without a path or when the hook declines", function()
    Config.options.cli.tools = {
      silent = { cmd = { "codex" }, format = function() end },
      blank = {
        cmd = { "codex" },
        format = function()
          return ""
        end,
      },
    }

    assert.are.equal(nil, Config.tool_reference(nil, "/proj", ""))
    assert.are.equal(nil, Config.tool_reference("silent", "/proj", "/proj/src/a.lua"))
    assert.are.equal(nil, Config.tool_reference("blank", "/proj", "/proj/src/a.lua"))
  end)
end)
