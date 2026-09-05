--- The :Vantage user command: subcommand dispatch. Each subcommand's logic
--- lives in its own module under `vantage.commands`; this file only maps
--- subcommand names to functions and owns the few one-line commands (toggle,
--- detach, status).
local Agent = require("vantage.commands.agent")
local Annotation = require("vantage.commands.annotation")
local Backend = require("vantage.backend")
local Client = require("vantage.client")
local Prompt = require("vantage.commands.prompt")
local Util = require("vantage.util")

local M = {}

local function usage()
  vim.notify(
    table.concat({
      "Vantage — coding-agent manager",
      "",
      "  :Vantage switch @N       re-point the terminal to an Agent; interactive if no @N",
      "  :Vantage kill group|@N   kill a Group or Agent; interactive if no argument",
      "  :Vantage toggle          hide/show the terminal (picks an Agent if none)",
      "  :Vantage detach          detach the client (kills the View; Agents survive)",
      "  :Vantage prompt          pick a prompt and type it into the focused Agent",
      "  :Vantage annotate        annotate a range (visual selection, or current line)",
      "  :Vantage annotate list   open the annotation picker",
      "  :Vantage annotate clear  clear every annotation",
      "  :Vantage status          show clients + sessions",
    }, "\n"),
    vim.log.levels.INFO
  )
end

--- Hide/show the terminal (lightweight). With no live terminal, pick an Agent
--- (or create one via a Tool row) and open the terminal on it.
local function toggle()
  if Client.toggle() then
    return
  end
  Agent.pick_or_new(Client.focus)
end

local function detach()
  Client.detach()
end

local function status()
  local status_info = Backend.get().status()
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
  elseif subcommand == "switch" then
    Agent.switch(remaining)
  elseif subcommand == "kill" then
    Agent.kill(remaining)
  elseif subcommand == "toggle" then
    toggle()
  elseif subcommand == "detach" then
    detach()
  elseif subcommand == "prompt" then
    Prompt.run()
  elseif subcommand == "annotate" then
    Annotation.run(remaining[1], args.line1, args.line2)
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
  local subcommands = { "switch", "kill", "toggle", "detach", "prompt", "annotate", "status" }
  if cmdline:match("^%s*Vantage%s+annotate%s+%S*%s*$") then
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
