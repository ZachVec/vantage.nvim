--- Backend interface: dispatches to the configured multiplexer driver.
--- This is the extension seam for future drivers (e.g. zellij).
local M = {}

---@return table the concrete backend driver module
function M.get()
  local name = require("vantage.config").options.backend
  return require("vantage.backend." .. name)
end

return M
