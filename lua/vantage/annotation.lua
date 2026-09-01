--- Annotation domain: a user note anchored to a line range in a normal file,
--- batched into the focused Agent's input through the `{annotations}` prompt
--- placeholder.
---
--- An Annotation is a line range (`start_row..end_row`, 1-based inclusive) plus
--- a free-text `note`. It lives entirely in memory: a per-buffer registry maps
--- an extmark id to { buf, start_row, end_row, note }. The extmark carries the
--- range and a `number_hl_group` tint; when the number column is off there is
--- nothing to tint, so nothing renders (the annotation stays reachable via
--- `list`).
local Config = require("vantage.config")
local Util = require("vantage.util")

local M = {}

local NS = vim.api.nvim_create_namespace("vantage_annotation")

--- registry[buf][extmark_id] = vantage.Annotation
---@type table<integer, table<integer, vantage.Annotation>>
local registry = {}

---@class vantage.Annotation
---@field buf integer source buffer
---@field id integer extmark id (unique per buffer)
---@field start_row integer 1-based inclusive
---@field end_row integer 1-based inclusive
---@field note string

-- ---------------------------------------------------------------------------
-- Lifecycle
-- ---------------------------------------------------------------------------

--- Register buffer-unload pruning and default highlight groups.
function M.setup()
  vim.api.nvim_create_augroup("VantageAnnotation", { clear = true })
  vim.api.nvim_create_autocmd("BufUnload", {
    group = "VantageAnnotation",
    callback = function(args)
      registry[args.buf] = nil
    end,
  })
  local function link(name, to)
    if vim.fn.hlexists(name) == 0 then
      vim.api.nvim_set_hl(0, name, { link = to })
    end
  end
  link("VantageAnnotation", "Special")
  link("VantageAnnotationActive", "WarningMsg")
end

-- ---------------------------------------------------------------------------
-- CRUD
-- ---------------------------------------------------------------------------

--- Create an annotation over lines `start_row..end_row` (1-based inclusive).
---@param buf integer
---@param start_row integer
---@param end_row integer
---@param note string
---@return vantage.Annotation?
function M.add(buf, start_row, end_row, note)
  local last = vim.api.nvim_buf_line_count(buf)
  start_row = math.max(1, start_row)
  end_row = math.min(end_row, last)
  if start_row > end_row then
    start_row, end_row = end_row, start_row
  end
  local id = vim.api.nvim_buf_set_extmark(buf, NS, start_row - 1, 0, {
    end_row = end_row - 1,
    number_hl_group = "VantageAnnotation",
    strict = false,
  })
  if id == 0 then
    return nil
  end
  local annotation = { buf = buf, id = id, start_row = start_row, end_row = end_row, note = note }
  registry[buf] = registry[buf] or {}
  registry[buf][id] = annotation
  return annotation
end

---@param buf integer
---@param id integer
---@return vantage.Annotation?
function M.get(buf, id)
  local by_id = registry[buf]
  return by_id and by_id[id] or nil
end

--- Replace an annotation's note text.
---@param buf integer
---@param id integer
---@param note string
function M.edit(buf, id, note)
  local annotation = M.get(buf, id)
  if annotation then
    annotation.note = note
  end
end

--- Remove one annotation (extmark + registry entry).
---@param buf integer
---@param id integer
function M.delete(buf, id)
  local by_id = registry[buf]
  if not by_id or not by_id[id] then
    return
  end
  pcall(vim.api.nvim_buf_del_extmark, buf, NS, id)
  by_id[id] = nil
  if next(by_id) == nil then
    registry[buf] = nil
  end
end

--- Remove every annotation.
function M.clear()
  for buf in pairs(registry) do
    if vim.api.nvim_buf_is_valid(buf) then
      pcall(vim.api.nvim_buf_clear_namespace, buf, NS, 0, -1)
    end
  end
  registry = {}
end

--- Every live annotation, sorted by (buffer name, start row). Entries whose
--- extmark no longer exists (e.g. after `:e!`) are skipped.
---@return vantage.Annotation[]
function M.collect()
  local out = {}
  for buf, by_id in pairs(registry) do
    if vim.api.nvim_buf_is_valid(buf) then
      for _, annotation in pairs(by_id) do
        local pos = vim.api.nvim_buf_get_extmark_by_id(buf, NS, annotation.id, {})
        if pos and pos[1] then
          out[#out + 1] = annotation
        end
      end
    end
  end
  table.sort(out, function(a, b)
    local na = vim.api.nvim_buf_get_name(a.buf) or ""
    local nb = vim.api.nvim_buf_get_name(b.buf) or ""
    if na ~= nb then
      return na < nb
    end
    return a.start_row < b.start_row
  end)
  return out
end

-- ---------------------------------------------------------------------------
-- Visual emphasis (read/edit)
-- ---------------------------------------------------------------------------

--- Swap one annotation's range tint between the resting and active highlight.
---@param buf integer
---@param id integer
---@param active boolean
function M.set_active(buf, id, active)
  local annotation = M.get(buf, id)
  if not annotation or not vim.api.nvim_buf_is_valid(buf) then
    return
  end
  local pos = vim.api.nvim_buf_get_extmark_by_id(buf, NS, id, {})
  if not pos or not pos[1] then
    return
  end
  vim.api.nvim_buf_set_extmark(buf, NS, pos[1], pos[2], {
    id = id,
    number_hl_group = active and "VantageAnnotationActive" or "VantageAnnotation",
  })
end

-- ---------------------------------------------------------------------------
-- Rendering ({annotations} placeholder)
-- ---------------------------------------------------------------------------

local FIELDS = { note = true, lines = true, code = true, file = true, start = true, ["end"] = true }

--- The annotation's selected lines, with leading/trailing blank lines dropped.
---@param annotation vantage.Annotation
---@return string
local function code_text(annotation)
  local lines = vim.api.nvim_buf_get_lines(annotation.buf, annotation.start_row - 1, annotation.end_row, false)
  while #lines > 0 and lines[1]:find("^%s*$") do
    table.remove(lines, 1)
  end
  while #lines > 0 and lines[#lines]:find("^%s*$") do
    table.remove(lines)
  end
  return table.concat(lines, "\n")
end

---@param annotation vantage.Annotation
---@param name string
---@param cwd string
---@return string?
local function field(annotation, name, cwd)
  local path = vim.api.nvim_buf_get_name(annotation.buf) or ""
  if name == "note" then
    return annotation.note
  elseif name == "lines" then
    local range = annotation.start_row == annotation.end_row and (":L%d"):format(annotation.start_row)
      or (":L%d-%d"):format(annotation.start_row, annotation.end_row)
    return "@" .. Util.relpath(cwd, path) .. " " .. range
  elseif name == "code" then
    return code_text(annotation)
  elseif name == "file" then
    return Util.relpath(cwd, path)
  elseif name == "start" then
    return tostring(annotation.start_row)
  elseif name == "end" then
    return tostring(annotation.end_row)
  end
end

---@param annotation vantage.Annotation
---@param template string
---@param cwd string
---@return string
local function render_item(annotation, template, cwd)
  return (
    template:gsub("{([%w_]+)}", function(name)
      if not FIELDS[name] then
        return "{" .. name .. "}" -- unknown: left literal
      end
      return field(annotation, name, cwd) or ""
    end)
  )
end

--- Render every annotation through the configured `item` template into one
--- string, or nil when there are none (so the prompt skips with a warning).
---@param cwd string focused Agent cwd (relativization base)
---@return string?
function M.render(cwd)
  local annotations = M.collect()
  if #annotations == 0 then
    return nil
  end
  local item = Config.options.annotations.item
  local out = {}
  for _, annotation in ipairs(annotations) do
    out[#out + 1] = render_item(annotation, item, cwd)
  end
  return table.concat(out, "\n")
end

return M
