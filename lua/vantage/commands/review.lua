--- The `:Vantage review` command and its sub-actions (add / list / clear):
--- notes anchored to line ranges, batched through {reviews}.
local Config = require("vantage.config")
local Note = require("vantage.frontend.note")
local Picker = require("vantage.frontend.picker")
local Review = require("vantage.frontend.review")
local Util = require("vantage.util")

local M = {}

local PROMPT = Util.picker_prompt

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

--- The raw `nvim_open_win` style for the note float, translated from the
--- review config's user-facing "inherit" | "minimal".
---@return string?
local function note_style()
  return Config.options.reviews.float.style == "minimal" and "minimal" or nil
end

--- Open a review's note float: jump to its range, mark it active, and edit
--- its note (an empty commit deletes it).
---@param review vantage.Review
local function open_note(review)
  if not jump_to_review(review) then
    return
  end
  Review.set_active(review.buf, review.id, true)
  local cwd = Util.cwd()
  Note.open({
    text = review.note,
    title = ("Review %s"):format(Review.location(review, cwd)),
    footer = "<Esc> save · empty deletes",
    style = note_style(),
    on_commit = function(note)
      if note == "" then
        -- Empty note = delete, after confirmation; the note UI owns no policy.
        if vim.fn.confirm("Delete review?", "&Yes\n&No", 2) == 1 then
          Review.delete(review.buf, review.id)
        end
      else
        Review.edit(review.buf, review.id, note)
      end
    end,
    on_close = function()
      Review.set_active(review.buf, review.id, false)
    end,
  })
end

--- A Review row. The flow opens the note float from the row's data; the row
--- itself only formats, previews, and deletes.
---@param review vantage.Review
---@param cwd string
---@return table
local function review_row(review, cwd)
  local path = Util.tilde(vim.api.nvim_buf_get_name(review.buf) or "")
  local first = (vim.split(review.note, "\n", { plain = true })[1] or ""):gsub("%s+", " ")
  return {
    review = review,
    format = function()
      return ("%s:L%d-%d  %s"):format(path, review.start_row, review.end_row, first)
    end,
    preview = function()
      return vim.split(Review.render_item(review, cwd), "\n")
    end,
    delete = function()
      Review.delete(review.buf, review.id)
      return true
    end,
  }
end

--- Reviews, sorted by (buffer name, start row). May be empty.
---@return vantage.PickSpec
local function spec()
  return {
    prompt = PROMPT,
    items_provider = function()
      local cwd = Util.cwd()
      local items = {}
      for _, review in ipairs(Review.collect()) do
        items[#items + 1] = review_row(review, cwd)
      end
      return items
    end,
  }
end

--- Open the review picker; selecting a review opens its note float.
local function review_list()
  local empty = Picker.get().pick_review(spec(), function(entry)
    open_note(entry.review)
  end)
  if empty then
    Util.warn("no reviews — add one with :Vantage review")
  end
end

--- Add a review over the command's range (a visual selection, else the
--- current line), asking for the note in a float.
---@param line1 integer
---@param line2 integer
local function review_add(line1, line2)
  local buf = vim.api.nvim_get_current_buf()
  local name = vim.api.nvim_buf_get_name(buf)
  if name == nil or name == "" then
    Util.warn("reviews need a named buffer — save the file first")
    return
  end
  -- A `<cmd>` mapping keeps Visual mode active, so the '< and '> marks are not
  -- set yet; exit Visual mode first, then read them for the range.
  if vim.api.nvim_get_mode().mode:match("[vV\22]") then
    vim.cmd("normal! \27")
    line1 = vim.fn.line("'<")
    line2 = vim.fn.line("'>")
    if line1 > line2 then
      line1, line2 = line2, line1
    end
  end
  Note.open({
    text = "",
    title = "New review",
    footer = "<Esc> save",
    style = note_style(),
    insert = true,
    on_commit = function(note)
      if note ~= "" then
        Review.add(buf, line1, line2, note)
      end
    end,
  })
end

--- Clear all reviews after a confirmation (built-in dialog, default No).
local function review_clear()
  if #Review.collect() == 0 then
    Util.warn("no reviews to clear")
    return
  end
  if vim.fn.confirm("Clear all reviews?", "&Yes\n&No", 2) == 1 then
    Review.clear()
  end
end

--- `:Vantage review [list|clear]`; bare `review` adds over the command's
--- range.
---@param action string?
---@param line1 integer
---@param line2 integer
function M.run(action, line1, line2)
  if action == "list" then
    review_list()
  elseif action == "clear" then
    review_clear()
  elseif action == nil then
    review_add(line1, line2)
  else
    Util.warn(("unknown review action '%s'"):format(action))
  end
end

return M
