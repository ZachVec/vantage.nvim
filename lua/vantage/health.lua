--- :checkhealth vantage
local M = {}

local start = vim.health.start or vim.health.report_start
local ok = vim.health.ok or vim.health.report_ok
local warn = vim.health.warn or vim.health.report_warn
local err = vim.health.error or vim.health.report_error

function M.check()
  start("vantage")

  if vim.fn.has("nvim-0.10") == 1 then
    ok("Neovim >= 0.10")
  else
    err("Neovim >= 0.10 is required")
    return
  end

  if vim.fn.executable("tmux") == 1 then
    local version = vim.trim(vim.fn.system({ "tmux", "-V" }))
    ok(("tmux found: %s"):format(version))
  else
    err("tmux not found in PATH")
    return
  end

  local socket = require("vantage.config").options.socket
  local code = vim.system({ "tmux", "-L", socket, "list-sessions" }, { text = true }):wait().code
  if code == 0 then
    ok(("vantage tmux socket '%s' is running"):format(socket))
  elseif code == 1 then
    ok(("vantage tmux socket '%s' not started yet (starts on first use)"):format(socket))
  else
    warn(("tmux socket '%s' check returned exit code %s"):format(socket, tostring(code)))
  end
end

return M
