--- Shared helpers for the Vantage plugin.
local M = {}

--- The picker prompt glyph (U+F105, e.g. Nerd Font), passed to the pickers as
--- the PickSpec's `prompt` by the flow layer.
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

--- Render `{placeholder}` tokens in `template` against a caller-provided
--- whitelist and resolver. Unknown placeholders are left literal; a resolver
--- returning nil records the failing name and returns nil from this function.
--- This is the single implementation shared by Prompt and Annotation
--- templates.
---@param template string
---@param allowed table<string, boolean>
---@param resolve fun(name: string): string?
---@return string?
---@return string? failed placeholder name, when nil is returned
function M.interpolate(template, allowed, resolve)
  local failed
  local out = template:gsub("{([%w_]+)}", function(name)
    if not allowed[name] then
      return "{" .. name .. "}"
    end
    local value = resolve(name)
    if value == nil then
      failed = name
      return ""
    end
    return value
  end)
  if failed then
    return nil, failed
  end
  return out
end

--- Quote one argument for POSIX `sh -c`, so a `string[]` command keeps its
--- argv boundaries when tmux passes the concatenated shell command to the
--- Agent's shell.
---@param arg string
---@return string
function M.shell_quote(arg)
  if arg == "" then
    return "''"
  end
  return "'" .. arg:gsub("'", "'\\''") .. "'"
end

--- Join an argv array into one safely shell-quoted command string.
---@param args string[]
---@return string
function M.shell_join(args)
  local out = {}
  for _, arg in ipairs(args) do
    out[#out + 1] = M.shell_quote(arg)
  end
  return table.concat(out, " ")
end

--- The numeric index of a tmux window target (`@N`), or 0 when the target is
--- malformed. Kept here so the Backend and Frontend share one degradation
--- rule instead of parsing `@N` in two places.
---@param target string tmux window id (@N)
---@return integer
function M.agent_window_index(target)
  return tonumber(target:match("^@(%d+)$")) or 0
end

--- Normalized global cwd (follows :cd, ignores :lcd / :tcd).
---@return string
function M.cwd()
  return vim.fs.normalize(vim.fn.fnamemodify(vim.fn.getcwd(-1, -1), ":p"))
end

--- Path relative to `cwd`, or absolute when it escapes `cwd` or relativizing
--- fails. Used by Prompt location references and Annotation `{file}`/`{lines}`.
---@param cwd string base directory
---@param path string absolute file path
---@return string
function M.relpath(cwd, path)
  local ok, rel = pcall(vim.fs.relpath, cwd, path)
  if ok and rel and rel ~= "" and rel ~= "." then
    return rel
  end
  return path
end

--- Fold $HOME into ~ for display.
---@param path string
---@return string
function M.tilde(path)
  local home = vim.fn.getenv("HOME")
  if home == nil or home == vim.NIL or home == "" then
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
