--- The :Vantage user command: subcommand dispatch.
local Annotation = require("vantage.annotation")
local Backend = require("vantage.backend")
local Client = require("vantage.client")
local Config = require("vantage.config")
local Picker = require("vantage.picker")
local Prompt = require("vantage.prompt")
local Select = require("vantage.select")
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
      "  :Vantage annotate             annotate a range (visual selection, or current line)",
      "  :Vantage annotate list        open the annotation picker",
      "  :Vantage annotate clear       clear every annotation",
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

--- The "+ new group" row of the creation wizard's Group stage.
local NEW_GROUP = "+ new group"

--- Prompt for a new Group name (insert-mode cmdline). Scheduled so a picker
--- window can finish closing before the cmdline opens.
---@param callback fun(group: string)
local function ask_new_group_name(callback)
  vim.schedule(function()
    local name = vim.trim(vim.fn.input({ prompt = "Group name: " }))
    if name ~= "" then
      callback(name)
    end
  end)
end

--- Pick a Group (or prompt a new-Group name) for a Tool, then create and
--- focus the Agent. Shared by the creation wizard's Tool step and by the Tool
--- rows at the tail of the Agent picker.
---@param tool_name string
local function create_with_tool(tool_name)
  local tool = Config.options.cli.tools[tool_name]
  if not tool then
    return
  end
  local cmd = table.concat(tool.cmd, " ")
  local picker = Picker.get()
  local function create(group)
    do_create(group, tool_name, cmd, Util.cwd())
  end
  local groups = Backend.get().groups()
  if #groups == 0 then
    ask_new_group_name(create)
    return
  end
  groups[#groups + 1] = NEW_GROUP
  picker.pick_plain(groups, { prompt = "Group: " }, function(group)
    if not group then
      return
    end
    if group == NEW_GROUP then
      ask_new_group_name(create)
    else
      create(group)
    end
  end)
end

--- The Agent-creation wizard: pick a Tool, then a Group (or "+ new group"),
--- then create and focus the Agent. Every step renders on the configured
--- Picker's own engine via `pick_plain`, so the flow never rides a foreign
--- global `vim.ui.select` override. With no Group yet, the Group step is
--- skipped and the new-Group name is prompted directly.
local function create_wizard()
  local tools = {}
  for name in pairs(Config.options.cli.tools) do
    tools[#tools + 1] = name
  end
  if #tools == 0 then
    Util.warn("no tools configured (cli.tools)")
    return
  end
  table.sort(tools)

  Picker.get().pick_plain(tools, { prompt = "Tool: " }, function(tool_name)
    if tool_name then
      create_with_tool(tool_name)
    end
  end)
end

--- Pick an Agent to focus, create a new one from a trailing Tool row, or
--- confirm the pinned `(focused)` row, which deliberately does nothing.
local function pick_or_new()
  local empty = Picker.get().pick_agent(Select.agent_spec(), function(choice)
    if choice.kind == "tool" then
      create_with_tool(choice.tool)
    elseif not choice.focused then
      Client.focus(choice.agent)
    end
  end)
  if empty then
    Util.warn("no agents and no tools configured (cli.tools)")
  end
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

--- Pick a prompt name through the Picker's plain-select method and send it to
--- the focused Agent. The current window is restored afterwards so the cursor
--- stays where it was (e.g. the terminal).
local function prompt_wizard()
  local names = {}
  local has_annotations = #Annotation.collect() > 0
  for name in pairs(Config.options.prompts) do
    if name == "{annotations}" and not has_annotations then
      -- hide the built-in {annotations} prompt while there is nothing to send
    else
      names[#names + 1] = name
    end
  end
  table.sort(names)
  local win = vim.api.nvim_get_current_win()
  local function restore()
    if vim.api.nvim_win_is_valid(win) then
      vim.api.nvim_set_current_win(win)
    end
  end
  Picker.get().pick_plain(names, { prompt = "Prompt: " }, function(name)
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
      local empty = Picker.get().pick_kill(Select.kill_spec(), function(target)
        Backend.get().kill(target)
      end)
      if empty then
        Util.warn("nothing to kill")
      end
      return
    end
    Backend.get().kill(remaining[1])
  elseif subcommand == "toggle" then
    M.toggle()
  elseif subcommand == "detach" then
    Client.detach()
  elseif subcommand == "prompt" then
    prompt_wizard()
  elseif subcommand == "annotate" then
    local action = remaining[1]
    if action == "list" then
      annotate_list()
    elseif action == "clear" then
      annotate_clear()
    elseif action == nil then
      annotate_add(args.line1, args.line2)
    else
      Util.warn(("unknown annotate action '%s'"):format(action))
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
  local subcommands = { "switch", "kill", "toggle", "detach", "prompt", "annotate", "status" }
  if cmdline:match("^%s*Vantage%s+annotate%s+%S*%s*$") then
    return vim.tbl_filter(function(s)
      return vim.startswith(s, arglead)
    end, { "list", "clear" })
  end
  if cmdline:match("^%s*Vantage%s*$") or cmdline:match("^%s*Vantage%s+%S*%s*$") then
    return vim.tbl_filter(function(s)
      return vim.startswith(s, arglead)
    end, subcommands)
  end
  return {}
end

return M
