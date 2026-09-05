--- The `:Vantage annotate` command and its sub-actions (add / list / clear):
--- notes anchored to line ranges, batched through {annotations}.
local Annotation = require("vantage.annotation")
local Config = require("vantage.config")
local Note = require("vantage.ui.note")
local Picker = require("vantage.picker")
local Select = require("vantage.select")
local Util = require("vantage.util")

local M = {}

--- Jump to the annotation's start line (first non-blank column).
---@param annotation vantage.Annotation
---@return boolean
local function jump_to_annotation(annotation)
  if not vim.api.nvim_buf_is_valid(annotation.buf) then
    return false
  end
  local win = vim.fn.bufwinid(annotation.buf)
  if win ~= -1 then
    vim.api.nvim_set_current_win(win)
  else
    vim.api.nvim_win_set_buf(0, annotation.buf)
  end
  local line = vim.api.nvim_buf_get_lines(annotation.buf, annotation.start_row - 1, annotation.start_row, false)[1]
    or ""
  local _, first = line:find("%S")
  vim.api.nvim_win_set_cursor(0, { annotation.start_row, first and (first - 1) or 0 })
  return true
end

--- The raw `nvim_open_win` style for the note float, translated from the
--- annotation config's user-facing "inherit" | "minimal".
---@return string?
local function note_style()
  return Config.options.annotations.float.style == "minimal" and "minimal" or nil
end

--- Open the annotation picker; selecting an annotation opens its note float.
local function annotate_list()
  local empty = Picker.get().pick_annotation(Select.annotation_spec(), function(annotation)
    if not jump_to_annotation(annotation) then
      return
    end
    Annotation.set_active(annotation.buf, annotation.id, true)
    local cwd = Select.focused_cwd()
    Note.open({
      text = annotation.note,
      title = ("Annotation %s"):format(Annotation.location(annotation, cwd)),
      footer = "<Esc> save · empty deletes",
      style = note_style(),
      on_commit = function(note)
        if note == "" then
          -- Empty note = delete, after confirmation; the note UI owns no policy.
          if vim.fn.confirm("Delete annotation?", "&Yes\n&No", 2) == 1 then
            Annotation.delete(annotation.buf, annotation.id)
          end
        else
          Annotation.edit(annotation.buf, annotation.id, note)
        end
      end,
      on_close = function()
        Annotation.set_active(annotation.buf, annotation.id, false)
      end,
    })
  end)
  if empty then
    Util.warn("no annotations — add one with :Vantage annotate")
  end
end

--- Add an annotation over the command's range (a visual selection, else the
--- current line), asking for the note in a float.
---@param line1 integer
---@param line2 integer
local function annotate_add(line1, line2)
  local buf = vim.api.nvim_get_current_buf()
  local name = vim.api.nvim_buf_get_name(buf)
  if name == nil or name == "" then
    Util.warn("annotations need a named buffer — save the file first")
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
    title = "New annotation",
    footer = "<Esc> save",
    style = note_style(),
    insert = true,
    on_commit = function(note)
      if note ~= "" then
        Annotation.add(buf, line1, line2, note)
      end
    end,
  })
end

--- Clear all annotations after a confirmation (built-in dialog, default No).
local function annotate_clear()
  if #Annotation.collect() == 0 then
    Util.warn("no annotations to clear")
    return
  end
  if vim.fn.confirm("Clear all annotations?", "&Yes\n&No", 2) == 1 then
    Annotation.clear()
  end
end

--- `:Vantage annotate [list|clear]`; bare `annotate` adds over the command's
--- range.
---@param action string?
---@param line1 integer
---@param line2 integer
function M.run(action, line1, line2)
  if action == "list" then
    annotate_list()
  elseif action == "clear" then
    annotate_clear()
  elseif action == nil then
    annotate_add(line1, line2)
  else
    Util.warn(("unknown annotate action '%s'"):format(action))
  end
end

return M
