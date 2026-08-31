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

function M.check()
  start("vantage")

  if vim.fn.has("nvim-0.10") == 1 then
    ok("Neovim >= 0.10")
  else
    err("Neovim >= 0.10 is required")
    return
  end

  for _, check in ipairs(require("vantage.backend").get().health()) do
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
end

return M
