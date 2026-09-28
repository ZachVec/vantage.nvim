--- Review domain: a user note anchored to a line range in a normal file,
--- batched into the focused Agent's input through the `{reviews}` prompt
--- placeholder.
---
--- A Review is identity (`buf` + extmark `id`) and a free-text `note`. It
--- lives entirely in memory: a per-buffer registry maps an extmark id to
--- { buf, id, note }. The extmark is the one owner of the range — a whole-line
--- half-open range plus a `number_hl_group` tint — so edits move the range and
--- every reader sees the moved one. When the number column is off there is
--- nothing to tint, so nothing renders (the review stays reachable via
--- `list`).
---
--- A range the user deleted is *invalidated*, not deleted: with
--- `undo_restore` a code undo brings the extmark — and with it the Review —
--- back, and a redo invalidates it again. Invalid Reviews stay in the registry
--- but leave the list and the send; only an explicit delete, `clear`, or the
--- buffer unloading ends them.
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

--- The `reviews.item` placeholder vocabulary: one resolver per name, so the
--- vocabulary and the dispatch cannot disagree. Assigned below, once the code
--- reader it uses exists.
---@type table<string, fun(review: vantage.Review, cwd: string, tool: string?, start_row: integer, end_row: integer): string?>
local FIELDS = {}

---@class vantage.Review
---@field buf integer source buffer
---@field id integer extmark id (unique per buffer)
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

  local unknown = {}
  for token in Config.options.reviews.item:gmatch("{([%w_]+)}") do
    if not FIELDS[token] then
      unknown[token] = true
    end
  end
  local names = vim.tbl_map(function(token)
    return "{" .. token .. "}"
  end, vim.tbl_keys(unknown))
  if #names > 0 then
    table.sort(names)
    Util.warn(("reviews.item: unknown placeholder(s) %s"):format(table.concat(names, ", ")))
  end
end

-- ---------------------------------------------------------------------------
-- CRUD
-- ---------------------------------------------------------------------------

--- Create a review over lines `start_row..end_row` (1-based inclusive).
---@param buf integer
---@param start_row integer
---@param end_row integer
---@param note string
---@return vantage.Review
function M.add(buf, start_row, end_row, note)
  local last = vim.api.nvim_buf_line_count(buf)
  start_row = math.max(1, start_row)
  end_row = math.min(end_row, last)
  if start_row > end_row then
    start_row, end_row = end_row, start_row
  end
  -- A whole-line range: the start sits at column 0 of the first covered line
  -- and the end at column 0 of the line after the last one, so the 0-based end
  -- row is the last covered 1-based line number. `invalidate` keeps the mark
  -- alive (with `invalid = true`) when the covered code is deleted, and
  -- `undo_restore` lets a code undo bring back its position and validity.
  local id = vim.api.nvim_buf_set_extmark(buf, NS, start_row - 1, 0, {
    end_row = end_row,
    end_col = 0,
    right_gravity = true,
    end_right_gravity = false,
    invalidate = true,
    undo_restore = true,
    number_hl_group = "VantageReview",
    strict = false,
  })
  local review = { buf = buf, id = id, note = note }
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

--- A Review's live range, read from its extmark: 1-based inclusive
--- `start_row, end_row`, or nil when the mark is gone or invalid (the code it
--- covered was deleted; a code undo can bring it back). The extmark owns the
--- range, so this is the only answer a reader needs — there is no second copy
--- to keep in sync when an edit moves or shrinks it.
---@param review vantage.Review
---@return integer? start_row
---@return integer? end_row
function M.range(review)
  if not vim.api.nvim_buf_is_valid(review.buf) then
    return nil, nil
  end
  local pos = vim.api.nvim_buf_get_extmark_by_id(review.buf, NS, review.id, { details = true })
  if #pos == 0 or pos[3].invalid then
    return nil, nil
  end
  local start_row = pos[1] + 1
  -- The end is the 0-based row of the line after the last covered one, which
  -- is that last line's 1-based number.
  local end_row = math.max(start_row, pos[3].end_row or pos[1])
  return start_row, end_row
end

--- How many Reviews are registered, valid or not. The list and send paths see
--- only valid ones (`M.collect`); a clear must reach the hidden ones too.
---@return integer
function M.count()
  local total = 0
  for _, by_id in pairs(registry) do
    for _ in pairs(by_id) do
      total = total + 1
    end
  end
  return total
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

--- Every valid Review, sorted by (buffer name, live start row). Entries whose
--- extmark no longer exists or is invalidated (its code was deleted) are
--- skipped — they leave the list and the send until a code undo restores them.
---@return vantage.Review[]
function M.collect()
  local rows = {}
  for buf, by_id in pairs(registry) do
    if vim.api.nvim_buf_is_valid(buf) then
      for _, review in pairs(by_id) do
        local start_row = M.range(review)
        if start_row then
          rows[#rows + 1] = {
            review = review,
            name = vim.api.nvim_buf_get_name(buf),
            start_row = start_row,
          }
        end
      end
    end
  end
  table.sort(rows, function(a, b)
    if a.name ~= b.name then
      return a.name < b.name
    end
    return a.start_row < b.start_row
  end)
  local out = {}
  for _, row in ipairs(rows) do
    out[#out + 1] = row.review
  end
  return out
end

-- ---------------------------------------------------------------------------
-- Visual emphasis (read/edit)
-- ---------------------------------------------------------------------------

--- Swap one review's range tint between the resting and active highlight,
--- keeping the range and the movement it was created with. Re-setting an
--- extmark with only a start position would turn it into a point mark and
--- change how later edits move it, so the full range and options are carried
--- over; an invalidated mark is left alone (its Review is not showing).
---@param buf integer
---@param id integer
---@param active boolean
local function set_active(buf, id, active)
  if not vim.api.nvim_buf_is_valid(buf) then
    return
  end
  local pos = vim.api.nvim_buf_get_extmark_by_id(buf, NS, id, { details = true })
  if #pos == 0 or pos[3].invalid then
    return
  end
  vim.api.nvim_buf_set_extmark(buf, NS, pos[1], pos[2], {
    id = id,
    end_row = pos[3].end_row,
    end_col = pos[3].end_col,
    right_gravity = pos[3].right_gravity,
    end_right_gravity = pos[3].end_right_gravity,
    invalidate = true,
    undo_restore = true,
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
  local start_row = M.range(review)
  if not start_row then
    return false
  end
  local win = vim.fn.bufwinid(review.buf)
  if win ~= -1 then
    vim.api.nvim_set_current_win(win)
  else
    vim.api.nvim_win_set_buf(0, review.buf)
  end
  local line = vim.api.nvim_buf_get_lines(review.buf, start_row - 1, start_row, false)[1]
  local _, first = line:find("%S")
  vim.api.nvim_win_set_cursor(0, { start_row, first and (first - 1) or 0 })
  return true
end

--- Open an editable scratch float. `<Esc>` reads the buffer, closes the window,
--- and commits the text; every policy decision belongs to the caller.
---@param opts { text: string, title: string, footer: string, insert?: boolean, on_commit: fun(note: string), on_close?: fun() }
local function open_float(opts)
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, vim.split(opts.text, "\n", { plain = true }))
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

--- The review's selected lines, with leading/trailing blank lines dropped.
---@param review vantage.Review
---@param start_row integer 1-based inclusive
---@param end_row integer 1-based inclusive
---@return string
local function code_text(review, start_row, end_row)
  local lines = vim.api.nvim_buf_get_lines(review.buf, start_row - 1, end_row, false)
  while #lines > 0 and lines[1]:find("^%s*$") do
    table.remove(lines, 1)
  end
  while #lines > 0 and lines[#lines]:find("^%s*$") do
    table.remove(lines)
  end
  return table.concat(lines, "\n")
end

--- One resolver per `reviews.item` placeholder. The keys *are* the vocabulary
--- `Util.interpolate` is given, so a name cannot be known without something to
--- resolve it. `start_row`/`end_row` are the Review's live 1-based range.
---@type table<string, fun(review: vantage.Review, cwd: string, tool: string?, start_row: integer, end_row: integer): string?>
FIELDS = {
  note = function(review)
    return review.note
  end,
  lines = function(review, cwd, tool, start_row, end_row)
    return Config.tool_reference(tool, cwd, vim.api.nvim_buf_get_name(review.buf), start_row, end_row)
  end,
  code = function(review, _, _, start_row, end_row)
    return code_text(review, start_row, end_row)
  end,
  file = function(review, cwd, tool)
    return Config.tool_reference(tool, cwd, vim.api.nvim_buf_get_name(review.buf))
  end,
  start = function(_, _, _, start_row)
    return tostring(start_row)
  end,
  ["end"] = function(_, _, _, _, end_row)
    return tostring(end_row)
  end,
}

--- Resolve one placeholder against a Review's live range, or nil when the
--- Review's range is gone (invalid) or the location has no reference.
---@param review vantage.Review
---@param name string
---@param cwd string
---@param tool? string the focused Tool's reference dialect; nil spells the default
---@return string?
local function field(review, name, cwd, tool)
  local start_row, end_row = M.range(review)
  if not start_row or not end_row then
    return nil
  end
  return FIELDS[name](review, cwd, tool, start_row, end_row)
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

--- Render one review through the configured `item` template in the caller's
--- context (a picker row and the send that follows it each spell their own).
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
