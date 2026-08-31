--- Vantage: a tmux-based coding-agent manager for Neovim.
local M = {}

---@param opts? vantage.Config
function M.setup(opts)
  require("vantage.config").setup(opts)
end

return M
