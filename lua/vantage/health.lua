--- :checkhealth vantage
local M = {}

local start = vim.health.start or vim.health.report_start
local ok = vim.health.ok or vim.health.report_ok
local warn = vim.health.warn or vim.health.report_warn
local err = vim.health.error or vim.health.report_error

--- Validate configured prompt placeholders (name -> template).
local function check_prompts()
  local prompts = require("vantage.config").options.prompts or {}
  local known = require("vantage.config").PROMPT_PLACEHOLDERS
  local unknown = {}
  for _, template in pairs(prompts) do
    if type(template) == "string" then
      for token in template:gmatch("{([%w_]+)}") do
        if not known[token] then
          unknown[token] = true
        end
      end
    end
  end
  if next(unknown) ~= nil then
    local names = {}
    for token in pairs(unknown) do
      names[#names + 1] = "{" .. token .. "}"
    end
    table.sort(names)
    err(("prompts: unknown placeholder(s) %s"):format(table.concat(names, ", ")))
  else
    ok("prompts: all placeholders known")
  end
end

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

  if vim.fn.has("nvim-0.10") == 1 then
    ok("Neovim >= 0.10")
  else
    err("Neovim >= 0.10 is required")
    return
  end

  local driver_ok, driver = pcall(require("vantage.backend.driver").get)
  if not driver_ok then
    err(tostring(driver))
    return
  end

  for _, check in ipairs(driver.health()) do
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
  local picker_ok, capabilities = pcall(require("vantage.frontend.picker").capabilities)
  if not picker_ok then
    err(tostring(capabilities))
    return
  end
  ok(
    ("picker: %s (preview=%s, command=%s)"):format(
      picker,
      capabilities.preview and "yes" or "no",
      capabilities.command and "yes" or "no"
    )
  )

  check_tools()
  check_prompts()
end

return M
