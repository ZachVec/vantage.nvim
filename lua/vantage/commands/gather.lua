--- The gather flow (terminal tokens `files` and `buffers`): pick several
--- files or buffers through the Picker and type their `<relpath>` references
--- into the focused Agent's input through the shared send path. References
--- are bare paths — the Tool's `format` hook owns the dialect decoration.
local Backend = require("vantage.backend")
local Config = require("vantage.config")
local Entries = require("vantage.frontend.entries")
local Picker = require("vantage.frontend.picker")
local Terminal = require("vantage.frontend.terminal")
local Util = require("vantage.util")

local M = {}

--- External file listers tried in order; the Lua walk covers installs with
--- neither. All of them skip `.git`; ignore semantics come from the tool.
local LISTERS = {
  { "fd", "--type", "f", "--type", "l", "--color", "never", "-E", ".git" },
  { "rg", "--files", "--no-messages", "--color", "never", "-g", "!.git" },
}

--- Collect every readable file under `root` (absolute paths, `.git` skipped).
---@param root string
---@param out string[]
local function walk(root, out)
  local ok, entries = pcall(vim.fs.dir, root)
  if not ok or not entries then
    return
  end
  for name, kind in entries do
    if name ~= ".git" then
      local path = vim.fs.joinpath(root, name)
      if kind == "directory" then
        walk(path, out)
      elseif kind == "file" then
        out[#out + 1] = path
      elseif kind == "link" then
        local stat = (vim.uv or vim.loop).fs_stat(path)
        if stat and stat.type == "file" then
          out[#out + 1] = path
        end
      end
    end
  end
end

--- File candidates under `cwd` as absolute paths, sorted. The first available
--- lister wins; an empty success is a real answer, not a reason to fall
--- through.
---@param cwd string
---@return string[]
local function list_files(cwd)
  for _, cmd in ipairs(LISTERS) do
    if vim.fn.executable(cmd[1]) == 1 then
      local ok, code, stdout = pcall(Util.run, cmd, { cwd = cwd })
      if ok and code == 0 then
        local paths = {}
        for _, line in ipairs(vim.split(stdout or "", "\n", { plain = true })) do
          if line ~= "" then
            paths[#paths + 1] = vim.fs.normalize(vim.fs.joinpath(cwd, line))
          end
        end
        table.sort(paths)
        return paths
      end
    end
  end
  local paths = {}
  walk(cwd, paths)
  table.sort(paths)
  return paths
end

---@param cwd string
---@return vantage.picker.Entry[]
local function file_items(cwd)
  local items = {}
  for _, path in ipairs(list_files(cwd)) do
    items[#items + 1] = Entries.file(path, cwd)
  end
  return items
end

--- Buffer candidates: listed, normal-buftype, named, readable-on-disk
--- buffers, most recently used first (path order breaks ties).
---@param cwd string
---@return vantage.picker.Entry[]
local function buffer_items(cwd)
  local rows = {}
  for _, info in ipairs(vim.fn.getbufinfo({ buflisted = 1 })) do
    local name = info.name
    if name ~= "" and vim.bo[info.bufnr].buftype == "" and vim.fn.filereadable(name) == 1 then
      rows[#rows + 1] = {
        lastused = info.lastused or 0,
        item = Entries.buffer(info.bufnr, vim.fs.normalize(name), cwd, vim.bo[info.bufnr].modified),
      }
    end
  end
  table.sort(rows, function(a, b)
    if a.lastused ~= b.lastused then
      return a.lastused > b.lastused
    end
    return a.item.path < b.item.path
  end)
  local items = {}
  for _, row in ipairs(rows) do
    items[#items + 1] = row.item
  end
  return items
end

---@type table<string, { prompt: string, items: fun(cwd: string): vantage.picker.Entry[] }>
local SOURCES = {
  files = { prompt = "Files: ", items = file_items },
  buffers = { prompt = "Buffers: ", items = buffer_items },
}

--- Pick several entries from `source` and type their references into the
--- focused Agent's input.
---@param source "files"|"buffers"
local function run(source)
  local agent, err = Backend.focus(Terminal.pid())
  if not agent then
    Util.warn(err or "no focused agent")
    return
  end
  local items = SOURCES[source].items(agent.cwd)
  local empty = Picker.pick_multi({
    prompt = SOURCES[source].prompt,
    items_provider = function()
      return items
    end,
  }, {
    on_choices = function(chosen)
      -- Every chosen path is spelled through the Tool's dialect, joined with
      -- `setup { gather = { join = … } }`, and pasted with a trailing space so
      -- continued typing stays off the last reference. A reference the hook
      -- declines drops the whole send. No trailing newline: a pasted trailing
      -- newline shows as an empty line in the Agent's input.
      local refs = {}
      for _, item in ipairs(chosen) do
        ---@cast item vantage.picker.PathEntry
        local ref = Config.tool_reference(agent.tool, agent.cwd, item.path)
        if ref == nil then
          Util.warn("no references sent: dropped by its format hook")
          return
        end
        refs[#refs + 1] = ref
      end
      local ok, send_err = Backend.send(agent, table.concat(refs, Config.options.gather.join) .. " ")
      if not ok then
        Util.warn(send_err or "failed to send references")
      end
    end,
  })
  if empty then
    Util.warn(("no %s"):format(source))
  end
end

--- Choose files and send their references to the focused Agent.
function M.files()
  run("files")
end

--- Choose buffers and send their references to the focused Agent.
function M.buffers()
  run("buffers")
end

return M
