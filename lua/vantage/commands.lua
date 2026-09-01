--- The :Vantage user command: subcommand dispatch.
local Annotation = require("vantage.annotation")
local Backend = require("vantage.backend")
local Client = require("vantage.client")
local Config = require("vantage.config")
local Picker = require("vantage.picker")
local Prompt = require("vantage.prompt")
local Util = require("vantage.util")

local M = {}

local function usage()
  vim.notify(
    table.concat({
      "Vantage — coding-agent manager",
      "",
      "  :Vantage switch [<@N>]       focus an Agent (interactive if no arg)",
      "  :Vantage kill [<group|@N>]   kill a Group or Agent (interactive if no arg)",
      "  :Vantage toggle              hide/show the terminal (creates if empty)",
      "  :Vantage detach              detach the client (kills the View; Agents survive)",
      "  :Vantage prompt              pick a prompt and type it into the focused Agent",
      "  :Vantage annotation <action> annotate ranges (add|list|edit|delete|clear)",
      "  :Vantage status              show clients + sessions",
    }, "\n"),
    vim.log.levels.INFO
  )
end

---@param target string
---@return vantage.Agent?
local function find_agent(target)
  for _, agent in ipairs(Backend.get().list()) do
    if agent.target == target then
      return agent
    end
  end
end

---@param group string
---@param tool_name string
---@param cmd string
---@param cwd string
local function do_create(group, tool_name, cmd, cwd)
  local agent = Backend.get().create({ group = group, cmd = cmd, cwd = cwd, tool = tool_name })
  if agent then
    Client.focus(agent)
  end
end

local function create_wizard()
  Picker.get().pick_tool(function(tool_name)
    local tool = Config.options.cli.tools[tool_name]
    Picker.get().pick_group(function(group)
      do_create(group, tool_name, table.concat(tool.cmd, " "), Util.cwd())
    end)
  end)
end

--- Pick an Agent, or create a new one via the "new" entry in the picker.
local function pick_or_new()
  Picker.get().pick_agent(function(choice)
    if choice.kind == "new" then
      create_wizard()
    else
      Client.focus(choice.agent)
    end
  end)
end

--- Render a prompt against the focused Agent's context and type it into the
--- Agent's input (no auto-submit).
---@param name string
local function send_prompt(name)
  local agent = Client.last_agent_alive()
  if not agent then
    Util.warn("no focused agent — use :Vantage switch or toggle first")
    return
  end
  local template = Config.options.prompts[name]
  if template == nil then
    Util.warn(("no such prompt '%s'"):format(name))
    return
  end
  local text, failed = Prompt.render(template, Prompt.context(agent))
  if text == nil then
    Util.warn(("prompt '%s' skipped: {%s} resolved empty"):format(name, failed))
    return
  end
  local tool = agent.tool and Config.options.cli.tools[agent.tool]
  if tool and tool.format then
    text = tool.format(text)
    if text == nil or text == "" then
      Util.warn(("prompt '%s' dropped by its format hook"):format(name))
      return
    end
  end
  Backend.get().send_keys(agent.target, text)
  if template:find("{annotations}", 1, true) and Config.options.annotations.clear_on_send then
    Annotation.clear()
  end
end

--- Pick a prompt name via vim.ui.select (no preview, so the pluggable Picker is
--- not used) and send it to the focused Agent. The current window is restored
--- afterwards so the cursor stays where it was (e.g. the terminal).
local function prompt_wizard()
  local names = {}
  for name in pairs(Config.options.prompts) do
    names[#names + 1] = name
  end
  table.sort(names)
  local win = vim.api.nvim_get_current_win()
  local function restore()
    if vim.api.nvim_win_is_valid(win) then
      vim.api.nvim_set_current_win(win)
    end
  end
  vim.ui.select(names, { prompt = "Prompt: " }, function(name)
    if name then
      send_prompt(name)
    end
    restore()
    vim.schedule(restore)
  end)
end

-- ---------------------------------------------------------------------------
-- Annotations: notes anchored to line ranges, batched through {annotations}
-- ---------------------------------------------------------------------------

--- A picker label: `~path:L<start>-<end> <note-first-line>`.
---@param annotation vantage.Annotation
---@return string
local function annotation_label(annotation)
  local path = Util.tilde(vim.api.nvim_buf_get_name(annotation.buf) or "")
  local first = (vim.split(annotation.note, "\n", { plain = true })[1] or ""):gsub("%s+", " ")
  return ("%s:L%d-%d  %s"):format(path, annotation.start_row, annotation.end_row, first)
end

--- Pick an annotation via vim.ui.select and hand it to `on_choice`. Like
--- `prompt_wizard`, this bypasses the pluggable Picker: there is nothing to
--- preview, so `vim.ui.select` (and any global override) is the right surface.
---@param on_choice fun(annotation: vantage.Annotation)
local function pick_annotation(on_choice)
  local annotations = Annotation.collect()
  if #annotations == 0 then
    Util.warn("no annotations — add one with :Vantage annotation add")
    return
  end
  local items = {}
  for i, annotation in ipairs(annotations) do
    items[i] = annotation_label(annotation)
  end
  vim.ui.select(items, { prompt = "Annotation: " }, function(choice)
    if choice == nil then
      return
    end
    local annotation = annotations[vim.fn.index(items, choice) + 1]
    if annotation then
      on_choice(annotation)
    end
  end)
end

--- Focus the annotation's buffer and jump to its start line (first non-blank
--- column), and emphasize its range.
---@param annotation vantage.Annotation
---@return integer? the column jumped to (0-based), or nil on failure
local function jump_to_annotation(annotation)
  if not vim.api.nvim_buf_is_valid(annotation.buf) then
    return nil
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
  local col = first and (first - 1) or 0
  vim.api.nvim_win_set_cursor(0, { annotation.start_row, col })
  Annotation.set_active(annotation.buf, annotation.id, true)
  return col
end

--- Show an annotation's note in a floating window; the range tint reverts when
--- the window closes. Like `K` hover, the window is non-focusable and closes as
--- soon as the cursor moves, insert mode is entered, or the buffer is left.
---@param annotation vantage.Annotation
local function show_annotation(annotation)
  local target_col = jump_to_annotation(annotation)
  if target_col == nil then
    return
  end
  local buf = vim.api.nvim_create_buf(false, true)
  local lines = vim.split(annotation.note, "\n", { plain = true })
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].bufhidden = "wipe"
  vim.bo[buf].modifiable = false

  local max_len = 0
  for _, line in ipairs(lines) do
    max_len = math.max(max_len, #line)
  end
  local width = math.max(20, math.min(max_len + 2, math.floor(vim.o.columns * 0.6)))
  local height = math.max(3, math.min(#lines + 2, math.floor(vim.o.lines * 0.5)))

  local win = vim.api.nvim_open_win(buf, false, {
    relative = "cursor",
    row = -height - 1, -- above the cursor (a negative row is above)
    col = 0,
    width = width,
    height = height,
    focusable = false,
    style = "minimal",
    border = "rounded",
  })

  local augroup = vim.api.nvim_create_augroup("VantageAnnotationPreview", { clear = true })

  local function close()
    pcall(vim.api.nvim_del_augroup_by_id, augroup)
    if vim.api.nvim_win_is_valid(win) then
      pcall(vim.api.nvim_win_close, win, true)
    end
    Annotation.set_active(annotation.buf, annotation.id, false)
  end

  -- `jump_to_annotation` positioned the cursor at the annotation's start line;
  -- the deferred CursorMoved from that positioning must not close the preview,
  -- so close only once the cursor leaves that exact position.
  local target_row = annotation.start_row
  vim.api.nvim_create_autocmd("CursorMoved", {
    buffer = annotation.buf,
    group = augroup,
    callback = function()
      local cursor = vim.api.nvim_win_get_cursor(0)
      if cursor[1] ~= target_row or cursor[2] ~= target_col then
        close()
      end
    end,
  })
  vim.api.nvim_create_autocmd({ "InsertEnter", "BufLeave" }, {
    buffer = annotation.buf,
    group = augroup,
    callback = close,
  })
  vim.api.nvim_create_autocmd("BufWipeout", {
    buffer = buf,
    once = true,
    callback = function()
      Annotation.set_active(annotation.buf, annotation.id, false)
    end,
  })
end

--- Read free-text via native `input()` rather than the pluggable `vim.ui.input`,
--- so the prompt is always insert-mode — the same reason `picker/items.lua` uses
--- `input()` for the Group name. Returns the trimmed text, or "" when cancelled.
---@param prompt string
---@param default? string
---@return string
local function input_text(prompt, default)
  return vim.trim(vim.fn.input({ prompt = prompt, default = default }))
end

--- Add an annotation over the command's range (a visual selection, else the
--- current line) after asking for the note text.
---@param line1 integer
---@param line2 integer
local function annotation_add(line1, line2)
  local buf = vim.api.nvim_get_current_buf()
  local name = vim.api.nvim_buf_get_name(buf)
  if name == nil or name == "" then
    Util.warn("annotations need a named buffer — save the file first")
    return
  end
  local note = input_text("Annotation note: ")
  if note == "" then
    return
  end
  if Annotation.add(buf, line1, line2, note) == nil then
    Util.warn("failed to add annotation")
  end
end

--- Edit the note text of the chosen annotation.
local function annotation_edit()
  pick_annotation(function(annotation)
    if jump_to_annotation(annotation) == nil then
      return
    end
    local note = input_text("Edit annotation: ", annotation.note)
    Annotation.set_active(annotation.buf, annotation.id, false)
    if note ~= "" then
      Annotation.edit(annotation.buf, annotation.id, note)
    end
  end)
end

--- Delete the chosen annotation.
local function annotation_delete()
  pick_annotation(function(annotation)
    Annotation.delete(annotation.buf, annotation.id)
  end)
end

--- Clear all annotations after a confirmation.
local function annotation_clear()
  if #Annotation.collect() == 0 then
    Util.warn("no annotations to clear")
    return
  end
  vim.ui.select({ "Yes", "No" }, { prompt = "Clear all annotations? " }, function(choice)
    if choice == "Yes" then
      Annotation.clear()
    end
  end)
end

--- Hide/show the terminal (lightweight); with no live terminal, re-open to the
--- last Agent, create one if there are none, or pick otherwise.
function M.toggle()
  if Client.toggle() then
    return
  end
  local last_agent = Client.last_agent_alive()
  if last_agent then
    Client.focus(last_agent)
    return
  end
  if #Backend.get().list() == 0 then
    create_wizard()
    return
  end
  pick_or_new()
end

function M.run(args)
  local fargs = args.fargs or {}
  local subcommand = fargs[1]
  local remaining = {}
  for i = 2, #fargs do
    remaining[#remaining + 1] = fargs[i]
  end

  if subcommand == nil then
    -- no default subcommand: show help
    usage()
  elseif subcommand == "switch" then
    if #remaining == 0 then
      pick_or_new()
      return
    end
    local agent = find_agent(remaining[1])
    if agent then
      Client.focus(agent)
    else
      Util.warn(("no such agent '%s'"):format(remaining[1]))
    end
  elseif subcommand == "kill" then
    if #remaining == 0 then
      Picker.get().pick_kill(function(target)
        Backend.get().kill(target)
      end)
      return
    end
    Backend.get().kill(remaining[1])
  elseif subcommand == "toggle" then
    M.toggle()
  elseif subcommand == "detach" then
    Client.detach()
  elseif subcommand == "prompt" then
    prompt_wizard()
  elseif subcommand == "annotation" then
    local action = remaining[1] or "list"
    if action == "add" then
      annotation_add(args.line1, args.line2)
    elseif action == "list" then
      pick_annotation(show_annotation)
    elseif action == "edit" then
      annotation_edit()
    elseif action == "delete" then
      annotation_delete()
    elseif action == "clear" then
      annotation_clear()
    else
      Util.warn(("unknown annotation action '%s'"):format(action))
    end
  elseif subcommand == "status" then
    local status_info = Backend.get().status()
    local lines = { "sessions:" }
    for _, line in ipairs(status_info.sessions) do
      lines[#lines + 1] = "  " .. line
    end
    lines[#lines + 1] = "clients:"
    for _, line in ipairs(status_info.clients) do
      lines[#lines + 1] = "  " .. line
    end
    vim.notify(table.concat(lines, "\n"), vim.log.levels.INFO)
  else
    Util.warn(("unknown subcommand '%s'"):format(subcommand))
    usage()
  end
end

---@param arglead string
---@param cmdline string
---@return string[]
function M.complete(arglead, cmdline)
  local subcommands = { "switch", "kill", "toggle", "detach", "prompt", "annotation", "status" }
  if cmdline:match("^%s*Vantage%s+annotation%s+%S*%s*$") then
    return vim.tbl_filter(function(s)
      return vim.startswith(s, arglead)
    end, { "add", "list", "edit", "delete", "clear" })
  end
  if cmdline:match("^%s*Vantage%s*$") or cmdline:match("^%s*Vantage%s+%S*%s*$") then
    return vim.tbl_filter(function(s)
      return vim.startswith(s, arglead)
    end, subcommands)
  end
  return {}
end

return M
