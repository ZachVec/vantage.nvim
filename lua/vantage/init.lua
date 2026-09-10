--- Vantage: a tmux-based coding-agent manager for Neovim.
---
--- This module is the composition root. It applies configuration, resolves the
--- configured Driver and Picker, then installs the runtime hooks and command.
local Config = require("vantage.config")
local Driver = require("vantage.backend.driver")
local Picker = require("vantage.frontend.picker")
local Prompt = require("vantage.commands.prompt")
local Review = require("vantage.frontend.review")

local M = {}

---@param opts? vantage.Config
function M.setup(opts)
  Config.apply(opts)

  -- Resolve the pluggable implementations before installing any runtime
  -- side effects. A bad backend/picker therefore leaves no command or autocmd
  -- behind, while Config.options retains the attempted values for health.
  local ok, err = pcall(function()
    Driver.setup()
    Picker.setup()

    Prompt.setup()
    Review.setup()

    vim.api.nvim_create_user_command("Vantage", function(args)
      require("vantage.commands").run(args)
    end, {
      nargs = "*",
      range = true, -- `:Vantage review` uses the range as the review span
      complete = function(arglead, cmdline)
        return require("vantage.commands").complete(arglead, cmdline)
      end,
      desc = "Vantage coding-agent manager",
    })
  end)
  if not ok then
    Driver.reset()
    Picker.reset()
    error(err, 0)
  end
end

return M
