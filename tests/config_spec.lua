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

  describe("sanitize_tools", function()
    it("keeps valid tools and drops invalid ones with reasons", function()
      local tools = {
        good = { cmd = { "codex" } },
        ["empty-name"] = {},
        no_cmd = { format = function() end },
        empty_cmd = { cmd = {} },
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
    end)

    it("works without a dropped table", function()
      local tools = { bad = { cmd = {} }, good = { cmd = { "x" } } }
      Config.sanitize_tools(tools)
      assert.are.same({ "good" }, vim.tbl_keys(tools))
    end)
  end)

  describe("setup", function()
    it("applies defaults with no options", function()
      local util = require("vantage.util")
      local original_warn = util.warn
      util.warn = function() end
      Config.setup({})
      util.warn = original_warn

      assert.are.equal("tmux", Config.options.backend)
      assert.are.equal("vantage", Config.options.socket)
      assert.are.equal("native", Config.options.picker)
      local prompt_names = vim.tbl_keys(Config.options.prompts)
      table.sort(prompt_names)
      assert.are.same({ "{annotations}", "{file}", "{line}" }, prompt_names)
      assert.are.same({}, Config.options.cli.tools)
    end)

    it("merges user options over defaults and records dropped tools", function()
      local util = require("vantage.util")
      local original_warn = util.warn
      util.warn = function() end
      Config.setup({
        picker = "snacks",
        socket = "custom",
        prompts = { review = "Review {file}" },
        annotations = { item = "{lines} {note} custom" },
        cli = {
          tools = {
            good = { cmd = { "codex" } },
            bad = { cmd = {} },
          },
        },
      })
      util.warn = original_warn

      assert.are.equal("snacks", Config.options.picker)
      assert.are.equal("custom", Config.options.socket)
      assert.are.equal("Review {file}", Config.options.prompts.review)
      assert.are.equal("{file}", Config.options.prompts["{file}"])
      assert.are.same({ "good" }, vim.tbl_keys(Config.options.cli.tools))
      assert.are.equal("cmd is missing or empty", Config.dropped_tools.bad)
      assert.are.equal("{lines} {note} custom", Config.options.annotations.item)
      assert.are.equal("float", Config.options.cli.win.layout)
    end)
  end)
end)
