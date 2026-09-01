--- Shared helpers for the Vantage plugin.
local M = {}

--- The selection prompt glyph (U+F105, e.g. Nerd Font), shared by the Picker
--- and the plain `vim.ui.select` flows.
M.picker_prompt = vim.fn.nr2char(0xF105)

--- Run a command synchronously via vim.system.
---@param cmd string[]
---@return integer code
---@return string stdout
---@return string stderr
function M.run(cmd)
  local process = vim.system(cmd, { text = true })
  local result = process:wait()
  return result.code or 0, result.stdout or "", result.stderr or ""
end

--- Normalized window-local cwd (respects :lcd / :tcd).
---@return string
function M.cwd()
  return vim.fs.normalize(vim.fn.fnamemodify(vim.fn.getcwd(0), ":p"))
end

--- Fold $HOME into ~ for display.
---@param path string
---@return string
function M.tilde(path)
  local home = vim.fn.getenv("HOME") or ""
  if home == "" then
    return path
  end
  if path == home then
    return "~"
  end
  if vim.startswith(path, home .. "/") then
    return "~" .. path:sub(#home + 1)
  end
  return path
end

---@param msg string
---@param level? integer
function M.notify(msg, level)
  vim.notify("vantage: " .. msg, level or vim.log.levels.ERROR)
end

---@param msg string
function M.warn(msg)
  M.notify(msg, vim.log.levels.WARN)
end

---@param msg string
function M.info(msg)
  M.notify(msg, vim.log.levels.INFO)
end

return M
