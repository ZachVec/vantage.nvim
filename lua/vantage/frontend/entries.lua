--- The Picker's entries: one vocabulary for everything a flow can offer a
--- pick. An entry is the text the implementation renders, the flow's own name
--- for it, the fields the flow carries, and the preview — the one
--- lazily-computed part: implementations call it only for the highlighted
--- entry, so a pane capture or a file read happens per highlight, never per
--- entry. Each builder binds the preview for its kind; the functions are
--- module-level, so no entry carries a closure of its own.
local Backend = require("vantage.backend")
local Review = require("vantage.frontend.review")
local Util = require("vantage.util")

local M = {}

--- Lines a file preview reads.
local PREVIEW_LINES = 200

---@class vantage.picker.AgentEntry : vantage.picker.Entry
---@field kind "focused"|"agent"
---@field agent vantage.Agent

---@class vantage.picker.ToolEntry : vantage.picker.Entry
---@field kind "tool"
---@field name string

---@class vantage.picker.GroupEntry : vantage.picker.Entry
---@field kind "group"
---@field group string

---@class vantage.picker.FileEntry : vantage.picker.Entry
---@field kind "file"
---@field path string

---@class vantage.picker.BufferEntry : vantage.picker.Entry
---@field kind "buffer"
---@field buf integer
---@field path string

---@class vantage.picker.ReviewEntry : vantage.picker.Entry
---@field kind "review"
---@field review vantage.Review
---@field cwd string
---@field tool? string

---@alias vantage.picker.PathEntry vantage.picker.FileEntry|vantage.picker.BufferEntry
--- the two entry kinds whose reference source is `path`

--- Entry glyphs (Nerd Fonts; nf-fa-toggle_on and nf-fa-toggle_off): a running
--- Agent entry leads with the "on" icon, a Tool entry (which creates a new
--- Agent) with the "off" one. Built with nr2char rather than literal escapes
--- (Lua 5.1 has no \u{…}). Two spaces keep the icon clear of the text.
local AGENT_ICON = vim.fn.nr2char(0xF205) .. "  "
local TOOL_ICON = vim.fn.nr2char(0xF204) .. "  "

--- The first PREVIEW_LINES lines of an entry's file, or nil when it cannot be
--- read. A file entry previews this; a buffer entry falls back to it when its
--- buffer is gone.
---@param entry vantage.picker.PathEntry
---@return string[]?
local function file_preview(entry)
  local ok, lines = pcall(vim.fn.readfile, entry.path, "", PREVIEW_LINES)
  if not ok or type(lines) ~= "table" then
    return nil
  end
  return lines
end

--- An Agent's pane, or the Driver's reason as the preview when it fails.
---@param entry vantage.picker.AgentEntry
---@return string[]?
local function agent_preview(entry)
  local lines, err = Backend.capture(entry.agent)
  if lines == nil then
    return { err or "failed to capture agent" }
  end
  return lines
end

---@return string[]?
local function none()
  return nil
end

--- A buffer's live lines, falling back to its file when the buffer is gone.
---@param entry vantage.picker.BufferEntry
---@return string[]?
local function buffer_preview(entry)
  if not vim.api.nvim_buf_is_valid(entry.buf) then
    return file_preview(entry)
  end
  local count = vim.api.nvim_buf_line_count(entry.buf)
  return vim.api.nvim_buf_get_lines(entry.buf, 0, math.min(count, PREVIEW_LINES), false)
end

---@param entry vantage.picker.ReviewEntry
---@return string[]?
local function review_preview(entry)
  return vim.split(Review.render_item(entry.review, entry.cwd, entry.tool), "\n")
end

--- An Agent entry. The pinned Focus entry carries `kind = "focused"`.
---@param agent vantage.Agent
---@param focused? boolean this entry is the pinned Focus
---@return vantage.picker.AgentEntry
function M.agent(agent, focused)
  local text = AGENT_ICON .. ("%s · %s · %s"):format(agent.tool, agent.group, Util.tilde(agent.cwd))
  return {
    kind = focused and "focused" or "agent",
    text = focused and (text .. " (focused)") or text,
    agent = agent,
    preview = agent_preview,
  }
end

--- A Tool entry: choosing it creates a new Agent.
---@param name string
---@return vantage.picker.ToolEntry
function M.tool(name)
  return { kind = "tool", text = TOOL_ICON .. name, name = name, preview = none }
end

--- A Group entry.
---@param group string
---@return vantage.picker.GroupEntry
function M.group(group)
  return { kind = "group", text = ("group %s"):format(group), group = group, preview = none }
end

--- A file entry: the reference source is the absolute path.
---@param path string absolute file path
---@param cwd string relativization base (the focused Agent's cwd)
---@return vantage.picker.FileEntry
function M.file(path, cwd)
  return { kind = "file", text = Util.relpath(cwd, path), path = path, preview = file_preview }
end

--- A buffer entry. A modified buffer's on-disk content is stale; the marker
--- keeps that visible without leaking into the reference text.
---@param buf integer
---@param path string absolute file path
---@param cwd string relativization base
---@param modified boolean
---@return vantage.picker.BufferEntry
function M.buffer(buf, path, cwd, modified)
  local name = Util.relpath(cwd, path)
  return {
    kind = "buffer",
    text = modified and (name .. " [+]") or name,
    buf = buf,
    path = path,
    preview = buffer_preview,
  }
end

--- A Review entry: the flow opens the note float from the entry's data. The
--- entry is a display of the Review, not a second spelling of it:
--- `Review.location` spells its `{lines}` reference through the one owner, and
--- the note's first line follows. The preview renders exactly what a
--- `{reviews}` send would produce.
---@param review vantage.Review
---@param cwd string relativization base (the Focus's Cwd, or Neovim's cwd)
---@param tool? string the focused Tool's reference dialect; nil spells the default
---@return vantage.picker.ReviewEntry
function M.review(review, cwd, tool)
  local lines = Review.location(review, cwd, tool)
  if lines == "" then
    -- The Tool's hook declined the reference. The entry still has to name the
    -- Review, so it falls back to the default dialect; the preview keeps the
    -- honest answer a send would give.
    lines = Review.location(review, cwd, nil)
  end
  local first = (vim.split(review.note, "\n", { plain = true })[1] or ""):gsub("%s+", " ")
  return {
    kind = "review",
    text = lines .. (first ~= "" and ("  " .. first) or ""),
    review = review,
    cwd = cwd,
    tool = tool,
    preview = review_preview,
  }
end

return M
