--- The `:Vantage review` command and its sub-actions (add / list / clear):
--- notes anchored to line ranges, batched through {reviews}.
local Entries = require("vantage.frontend.entries")
local Picker = require("vantage.frontend.picker")
local Review = require("vantage.frontend.review")
local Util = require("vantage.util")

local M = {}

local PROMPT = Util.picker_prompt

--- Reviews, sorted by (buffer name, start row). May be empty.
---@return vantage.PickSpec
local function spec()
  return {
    prompt = PROMPT,
    many = false,
    preview = Entries.preview,
    items = function(emit, done)
      -- The list is a display, not a send: it spells every `{lines}` against
      -- Neovim's own cwd in the default dialect, so it needs no Focus and can
      -- differ from the reference a send to the focused Agent would produce.
      local cwd = Util.cwd()
      local items = {}
      for _, review in ipairs(Review.collect()) do
        items[#items + 1] = Entries.review(review, cwd, nil)
      end
      emit(items)
      done()
    end,
  }
end

--- Delete the Review the entry names. Returns true when the list may have
--- changed.
---@param entry vantage.picker.Entry
---@return boolean
local function delete_review(entry)
  ---@cast entry vantage.picker.ReviewEntry
  Review.delete(entry.review.buf, entry.review.id)
  return true
end

--- Open the review picker; selecting a review opens its editing float.
local function review_list()
  Picker.pick_fancy(spec(), {
    on_choices = function(entries)
      local entry = entries[1]
      ---@cast entry vantage.picker.ReviewEntry
      Review.edit(entry.review.buf, entry.review.id)
    end,
    commands = {
      {
        "<C-x>",
        function(ctx)
          return ctx.item ~= nil and delete_review(ctx.item)
        end,
        desc = "delete review",
      },
    },
  })
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
  Review.create(buf, line1, line2)
end

--- Clear all reviews after a confirmation (built-in dialog, default No).
local function review_clear()
  -- `count`, not `collect`: an invalidated Review is hidden from the list but
  -- is still registered, and a clear has to reach it.
  if Review.count() == 0 then
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
