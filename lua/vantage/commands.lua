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

local function create_wizard()
  Select.pick_tool(function(tool_name)
    local tool = Config.options.cli.tools[tool_name]
    Select.pick_group(function(group)
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

--- Apply the tool format hook and type the text into the Agent's input (no
--- auto-submit). Returns false when the format hook dropped the text.
---@param agent vantage.Agent
---@param name string prompt name, for warnings
---@param text string
---@return boolean
local function send_text(agent, name, text)
  local tool = agent.tool and Config.options.cli.tools[agent.tool]
  if tool and tool.format then
    text = tool.format(text)
    if text == nil or text == "" then
      Util.warn(("prompt '%s' dropped by its format hook"):format(name))
      return false
    end
  end
  Backend.get().send_keys(agent.target, text)
  return true
end

--- Run a built-in Action: open its picker and type the selected references.
--- Scheduled so the prompt-name selector can finish closing first.
---@param name string "files" | "buffers"
---@param agent vantage.Agent
local function send_action(name, agent)
  local pick = name == "files" and Picker.get().pick_files or Picker.get().pick_buffers
  if type(pick) ~= "function" then
    return -- picker doesn't support the Action (native, or unavailable)
  end
  vim.schedule(function()
    pick(function(paths)
      if #paths == 0 then
        return -- empty selection: no-op
      end
      send_text(agent, name, Prompt.render_paths(agent, paths))
    end)
  end)
end

--- Render a Template against the focused Agent's context and type it in, or run
--- a built-in Action. Returns true when an Action opened a picker (async).
---@param name string
---@return boolean?
local function send_prompt(name)
  local agent = Client.last_agent_alive()
  if not agent then
    Util.warn("no focused agent — use :Vantage switch or toggle first")
    return
  end
  if Prompt.actions[name] then
    send_action(name, agent)
    return true
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
  if send_text(agent, name, text)
    and template:find("{annotations}", 1, true)
    and Config.options.annotations.clear_on_send then
    Annotation.clear()
  end
end

--- Pick a Prompt (Template or Action) name via vim.ui.select and send it. The
--- window is restored afterwards for Templates; Actions open their own picker
--- and manage focus themselves.
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
  -- Built-in Actions need the files/buffers pickers (fzf-lua/snacks), so they
  -- are offered only when the resolved Picker implements them.
  if type(Picker.get().pick_files) == "function" then
    for name in pairs(Prompt.actions) do
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
  vim.ui.select(names, { prompt = "Prompt: " }, function(name)
    if name and send_prompt(name) then
      return -- Action opened a picker: let it own focus
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
  local win = vim.api.nvim_open_win(buf, true, {
    relative = "editor",
    row = math.floor((vim.o.lines - height) / 2),
    col = math.floor((vim.o.columns - width) / 2),
    width = width,
    height = height,
    style = "minimal",
    border = "rounded",
    title = opts.title,
    footer = opts.footer,
  })
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
    vim.ui.select({ "Yes", "No" }, { prompt = "Delete annotation? " }, function(choice)
      if choice == "Yes" and opts.on_delete then
        opts.on_delete()
      end
    end)
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
  Picker.get().pick_annotation({
    select = function(annotation)
      if not jump_to_annotation(annotation) then
        return
      end
      Annotation.set_active(annotation.buf, annotation.id, true)
      local keys = Config.options.annotations.keys
      local agent = Client.last_agent_alive()
      local cwd = agent and agent.cwd or Util.cwd()
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
    end,
    delete = function(annotation)
      Annotation.delete(annotation.buf, annotation.id)
    end,
  })
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

--- Clear all annotations after a confirmation.
local function annotate_clear()
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
