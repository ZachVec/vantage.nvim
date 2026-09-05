--- The persistent :terminal that is Vantage's tmux client.
---
--- One terminal per nvim instance. On first focus the plugin creates a View and
--- attaches the terminal to it; later focuses re-target the same terminal
--- through the Backend (`retarget`: a window select within the View's Group, a
--- View relocation across Groups — the plugin knows the View session name, so
--- no pty round-trip and no client-registration race).
---
--- Toggle is lightweight: `hide` closes only the window and keeps the buffer +
--- tmux client + View alive; `show` re-opens the window on the same buffer.
--- `detach` (destroy) deletes the buffer, which detaches the client; the
--- client-detached hook then destroys the View.
local Backend = require("vantage.backend")
local Config = require("vantage.config")
local Util = require("vantage.util")

---@class vantage.Client
---@field job? integer terminal channel id
---@field buffer? integer
---@field window? integer
---@field view? string tmux View session name
---@field last_agent? vantage.Agent remembered across detach, for toggle re-open
local M = {
  job = nil,
  buffer = nil,
  window = nil,
  view = nil,
  last_agent = nil,
}

function M.reset()
  M.job, M.buffer, M.window, M.view = nil, nil, nil, nil
end

--- True if our View session still exists (i.e. the terminal is a live client).
---@return boolean
function M.is_attached()
  if not M.view or M.job == nil then
    return false
  end
  return Backend.get().has_session(M.view)
end

--- True if the terminal window is currently open (regardless of whether its
--- View is still alive).
---@return boolean
function M.is_open()
  return M.window ~= nil and vim.api.nvim_win_is_valid(M.window)
end

--- The last-focused Agent if it still exists, else nil.
---@return vantage.Agent?
function M.last_agent_alive()
  if not M.last_agent then
    return nil
  end
  for _, agent in ipairs(Backend.get().list()) do
    if agent.target == M.last_agent.target then
      return agent
    end
  end
  return nil
end

--- Detach the client and destroy the terminal buffer. The client-detached hook
--- then destroys the View (Agents keep running).
function M.detach()
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

local function configure_window()
  vim.wo[M.window].number = false
  vim.wo[M.window].relativenumber = false
  vim.wo[M.window].signcolumn = "no"
  vim.wo[M.window].statuscolumn = ""
  vim.wo[M.window].cursorline = false
end

--- Apply a single cli.win.keys entry to the terminal buffer.
---@param buffer integer
---@param keymap table
local function apply_key(buffer, keymap)
  local lhs, rhs = keymap[1], keymap[2]
  if not lhs or rhs == nil then
    Util.warn("keymap entry must be a 4-tuple { lhs, rhs, mode?, desc? }")
    return
  end
  local mode = keymap.mode or "n"
  if type(mode) == "table" then
    mode = table.concat(mode, "")
  end
  local modes = vim.split(mode, "", { plain = true })
  pcall(vim.keymap.set, modes, lhs, rhs, {
    buffer = buffer,
    desc = keymap.desc,
    silent = true,
    nowait = true,
  })
end

--- Apply cli.win.keys to the terminal buffer (buffer-local), at terminal
--- creation. Each entry is a 4-tuple { lhs, rhs, mode = "n", desc }; `rhs` is
--- passed verbatim to vim.keymap.set (a key sequence / <cmd> RHS or a Lua
--- function). mode may be "n" | "t" | "nt" (or a table of modes).
---@param buffer integer
function M.apply_keys(buffer)
  for _, keymap in ipairs(Config.options.cli.win.keys or {}) do
    apply_key(buffer, keymap)
  end
end

--- Open the terminal buffer full or in a split, per cli.win.layout.
---@param buffer integer
---@return integer window id
function M.open_win(buffer)
  local cfg = Config.options.cli.win
  if cfg.layout == "full" then
    -- A dedicated tab gives a normal (non-floating) window at the full editor
    -- size. We avoid a floating window on purpose: Neovim redraws the terminal
    -- cursor per-frame inside floats, which flickers on every agent TUI repaint.
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
    if width and width > 0 then
      vim.api.nvim_win_set_width(0, width)
    end
  else
    local height = cfg.split.height or 0
    if height and height > 0 then
      vim.api.nvim_win_set_height(0, height)
    end
  end
  return vim.api.nvim_get_current_win()
end

--- Hide the terminal window, keeping the buffer + tmux client + View alive.
function M.hide()
  if not M.is_open() then
    return
  end
  if #vim.api.nvim_list_wins() == 1 then
    -- last window: swap in an empty buffer instead of closing it
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
  if M.is_attached() then
    return M.show()
  end
  return false
end

--- Open a fresh terminal attached to the given View session.
---@param view string tmux View session name
---@return boolean
function M.attach_terminal(view)
  M.detach()

  local buffer = vim.api.nvim_create_buf(false, true)
  vim.bo[buffer].bufhidden = "hide"
  vim.bo[buffer].swapfile = false
  vim.bo[buffer].filetype = "vantage_terminal"
  M.apply_keys(buffer)

  local window = M.open_win(buffer)
  M.buffer = buffer
  M.window = window
  M.view = view
  configure_window()

  local job = vim.fn.jobstart(Backend.get().client_command(view), { term = true })
  if job <= 0 then
    Util.notify("failed to start the terminal")
    M.detach()
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

--- Name the terminal buffer after the focused Agent's tool and its working
--- directory, so tabs and winbars show a meaningful title instead of an empty
--- scratch name.
local function retitle()
  local agent = M.last_agent
  if not agent or not M.buffer or not vim.api.nvim_buf_is_valid(M.buffer) then
    return
  end
  local title = agent.tool or agent.name or "vantage"
  if agent.cwd and agent.cwd ~= "" then
    title = title .. " · " .. agent.cwd
  end
  vim.api.nvim_buf_set_name(M.buffer, title)
end

--- Focus an Agent: re-target the existing terminal, or attach a new one.
---@param agent vantage.Agent
---@return boolean
function M.focus(agent)
  M.last_agent = agent
  local backend = Backend.get()
  backend.ensure_server()

  if M.is_attached() then
    local view = backend.retarget(M.view, agent.group, agent.target)
    if not view then
      return false
    end
    M.view = view
    retitle()
    return M.show()
  end

  local view = backend.attach(agent.group, agent.target)
  if not view then
    return false
  end
  local ok = M.attach_terminal(view)
  retitle()
  return ok
end

--- Re-target the existing terminal to a different Agent, without showing or
--- hiding it. Switching only re-points: with no live terminal it fails and
--- leaves materialization to `focus` (toggle's open path). Re-targeting into
--- another Group relocates the View to that Group (the Backend returns the
--- View the client ends on, possibly a fresh one; the old View is destroyed).
---@param agent vantage.Agent
---@return boolean
function M.retarget(agent)
  if not M.is_attached() then
    return false
  end
  M.last_agent = agent
  local view = Backend.get().retarget(M.view, agent.group, agent.target)
  if not view then
    return false
  end
  M.view = view
  retitle()
  return true
end

return M
