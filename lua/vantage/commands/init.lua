--- The command layer's own module: the `:Vantage` subcommand dispatch and the
--- Terminal action vocabulary. Every other module under `vantage.commands` is a
--- flow. This one maps subcommand names to functions, owns the one-line
--- commands (show, hide, detach, status), and holds the strings a
--- `cli.win.keys` `rhs` may name — a token's meaning is a command, so the token
--- table lives here too. Dispatch, the usage text, and completion all derive
--- from one table, so a subcommand is named once.
local Attach = require("vantage.commands.attach")
local Backend = require("vantage.backend")
local Kill = require("vantage.commands.kill")
local Review = require("vantage.commands.review")
local Terminal = require("vantage.frontend.terminal")
local Util = require("vantage.util")

local M = {}

local function status()
  local status_info, err = Backend.status()
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

--- One fixed word of a subcommand's own, e.g. `review clear`.
---@class vantage.SubcommandArg
---@field name string
---@field help string

--- One `:Vantage` subcommand. Everything the user sees about it — dispatch, the
--- usage line, completion, and any words of its own — comes from here.
---@class vantage.Subcommand
---@field name string
---@field help string
---@field run fun(rest: string[], args: table) `rest` holds the words after `name`
---@field args? vantage.SubcommandArg[] the subcommand's own fixed words

---@type vantage.Subcommand[]
local SUBCOMMANDS = {
  {
    name = "show",
    help = "show the terminal (picks an Agent if none; focuses it when open)",
    run = function()
      Attach.show()
    end,
  },
  {
    name = "hide",
    help = "hide the terminal window (the client stays attached)",
    run = function()
      Terminal.hide()
    end,
  },
  {
    name = "detach",
    help = "destroy the terminal (Agents keep running)",
    run = function()
      Terminal.destroy()
    end,
  },
  {
    name = "review",
    help = "review a range (visual selection, or current line)",
    run = function(rest, args)
      Review.run(rest[1], args.line1, args.line2)
    end,
    args = {
      { name = "list", help = "open the review picker" },
      { name = "clear", help = "clear every review" },
    },
  },
  {
    name = "kill",
    help = "kill Agents (mark several to kill them together)",
    run = function()
      Kill.run()
    end,
  },
  {
    name = "status",
    help = "show clients + sessions",
    run = status,
  },
}

local function usage()
  local lines = { "Vantage — coding-agent manager", "" }
  for _, sub in ipairs(SUBCOMMANDS) do
    lines[#lines + 1] = ("  :Vantage %-15s %s"):format(sub.name, sub.help)
    for _, arg in ipairs(sub.args or {}) do
      lines[#lines + 1] = ("  :Vantage %-15s %s"):format(sub.name .. " " .. arg.name, arg.help)
    end
  end
  vim.notify(table.concat(lines, "\n"), vim.log.levels.INFO)
end

---@param names string[]
---@param arglead string
---@return string[]
local function matching(names, arglead)
  return vim.tbl_filter(function(name)
    return vim.startswith(name, arglead)
  end, names)
end

--- The `name` of every entry, whether a subcommand or one of its words.
---@param entries { name: string }[]
---@return string[]
local function names_of(entries)
  return vim.tbl_map(function(entry)
    return entry.name
  end, entries)
end

function M.run(args)
  local fargs = args.fargs
  local subcommand = fargs[1]
  if subcommand == nil then
    usage()
    return
  end

  local rest = {}
  for i = 2, #fargs do
    rest[#rest + 1] = fargs[i]
  end

  for _, sub in ipairs(SUBCOMMANDS) do
    if sub.name == subcommand then
      sub.run(rest, args)
      return
    end
  end

  Util.warn(("unknown subcommand '%s'"):format(subcommand))
  usage()
end

---@param arglead string
---@param cmdline string
---@return string[]
function M.complete(arglead, cmdline)
  -- A completed first word: offer that subcommand's own words.
  local named = cmdline:match("^%s*Vantage%s+(%S+)%s+%S*%s*$")
  if named then
    for _, sub in ipairs(SUBCOMMANDS) do
      if sub.name == named then
        return matching(names_of(sub.args or {}), arglead)
      end
    end
    return {}
  end
  -- No word yet, or the first word still being typed: offer the names.
  if cmdline:match("^%s*Vantage%s*$") or cmdline:match("^%s*Vantage%s+%S*%s*$") then
    return matching(names_of(SUBCOMMANDS), arglead)
  end
  return {}
end

--- The Terminal action tokens: what a `cli.win.keys` `rhs` string may name. A
--- token's meaning is a command. `prompt` and gather are installed by the
--- composition root, which also runs their setup; the table resolves the
--- tokens to their flows on demand.
---@type table<string, fun()>
local ACTIONS = {
  hide = function()
    Terminal.hide()
  end,
  switch = function()
    Attach.switch()
  end,
  prompt = function()
    require("vantage.commands.prompt").run()
  end,
  files = function()
    require("vantage.commands.gather").files()
  end,
  buffers = function()
    require("vantage.commands.gather").buffers()
  end,
}

--- Resolve a cli.win.keys rhs: a string naming a built-in action becomes that
--- action's function; anything else is returned unchanged. The composition root
--- installs this as the Terminal's resolver.
---@param rhs any
---@return any
function M.resolve(rhs)
  if type(rhs) == "string" then
    return ACTIONS[rhs] or rhs
  end
  return rhs
end

return M
