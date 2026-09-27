--- Vantage: a tmux-based coding-agent manager for Neovim.
---
--- This module is the composition root. It applies configuration, resolves the
--- configured Driver and Picker, then installs the runtime hooks, the Terminal's
--- action resolver, and the command.
local Backend = require("vantage.backend")
local Commands = require("vantage.commands")
local Config = require("vantage.config")
local Picker = require("vantage.frontend.picker")
local Prompt = require("vantage.commands.prompt")
local Review = require("vantage.frontend.review")
local Terminal = require("vantage.frontend.terminal")

local M = {}

---@param opts? vantage.Config
function M.setup(opts)
  Config.apply(opts)

  -- Resolve the pluggable implementations before installing any runtime
  -- side effects. A bad backend/picker therefore leaves no command or autocmd
  -- behind, while Config.options retains the attempted values for health.
  local ok, err = pcall(function()
    Backend.setup()
    Picker.setup()

    Prompt.setup()
    Review.setup()
    -- The Frontend cannot import the command layer, so the terminal's action
    -- vocabulary is installed here, once, instead of threaded through every
    -- Terminal.open by the flow that happens to open it.
    Terminal.setup(Commands.resolve)

    vim.api.nvim_create_user_command("Vantage", function(args)
      Commands.run(args)
    end, {
      nargs = "*",
      range = true, -- `:Vantage review` uses the range as the review span
      complete = function(arglead, cmdline)
        return Commands.complete(arglead, cmdline)
      end,
      desc = "Vantage coding-agent manager",
    })
  end)
  if not ok then
    Backend.reset()
    Picker.reset()
    error(err, 0)
  end
end

return M
