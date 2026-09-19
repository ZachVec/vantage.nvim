--- Review domain: a user note anchored to a line range in a normal file,
--- batched into the focused Agent's input through the `{reviews}` prompt
--- placeholder.
---
--- A Review is a line range (`start_row..end_row`, 1-based inclusive) plus a
--- free-text `note`. It lives entirely in memory: a per-buffer registry maps
--- an extmark id to { buf, start_row, end_row, note }. The extmark carries the
--- range and a `number_hl_group` tint; when the number column is off there is
--- nothing to tint, so nothing renders (the review stays reachable via
--- `list`).
---
--- This module also owns the Review's editing float: `edit` and `create` open
--- a scratch buffer in a centered float whose `<Esc>` commits, and the Review
--- policy (save on exit, empty deletes) lives here, not in the command layer.
--- The float mechanics are a private helper, not a contract.
local Config = require("vantage.config")
local Util = require("vantage.util")

local M = {}

local NS = vim.api.nvim_create_namespace("vantage_review")

--- registry[buf][extmark_id] = vantage.Review
---@type table<integer, table<integer, vantage.Review>>
local registry = {}

---@class vantage.Review
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
  vim.api.nvim_create_augroup("VantageReview", { clear = true })
  vim.api.nvim_create_autocmd("BufUnload", {
    group = "VantageReview",
    callback = function(args)
      registry[args.buf] = nil
    end,
  })
  local function link(name, to)
    if vim.fn.hlexists(name) == 0 then
      vim.api.nvim_set_hl(0, name, { link = to })
    end
  end
  link("VantageReview", "Special")
  link("VantageReviewActive", "WarningMsg")
end

-- ---------------------------------------------------------------------------
-- CRUD
-- ---------------------------------------------------------------------------

--- Create a review over lines `start_row..end_row` (1-based inclusive).
---@param buf integer
---@param start_row integer
---@param end_row integer
---@param note string
---@return vantage.Review?
function M.add(buf, start_row, end_row, note)
  local last = vim.api.nvim_buf_line_count(buf)
  start_row = math.max(1, start_row)
  end_row = math.min(end_row, last)
  if start_row > end_row then
    start_row, end_row = end_row, start_row
  end
  local id = vim.api.nvim_buf_set_extmark(buf, NS, start_row - 1, 0, {
    end_row = end_row - 1,
    number_hl_group = "VantageReview",
    strict = false,
  })
  if id == 0 then
    return nil
  end
  local review = { buf = buf, id = id, start_row = start_row, end_row = end_row, note = note }
  registry[buf] = registry[buf] or {}
  registry[buf][id] = review
  return review
end

---@param buf integer
---@param id integer
---@return vantage.Review?
function M.get(buf, id)
  local by_id = registry[buf]
  return by_id and by_id[id]
end

--- Replace a review's note text.
---@param buf integer
---@param id integer
---@param note string
function M.set_note(buf, id, note)
  local review = M.get(buf, id)
  if review then
    review.note = note
  end
end

--- Remove one review (extmark + registry entry).
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

--- Remove every review.
function M.clear()
  for buf in pairs(registry) do
    if vim.api.nvim_buf_is_valid(buf) then
      pcall(vim.api.nvim_buf_clear_namespace, buf, NS, 0, -1)
    end
  end
  registry = {}
end

--- Every live review, sorted by (buffer name, start row). Entries whose
--- extmark no longer exists (e.g. after `:e!`) are skipped.
---@return vantage.Review[]
function M.collect()
  local out = {}
  for buf, by_id in pairs(registry) do
    if vim.api.nvim_buf_is_valid(buf) then
      for _, review in pairs(by_id) do
        local pos = vim.api.nvim_buf_get_extmark_by_id(buf, NS, review.id, {})
        if pos and pos[1] then
          out[#out + 1] = review
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

--- Swap one review's range tint between the resting and active highlight.
---@param buf integer
---@param id integer
---@param active boolean
local function set_active(buf, id, active)
  if not vim.api.nvim_buf_is_valid(buf) then
    return
  end
  local pos = vim.api.nvim_buf_get_extmark_by_id(buf, NS, id, {})
  if not pos or not pos[1] then
    return
  end
  vim.api.nvim_buf_set_extmark(buf, NS, pos[1], pos[2], {
    id = id,
    number_hl_group = active and "VantageReviewActive" or "VantageReview",
  })
end

-- ---------------------------------------------------------------------------
-- Editing (float)
-- ---------------------------------------------------------------------------

--- The raw `nvim_open_win` style for the editing float, translated from the
--- review config's user-facing "inherit" | "minimal".
---@return string?
local function float_style()
  return Config.options.reviews.float.style == "minimal" and "minimal" or nil
end

--- Jump to the review's start line (first non-blank column).
---@param review vantage.Review
---@return boolean
local function jump_to_review(review)
  if not vim.api.nvim_buf_is_valid(review.buf) then
    return false
  end
  local win = vim.fn.bufwinid(review.buf)
  if win ~= -1 then
    vim.api.nvim_set_current_win(win)
  else
    vim.api.nvim_win_set_buf(0, review.buf)
  end
  local line = vim.api.nvim_buf_get_lines(review.buf, review.start_row - 1, review.start_row, false)[1] or ""
  local _, first = line:find("%S")
  vim.api.nvim_win_set_cursor(0, { review.start_row, first and (first - 1) or 0 })
  return true
end

--- Open an editable scratch float. `<Esc>` reads the buffer, closes the window,
--- and commits the text; every policy decision belongs to the caller.
---@param opts { text: string, title: string, footer: string, insert?: boolean, on_commit: fun(note: string), on_close?: fun() }
local function open_float(opts)
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, vim.split(opts.text or "", "\n", { plain = true }))
  vim.bo[buf].bufhidden = "wipe"

  local width = math.max(40, math.min(80, math.floor(vim.o.columns * 0.5)))
  local height = math.max(8, math.min(20, math.floor(vim.o.lines * 0.5)))
  local win_config = {
    relative = "editor",
    row = math.floor((vim.o.lines - height) / 2),
    col = math.floor((vim.o.columns - width) / 2),
    width = width,
    height = height,
    border = "rounded",
    title = opts.title,
    footer = opts.footer,
  }
  local style = float_style()
  if style then
    win_config.style = style
  end
  local win = vim.api.nvim_open_win(buf, true, win_config)
  if opts.insert then
    vim.cmd("startinsert")
  end

  local function commit()
    local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
    while #lines > 0 and lines[#lines]:find("^%s*$") do
      table.remove(lines)
    end
    local note = table.concat(lines, "\n")
    if vim.api.nvim_win_is_valid(win) then
      pcall(vim.api.nvim_win_close, win, true)
    end
    opts.on_commit(note)
  end

  vim.keymap.set("n", "<Esc>", commit, { buffer = buf, nowait = true, desc = "commit note" })

  vim.api.nvim_create_autocmd("BufWipeout", {
    buffer = buf,
    once = true,
    callback = function()
      if opts.on_close then
        opts.on_close()
      end
    end,
  })
end

--- Edit one Review: jump to its range, mark it active, and open its float. An
--- empty commit deletes it after confirmation. The title names no reference:
--- the jump and the active range already say where you are.
---@param buf integer
---@param id integer
function M.edit(buf, id)
  local review = M.get(buf, id)
  if not review or not jump_to_review(review) then
    return
  end
  set_active(review.buf, review.id, true)
  open_float({
    text = review.note,
    title = "Review",
    footer = "<Esc> save · empty deletes",
    on_commit = function(note)
      if note == "" then
        -- Empty note = delete, after confirmation.
        if vim.fn.confirm("Delete review?", "&Yes\n&No", 2) == 1 then
          M.delete(review.buf, review.id)
        end
      else
        M.set_note(review.buf, review.id, note)
      end
    end,
    on_close = function()
      set_active(review.buf, review.id, false)
    end,
  })
end

--- Ask for a new Review over lines `start_row..end_row` (1-based inclusive):
--- open an empty float in insert mode and add the Review on commit. An empty
--- commit discards it.
---@param buf integer
---@param start_row integer
---@param end_row integer
function M.create(buf, start_row, end_row)
  open_float({
    text = "",
    title = "New Review",
    footer = "<Esc> save",
    insert = true,
    on_commit = function(note)
      if note ~= "" then
        M.add(buf, start_row, end_row, note)
      end
    end,
  })
end

-- ---------------------------------------------------------------------------
-- Rendering ({reviews} placeholder)
-- ---------------------------------------------------------------------------

local FIELDS = { note = true, lines = true, code = true, file = true, start = true, ["end"] = true }

--- The review's selected lines, with leading/trailing blank lines dropped.
---@param review vantage.Review
---@return string
local function code_text(review)
  local lines = vim.api.nvim_buf_get_lines(review.buf, review.start_row - 1, review.end_row, false)
  while #lines > 0 and lines[1]:find("^%s*$") do
    table.remove(lines, 1)
  end
  while #lines > 0 and lines[#lines]:find("^%s*$") do
    table.remove(lines)
  end
  return table.concat(lines, "\n")
end

---@param review vantage.Review
---@param name string
---@param cwd string
---@param tool? string the focused Tool's reference dialect; nil spells the default
---@return string? nil when the location has no reference
local function field(review, name, cwd, tool)
  local path = vim.api.nvim_buf_get_name(review.buf) or ""
  if name == "note" then
    return review.note
  elseif name == "lines" then
    return Config.tool_reference(tool, cwd, path, review.start_row, review.end_row)
  elseif name == "code" then
    return code_text(review)
  elseif name == "file" then
    return Config.tool_reference(tool, cwd, path)
  elseif name == "start" then
    return tostring(review.start_row)
  elseif name == "end" then
    return tostring(review.end_row)
  end
  return "" -- unknown name: unreachable from whitelisted callers
end

---@param review vantage.Review
---@param template string
---@param cwd string
---@param tool? string
---@return string? nil when a location field was dropped
local function render_item(review, template, cwd, tool)
  return Util.interpolate(template, FIELDS, function(name)
    return field(review, name, cwd, tool)
  end)
end

--- Render one review through the configured `item` template (for picker
--- previews: what you see is what gets sent).
---@param review vantage.Review
---@param cwd string focused Agent cwd (relativization base)
---@param tool? string the focused Tool's reference dialect; nil spells the default
---@return string
function M.render_item(review, cwd, tool)
  return render_item(review, Config.options.reviews.item, cwd, tool) or ""
end

--- The `{lines}` location reference for one review, spelled by the Tool's
--- `format` hook (`<relpath> :L<start>-<end>` without one).
---@param review vantage.Review
---@param cwd string
---@param tool? string the focused Tool's reference dialect; nil spells the default
---@return string
function M.location(review, cwd, tool)
  return field(review, "lines", cwd, tool) or ""
end

--- Render every review through the configured `item` template into one
--- string, or nil when there are none — or when a location has no reference —
--- so the prompt skips with a warning.
---@param cwd string focused Agent cwd (relativization base)
---@param tool? string the focused Tool's reference dialect; nil spells the default
---@return string?
function M.render(cwd, tool)
  local reviews = M.collect()
  if #reviews == 0 then
    return nil
  end
  local item = Config.options.reviews.item
  local out = {}
  for _, review in ipairs(reviews) do
    local rendered = render_item(review, item, cwd, tool)
    if rendered == nil then
      return nil
    end
    out[#out + 1] = rendered
  end
  return table.concat(out, "\n")
end

return M
