--- Shared picker-row display constants and the Agent row text. Every flow
--- that renders an Agent row must render it identically, so the icon and the
--- `tool · group · cwd` shape live here instead of in one command.
local Util = require("vantage.util")

local M = {}

--- Toggle row glyphs (Nerd Fonts; nf-fa-toggle_on and nf-fa-toggle_off): a
--- running Agent row leads with the "on" icon, a Tool row (which creates a
--- new Agent) with the "off" one. Built with nr2char rather than literal
--- escapes (Lua 5.1 has no \u{…}). Two spaces keep the icon clear of the text.
M.agent_icon = vim.fn.nr2char(0xF205) .. "  "
M.tool_icon = vim.fn.nr2char(0xF204) .. "  "

---@param agent vantage.Agent
---@return string
function M.format_agent(agent)
  return M.agent_icon .. ("%s · %s · %s"):format(agent.tool, agent.group, Util.tilde(agent.cwd))
end

return M
