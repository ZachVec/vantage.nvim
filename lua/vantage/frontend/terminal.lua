--- The single :terminal that is Vantage's display surface.
---
--- One terminal per nvim instance. `open(argv)` starts the attach client as
--- the terminal's job; the terminal's existence IS the attachment's existence
--- (the job is the attached client), so a `TermClose` closes the window,
--- deletes the buffer, and resets state. `hide` closes only the window and
--- keeps the buffer + client alive; `show` re-opens the same buffer.
local Config = require("vantage.config")
local Util = require("vantage.util")

---@class vantage.Terminal
---@field job? integer terminal channel id
---@field buffer? integer
---@field window? integer
local M = {
  job = nil,
  buffer = nil,
  window = nil,
}

function M.reset()
  M.job, M.buffer, M.window = nil, nil, nil
end

--- True if the terminal window is currently open.
---@return boolean
function M.is_open()
  return M.window ~= nil and vim.api.nvim_win_is_valid(M.window)
end

--- The terminal job's pid (the attached client's identity), or nil.
---@return integer?
function M.pid()
  if not M.job or M.job <= 0 then
    return nil
  end
  return vim.fn.jobpid(M.job)
end

local function configure_window()
  vim.wo[M.window].number = false
  vim.wo[M.window].relativenumber = false
  vim.wo[M.window].signcolumn = "no"
  vim.wo[M.window].statuscolumn = ""
  vim.wo[M.window].cursorline = false
end

--- Open the terminal buffer in a float, tab, or split, per cli.win.layout.
---@param buffer integer
---@return integer window id
function M.open_win(buffer)
  local cfg = Config.options.cli.win
  if cfg.layout == "float" then
    -- A centered, full-editor-size floating window. Floats render no
    -- statusline or winbar, so the view is a pure terminal — a normal
    -- window's statusline row cannot be removed per window while 'laststatus'
    -- >= 2. The float's per-frame terminal-cursor redraw can flicker on some
    -- Agent-TUI repaints; `full` (a dedicated tab) is the opt-out.
    local width = math.floor(vim.o.columns * (cfg.float.width or 0.9))
    local height = math.floor(vim.o.lines * (cfg.float.height or 0.9))
    width = math.max(width, 40)
    height = math.max(height, 10)
    local col = math.floor((vim.o.columns - width) / 2)
    local row = math.floor((vim.o.lines - height) / 2)
    local border = cfg.float.border
    if border == false then
      border = "none"
    end
    return vim.api.nvim_open_win(buffer, true, {
      relative = "editor",
      width = width,
      height = height,
      row = row,
      col = col,
      style = "minimal",
      border = border,
    })
  end

  if cfg.layout == "full" then
    vim.cmd("tab split")
    vim.api.nvim_win_set_buf(0, buffer)
    return vim.api.nvim_get_current_win()
  end

  local layout = cfg.layout
  if layout == "left" then
    vim.cmd("topleft vsplit")
  elseif layout == "right" then
    vim.cmd("botright vsplit")
  elseif layout == "top" then
    vim.cmd("aboveleft split")
  else
    vim.cmd("belowright split")
  end
  vim.api.nvim_win_set_buf(0, buffer)
  if layout == "left" or layout == "right" then
    local width = cfg.split.width or 0
    if width > 0 then
      vim.api.nvim_win_set_width(0, width)
    end
  else
    local height = cfg.split.height or 0
    if height > 0 then
      vim.api.nvim_win_set_height(0, height)
    end
  end
  return vim.api.nvim_get_current_win()
end

--- Hide the terminal window, keeping the buffer + client alive.
function M.hide()
  if not M.is_open() then
    return
  end
  if vim.api.nvim_win_get_config(M.window).relative ~= "" then
    -- floating window: close it directly. The `enew` fallback below is only
    -- for the last *tiled* window — a float can never be the session's only
    -- window, since Neovim refuses to close the last tiled window beneath it.
    pcall(vim.api.nvim_win_close, M.window, true)
  elseif #vim.api.nvim_list_wins() == 1 then
    vim.api.nvim_win_call(M.window, function()
      vim.cmd("enew")
    end)
  else
    pcall(vim.api.nvim_win_close, M.window, true)
  end
  M.window = nil
end

--- Show the terminal window (re-opening it if hidden), focus it, and enter
--- terminal (insert) mode.
---@return boolean
function M.show()
  if not M.is_open() then
    if not M.buffer or not vim.api.nvim_buf_is_valid(M.buffer) then
      return false
    end
    M.window = M.open_win(M.buffer)
    configure_window()
  end
  vim.api.nvim_set_current_win(M.window)
  vim.cmd("startinsert")
  return true
end

--- Hide if open, show if hidden. Returns false when there is no live terminal.
---@return boolean
function M.toggle()
  if M.is_open() then
    M.hide()
    return true
  end
  if M.buffer and vim.api.nvim_buf_is_valid(M.buffer) then
    return M.show()
  end
  return false
end

--- Destroy the terminal: close the window, stop the job (detaching the
--- client; Agents keep running), delete the buffer, and reset state.
function M.destroy()
  if M.window and vim.api.nvim_win_is_valid(M.window) then
    pcall(vim.api.nvim_win_close, M.window, true)
  end
  if M.job and M.job > 0 then
    pcall(vim.fn.jobstop, M.job)
    M.job = nil
  end
  if M.buffer and vim.api.nvim_buf_is_valid(M.buffer) then
    pcall(vim.api.nvim_buf_delete, M.buffer, { force = true })
  end
  M.reset()
end

--- Open a fresh terminal attached via `argv` (the Driver's attach command).
---@param argv string[]
---@return boolean
function M.open(argv)
  M.destroy()

  local buffer = vim.api.nvim_create_buf(false, true)
  vim.bo[buffer].bufhidden = "hide"
  vim.bo[buffer].swapfile = false
  vim.bo[buffer].filetype = "vantage_terminal"

  local window = M.open_win(buffer)
  M.buffer = buffer
  M.window = window
  configure_window()

  local job = vim.fn.jobstart(argv, { term = true })
  if job <= 0 then
    Util.notify("failed to start the terminal")
    M.destroy()
    return false
  end
  M.job = job

  vim.api.nvim_create_autocmd("TermClose", {
    buffer = buffer,
    callback = function()
      vim.schedule(function()
        if M.buffer ~= buffer then
          return -- superseded by a newer terminal
        end
        if vim.api.nvim_buf_is_valid(buffer) then
          pcall(vim.api.nvim_buf_delete, buffer, { force = true })
        end
        M.reset()
      end)
    end,
  })

  vim.cmd("startinsert")
  return true
end

return M
