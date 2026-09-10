--- The :Vantage user command: subcommand dispatch. Each subcommand's logic
--- lives in its own module under `vantage.commands`; this file only maps
--- subcommand names to functions and owns the one-line commands (detach,
--- status).
local Attach = require("vantage.commands.attach")
local Bridge = require("vantage.backend.bridge")
local Kill = require("vantage.commands.kill")
local Review = require("vantage.commands.review")
local Terminal = require("vantage.frontend.terminal")
local Util = require("vantage.util")

local M = {}

local function usage()
  vim.notify(
    table.concat({
      "Vantage — coding-agent manager",
      "",
      "  :Vantage toggle          hide/show the terminal (picks an Agent if none)",
      "  :Vantage detach          destroy the terminal (Agents keep running)",
      "  :Vantage review          review a range (visual selection, or current line)",
      "  :Vantage review list     open the review picker",
      "  :Vantage review clear    clear every review",
      "  :Vantage kill            kill an Agent or Group",
      "  :Vantage status          show clients + sessions",
    }, "\n"),
    vim.log.levels.INFO
  )
end

local function status()
  local status_info, err = Bridge.status()
  if status_info == nil then
    Util.warn(err or "failed to read status")
    return
  end
  local lines = { "sessions:" }
  for _, line in ipairs(status_info.sessions) do
    lines[#lines + 1] = "  " .. line
  end
  lines[#lines + 1] = "clients:"
  for _, line in ipairs(status_info.clients) do
    lines[#lines + 1] = "  " .. line
  end
  vim.notify(table.concat(lines, "\n"), vim.log.levels.INFO)
end

function M.run(args)
  local fargs = args.fargs or {}
  local subcommand = fargs[1]
  local remaining = {}
  for i = 2, #fargs do
    remaining[#remaining + 1] = fargs[i]
  end

  if subcommand == nil then
    usage()
  elseif subcommand == "toggle" then
    Attach.toggle()
  elseif subcommand == "detach" then
    Terminal.destroy()
  elseif subcommand == "review" then
    Review.run(remaining[1], args.line1, args.line2)
  elseif subcommand == "kill" then
    Kill.run()
  elseif subcommand == "status" then
    status()
  else
    Util.warn(("unknown subcommand '%s'"):format(subcommand))
    usage()
  end
end

---@param arglead string
---@param cmdline string
---@return string[]
function M.complete(arglead, cmdline)
  local subcommands = { "toggle", "detach", "review", "kill", "status" }
  if cmdline:match("^%s*Vantage%s+review%s+%S*%s*$") then
    return vim.tbl_filter(function(s)
      return vim.startswith(s, arglead)
    end, { "list", "clear" })
  end
  if cmdline:match("^%s*Vantage%s*$") or cmdline:match("^%s*Vantage%s+%S*%s*$") then
    return vim.tbl_filter(function(s)
      return vim.startswith(s, arglead)
    end, subcommands)
  end
  return {}
end

return M
