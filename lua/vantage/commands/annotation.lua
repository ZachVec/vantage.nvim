--- The `:Vantage annotate` command and its sub-actions (add / list / clear):
--- notes anchored to line ranges, batched through {annotations}.
local Annotation = require("vantage.annotation")
local Config = require("vantage.config")
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

--- Open an editable note float (normal mode). `keys.exit` commits the note and
--- closes (an empty note deletes after confirmation); an optional `keys.delete`
--- deletes directly. `on_close` runs when the float closes (BufWipeout).
---@param opts { text: string, on_commit: fun(note: string), on_delete?: fun(), on_close?: fun(), title?: string, footer?: string, insert?: boolean }
local function open_note_float(opts)
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, vim.split(opts.text or "", "\n", { plain = true }))
  vim.bo[buf].bufhidden = "wipe"

  local width = math.max(40, math.min(80, math.floor(vim.o.columns * 0.5)))
  local height = math.max(8, math.min(20, math.floor(vim.o.lines * 0.5)))
  -- `style = "minimal"` forces every window option off (no line numbers, no
  -- cursorline, …), which reads as a read-only dialog. By default
  -- (`annotations.float.style` = "inherit") no style key is passed, so the
  -- float takes the options of the window it opens from — like a normal split,
  -- line numbers and friends follow the user's config and the float reads as
  -- an editable buffer. `"minimal"` stays available for the clean dialog look.
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
  if Config.options.annotations.float.style == "minimal" then
    win_config.style = "minimal"
  end
  local win = vim.api.nvim_open_win(buf, true, win_config)
  if opts.insert then
    vim.cmd("startinsert")
  end

  local function read_note()
    local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
    while #lines > 0 and lines[#lines]:find("^%s*$") do
      table.remove(lines)
    end
    return table.concat(lines, "\n")
  end

  local function close()
    if vim.api.nvim_win_is_valid(win) then
      pcall(vim.api.nvim_win_close, win, true)
    end
  end

  local function confirm_delete()
    -- Built-in dialog: light two-choice confirmations stay off the pickers.
    if vim.fn.confirm("Delete annotation?", "&Yes\n&No", 2) == 1 and opts.on_delete then
      opts.on_delete()
    end
  end

  local function finish()
    local note = read_note()
    close()
    if note == "" then
      if opts.on_delete then
        confirm_delete()
      end
    else
      opts.on_commit(note)
    end
  end

  local keys = Config.options.annotations.keys
  vim.keymap.set("n", keys.exit, finish, { buffer = buf, nowait = true, desc = "commit annotation note" })
  if keys.delete then
    vim.keymap.set("n", keys.delete, function()
      close()
      confirm_delete()
    end, { buffer = buf, nowait = true, desc = "delete annotation" })
  end

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

--- Open the annotation picker; selecting an annotation opens its note float.
local function annotate_list()
  local empty = Picker.get().pick_annotation(Select.annotation_spec(), function(annotation)
    if not jump_to_annotation(annotation) then
      return
    end
    Annotation.set_active(annotation.buf, annotation.id, true)
    local keys = Config.options.annotations.keys
    local cwd = Select.focused_cwd()
    open_note_float({
      text = annotation.note,
      title = ("Annotation %s"):format(Annotation.location(annotation, cwd)),
      footer = ("%s save · empty deletes"):format(keys.exit),
      on_commit = function(note)
        Annotation.edit(annotation.buf, annotation.id, note)
      end,
      on_delete = function()
        Annotation.delete(annotation.buf, annotation.id)
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
  open_note_float({
    text = "",
    title = "New annotation",
    footer = ("%s save"):format(Config.options.annotations.keys.exit),
    insert = true,
    on_commit = function(note)
      Annotation.add(buf, line1, line2, note)
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
