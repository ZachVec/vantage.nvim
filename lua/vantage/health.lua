--- :checkhealth vantage
local M = {}

local start = vim.health.start or vim.health.report_start
local ok = vim.health.ok or vim.health.report_ok
local warn = vim.health.warn or vim.health.report_warn
local err = vim.health.error or vim.health.report_error

--- Validate the cli.tools configuration. Invalid entries are dropped at setup
--- with a warning; this check surfaces what was dropped.
local function check_tools()
  local config = require("vantage.config")
  local dropped = config.dropped_tools
  if next(dropped) ~= nil then
    local lines = {}
    for name, reason in pairs(dropped) do
      lines[#lines + 1] = ("'%s' (%s)"):format(name, reason)
    end
    table.sort(lines)
    err(("cli.tools: dropped entries: %s"):format(table.concat(lines, ", ")))
  else
    ok("cli.tools: no invalid entries (non-empty name + non-empty cmd)")
  end
end

function M.check()
  start("vantage")

  if vim.fn.has("nvim-0.12") == 1 then
    ok("Neovim >= 0.12")
  else
    err("Neovim >= 0.12 is required")
    return
  end

  local checked, checks = pcall(require("vantage.backend").health)
  if not checked then
    err(tostring(checks))
    return
  end

  for _, check in ipairs(checks) do
    if check.status == "ok" then
      ok(check.message)
    elseif check.status == "warn" then
      warn(check.message)
    else
      err(check.message)
    end
    if check.fatal then
      return
    end
  end

  local picker = require("vantage.config").options.picker
  ok(("picker: %s"):format(picker))

  check_tools()
end

return M
