--- The gather flow (terminal tokens `files` and `buffers`): pick several
--- files or buffers through the Picker and type their `<relpath>` references
--- into the focused Agent's input through the shared send path. References
--- are bare paths — the Tool's `format` hook owns the dialect decoration.
local Picker = require("vantage.frontend.picker")
local Send = require("vantage.commands.send")
local Util = require("vantage.util")

local M = {}

--- Lines read for a row's preview.
local PREVIEW_LINES = 200

--- External file listers tried in order; the Lua walk covers installs with
--- neither. All of them skip `.git`; ignore semantics come from the tool.
local LISTERS = {
  { "fd", "--type", "f", "--type", "l", "--color", "never", "-E", ".git" },
  { "rg", "--files", "--no-messages", "--color", "never", "-g", "!.git" },
}

---@class vantage.GatherItem One selectable reference source row.
---@field path string absolute file path
---@field cwd string focused Agent cwd (relativization base)
---@field format fun(self: vantage.GatherItem): string
---@field preview fun(self: vantage.GatherItem): string[]?
---@field reference fun(self: vantage.GatherItem): string

--- The first PREVIEW_LINES lines of a file, or nil when it cannot be read.
---@param path string
---@return string[]?
local function file_preview(path)
  local ok, lines = pcall(vim.fn.readfile, path, "", PREVIEW_LINES)
  if not ok or type(lines) ~= "table" then
    return nil
  end
  return lines
end

---@class vantage.GatherFileItem : vantage.GatherItem
local FileItem = {}
FileItem.__index = FileItem

---@param path string absolute file path
---@param cwd string
---@return vantage.GatherFileItem
function FileItem.new(path, cwd)
  return setmetatable({ path = path, cwd = cwd }, FileItem)
end

function FileItem:format()
  return Util.relpath(self.cwd, self.path)
end

function FileItem:preview()
  return file_preview(self.path)
end

function FileItem:reference()
  return Util.relpath(self.cwd, self.path)
end

---@class vantage.GatherBufferItem : vantage.GatherItem
---@field buf integer
---@field modified boolean
local BufferItem = {}
BufferItem.__index = BufferItem

---@param buf integer
---@param path string absolute file path
---@param cwd string
---@param modified boolean
---@return vantage.GatherBufferItem
function BufferItem.new(buf, path, cwd, modified)
  return setmetatable({ buf = buf, path = path, cwd = cwd, modified = modified }, BufferItem)
end

--- A modified buffer's on-disk content is stale; the marker keeps that
--- visible without leaking into the reference text.
function BufferItem:format()
  local name = Util.relpath(self.cwd, self.path)
  return self.modified and (name .. " [+]") or name
end

function BufferItem:preview()
  if not vim.api.nvim_buf_is_valid(self.buf) then
    return file_preview(self.path)
  end
  local count = vim.api.nvim_buf_line_count(self.buf)
  return vim.api.nvim_buf_get_lines(self.buf, 0, math.min(count, PREVIEW_LINES), false)
end

function BufferItem:reference()
  return Util.relpath(self.cwd, self.path)
end

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
---@return vantage.GatherItem[]
local function file_items(cwd)
  local items = {}
  for _, path in ipairs(list_files(cwd)) do
    items[#items + 1] = FileItem.new(path, cwd)
  end
  return items
end

--- Buffer candidates: listed, normal-buftype, named, readable-on-disk
--- buffers, most recently used first (path order breaks ties).
---@param cwd string
---@return vantage.GatherItem[]
local function buffer_items(cwd)
  local rows = {}
  for _, info in ipairs(vim.fn.getbufinfo({ buflisted = 1 })) do
    local name = info.name
    if name ~= "" and vim.bo[info.bufnr].buftype == "" and vim.fn.filereadable(name) == 1 then
      rows[#rows + 1] = {
        lastused = info.lastused or 0,
        item = BufferItem.new(info.bufnr, vim.fs.normalize(name), cwd, vim.bo[info.bufnr].modified),
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

---@type table<string, { prompt: string, items: fun(cwd: string): vantage.GatherItem[] }>
local SOURCES = {
  files = { prompt = "Files: ", items = file_items },
  buffers = { prompt = "Buffers: ", items = buffer_items },
}

--- Pick several rows from `source` and type their references into the focused
--- Agent's input.
---@param source "files"|"buffers"
local function run(source)
  local agent, err = Send.focused()
  if not agent then
    Util.warn(err or "failed to resolve the focused agent")
    return
  end
  local items = SOURCES[source].items(agent.cwd)
  local win = vim.api.nvim_get_current_win()
  local empty = Picker.pick_multi({
    prompt = SOURCES[source].prompt,
    items_provider = function()
      return items
    end,
  }, {
    on_choices = function(chosen)
      local refs = {}
      for _, item in ipairs(chosen) do
        refs[#refs + 1] = item:reference()
      end
      local ok, send_err = Send.references(agent, refs)
      if not ok then
        Util.warn(send_err or "failed to send references")
      end
    end,
    -- Restore the invoking window once the picker engine has finished
    -- closing its own; a synchronous restore can fight that teardown.
    on_close = function()
      vim.schedule(function()
        if vim.api.nvim_win_is_valid(win) then
          vim.api.nvim_set_current_win(win)
        end
      end)
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
