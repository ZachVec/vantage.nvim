--- An editable note: a scratch buffer in a float. Esc commits the text through
--- `on_commit` and closes; there is no separate save or delete action, and no
--- policy — the caller's `on_commit` owns what empty/commit/close mean. Pure
--- UI: it depends on nothing but the Neovim runtime.
local M = {}

---@param opts vantage.NoteOpts
function M.open(opts)
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
  if opts.style then
    win_config.style = opts.style
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

  local function commit()
    local note = read_note()
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

return M
