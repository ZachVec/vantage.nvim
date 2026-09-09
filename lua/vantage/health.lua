--- :checkhealth vantage
local M = {}

local start = vim.health.start or vim.health.report_start
local ok = vim.health.ok or vim.health.report_ok
local warn = vim.health.warn or vim.health.report_warn
local err = vim.health.error or vim.health.report_error

--- True when the Lua module `mod` (dots as separators) is on the runtimepath,
--- without loading it.
local function module_available(mod)
  local path = mod:gsub("%.", "/")
  return #vim.api.nvim_get_runtime_file(("lua/%s.lua"):format(path), false) > 0
    or #vim.api.nvim_get_runtime_file(("lua/%s/init.lua"):format(path), false) > 0
end

--- Validate configured prompt placeholders (name -> template).
local function check_prompts()
  local prompts = require("vantage.config").options.prompts or {}
  local known = require("vantage.commands.prompt").PLACEHOLDERS
  local unknown = {}
  local uses_symbol = false
  for _, template in pairs(prompts) do
    if type(template) == "string" then
      for token in template:gmatch("{([%w_]+)}") do
        if not known[token] then
          unknown[token] = true
        elseif token == "function" or token == "class" then
          uses_symbol = true
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
  if uses_symbol and not module_available("nvim-treesitter-textobjects.shared") then
    warn("prompts use {function}/{class} but nvim-treesitter-textobjects is not installed")
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

  for _, check in ipairs(require("vantage.backend.driver").get().health()) do
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
  if picker == "native" then
    ok("picker: native (built-in vim.ui.select)")
  else
    local dep = picker == "fzf-lua" and "fzf-lua" or (picker == "snacks" and "snacks.picker" or nil)
    if not dep then
      warn(("picker '%s' is unknown — falling back to native"):format(tostring(picker)))
    elseif module_available(dep) then
      ok(("picker: %s"):format(picker))
    else
      err(("picker '%s' configured but '%s' is not installed"):format(picker, dep))
    end
  end

  check_tools()
  check_prompts()
end

return M
