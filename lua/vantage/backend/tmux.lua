--- tmux driver: pure multiplexer mapping over a private socket.
---
--- Domain model:
---   Group  = one tmux session group: a persistent Anchor owns the Agents.
---   Agent  = one single-pane window in the Anchor, marked with @agent-cmd.
---   View   = one transient grouped session per Terminal client; its current
---            window is independent from every other client's View.
local Config = require("vantage.config")
local Util = require("vantage.util")

local M = {}

--- Destroy a View when its client detaches. The Anchor is never marked
--- @vantage-view, so it survives and keeps Agents alive headless. The kill
--- must run in a separate tmux process: a direct kill from the hook context
--- does not take effect.
local CLIENT_DETACHED_HOOK =
  [[run-shell "if [ \"#{@vantage-view}\" = \"1\" ]; then tmux -S \"#{socket_path}\" kill-session -t \"#{session_name}\"; fi"]]

local function socket()
  return Config.options.backend_opts.tmux.socket
end

--- Resolve a tmux Driver resource from the plugin runtimepath. tmux runs
--- `#()` with the server's environment, where these files are not on PATH.
---@param name string
---@return string?
---@return string?
local function resource_path(name)
  local path = vim.api.nvim_get_runtime_file(("lua/vantage/backend/resources/tmux/%s"):format(name), false)[1]
  if not path then
    return nil, ("tmux driver resource '%s' not found"):format(name)
  end
  return path, nil
end

--- The argv every tmux invocation starts from: the binary plus the private
--- socket. M.attach hands this to the Terminal as well.
---@return string[]
local function tmux_argv(...)
  return { "tmux", "-L", socket(), ... }
end

--- Build a user-facing failure message from a failed tmux result, including
--- stderr when tmux supplied a reason.
---@param prefix string
---@param result { code: integer, stdout: string, stderr: string }
---@return string
local function fail_message(prefix, result)
  local detail = vim.trim(result.stderr or "")
  if detail == "" then
    return prefix
  end
  return ("%s: %s"):format(prefix, detail)
end

--- Run a tmux command and return a structured result, so callers that need
--- diagnostics can read `stdout`/`stderr` without every caller handling three
--- return values; a caller that needs only the exit code reads `.code`.
---@return { code: integer, stdout: string, stderr: string }
local function exec(...)
  local code, stdout, stderr = Util.run(tmux_argv(...))
  return { code = code, stdout = stdout, stderr = stderr }
end

--- List of non-empty lines, or {} plus the failure message on error.
---@return string[]
---@return string?
local function exec_lines(...)
  local result = exec(...)
  if result.code ~= 0 then
    return {}, fail_message("tmux command failed", result)
  end
  local lines = {}
  -- Do not trim: tmux -F output is tab-delimited and may carry a trailing
  -- empty field (e.g. @agent-state). Only drop empty/whitespace-only lines.
  for line in (result.stdout or ""):gmatch("[^\r\n]+") do
    if line:find("%S") then
      lines[#lines + 1] = line
    end
  end
  return lines, nil
end

--- True when tmux's `text` — a stderr, or an error message embedding one —
--- reports that its server/socket does not exist yet.
---@param text string
---@return boolean
local function missing_server(text)
  return text:find("no server running", 1, true) ~= nil or text:find("error connecting", 1, true) ~= nil
end

--- Apply the global (server-wide) config. Idempotent and cheap; only called
--- right after a `new-session` starts the server, exactly once per server
--- lifetime (L1: never re-checked afterwards, fail-and-warn on external kill).
---@return boolean
---@return string?
local function apply_global_config()
  local counts_path, resource_err = resource_path("counts.sh")
  if not counts_path then
    return false, resource_err
  end
  -- Per-Group State counts in the pane's top border: computed read-only per
  -- status tick by the driver's counts.sh inside a #() substitution — never
  -- stored; the command string embeds the expanded #{@agent-group}, so tmux
  -- dedupes it to one small process per Group per tick.
  local counts = ('#("%s" -L %s #{@agent-group})'):format(counts_path, socket())
  local settings = {
    { "set-hook", "-g", "client-detached", CLIENT_DETACHED_HOOK },
    { "set", "-g", "default-terminal", "tmux-256color" },
    { "set", "-g", "history-limit", "20000" },
    { "set", "-g", "focus-events", "on" },
    -- No tmux status line: the terminal is the raw agent prompt.
    { "set", "-g", "status", "off" },
    { "set", "-g", "status-interval", "1" },
    { "set", "-g", "pane-border-status", "top" },
    {
      "set",
      "-g",
      "pane-border-format",
      (" #{@agent-group} · #{@agent-tool} · #{@agent-cwd-tilde}%s "):format(counts),
    },
  }

  for _, setting in ipairs(settings) do
    local result = exec(setting[1], setting[2], setting[3], setting[4])
    if result.code ~= 0 then
      return false, fail_message(("failed to apply tmux setting '%s'"):format(setting[1]), result)
    end
  end
  return true, nil
end

--- Sessions belonging to a Group: the Anchor plus its Views.
---@param group string
---@return string[]?
---@return string?
local function group_sessions(group)
  local filter = "#{==:#{?#{session_group},#{session_group},#{session_name}}," .. group .. "}"
  local sessions, err = exec_lines("list-sessions", "-F", "#{session_name}", "-f", filter)
  if err then
    if missing_server(err) then
      return {}, nil
    end
    return nil, err
  end
  return sessions, nil
end

--- The session group of a session, falling back to its own name for an Anchor.
---@param session string
---@return string?
---@return string?
local function session_group(session)
  local result = exec("display", "-p", "-t", session, "#{?#{session_group},#{session_group},#{session_name}}")
  if result.code ~= 0 then
    return nil, fail_message(("can't read session group for '%s'"):format(session), result)
  end
  return vim.trim(result.stdout), nil
end

--- Kill a View this Driver created. Best-effort cleanup: the View of an
--- attachment whose client never started, and the abandoned View of a
--- cross-Group move.
---@param view string
---@return boolean
---@return string?
local function close_view(view)
  local result = exec("kill-session", "-t", view)
  if result.code ~= 0 then
    return false, fail_message(("can't kill view '%s'"):format(view), result)
  end
  return true, nil
end

--- Create a fresh View in a Group and point it at an Agent window.
---@param group string
---@param target string Agent window id (@N)
---@return string?
---@return string?
local function create_view(group, target)
  if exec("has-session", "-t", group).code ~= 0 then
    return nil, ("no such group '%s'"):format(group)
  end
  local result = exec("new-session", "-d", "-P", "-F", "#{session_name}", "-t", group)
  if result.code ~= 0 then
    return nil, fail_message(("failed to create a view for group '%s'"):format(group), result)
  end
  local view = vim.trim(result.stdout)
  if view == "" then
    return nil, ("failed to create a view for group '%s': tmux returned an empty session name"):format(group)
  end

  local mark = exec("set-option", "-t", view, "@vantage-view", "1")
  if mark.code ~= 0 then
    exec("kill-session", "-t", view)
    return nil, fail_message(("failed to mark view '%s'"):format(view), mark)
  end
  local select = exec("select-window", "-t", view .. ":" .. target)
  if select.code ~= 0 then
    exec("kill-session", "-t", view)
    return nil, fail_message(("failed to point view '%s' at %s"):format(view, target), select)
  end
  return view, nil
end

--- The client sitting on a View, by its tty. A View is created for exactly one
--- Terminal and destroyed when that client detaches, so its client is
--- unambiguous. An empty answer is a View with nobody on it: the state an
--- attachment is in between `attach` and its client starting.
---@param view string
---@return string? client the client's tty, or nil when the View has no client
---@return string?
local function view_client(view)
  local result = exec("display", "-p", "-t", view, "#{client_name}")
  if result.code ~= 0 then
    return nil, fail_message(("can't read the client of view '%s'"):format(view), result)
  end
  local client = vim.trim(result.stdout or "")
  if client == "" then
    return nil, nil
  end
  return client, nil
end

--- Move a client into a fresh View in the target Group.
---@param client string the client's tty
---@param group string
---@param target string Agent window id (@N)
---@return string?
---@return string?
local function move_client_to_view(client, group, target)
  local view, err = create_view(group, target)
  if not view then
    return nil, err
  end
  local switch = exec("switch-client", "-c", client, "-t", view)
  if switch.code ~= 0 then
    close_view(view)
    return nil, fail_message(("can't move client to group '%s'"):format(group), switch)
  end
  return view, nil
end

--- The numeric creation order carried by a tmux window id. This is the only
--- place tmux's `@N` format is interpreted.
---@param id string
---@return integer
local function window_seq(id)
  return tonumber(id:match("^@(%d+)$")) or 0
end

--- The one place an Agent record is spelled from raw multiplexer fields.
---@param group string
---@param id string Agent window id (@N)
---@param cmd string
---@param cwd string
---@param tool string
---@param state string empty when the window reports no State
---@return vantage.Agent
local function agent_record(group, id, cmd, cwd, tool, state)
  return {
    id = id,
    seq = window_seq(id),
    group = group,
    cmd = cmd,
    cwd = cwd,
    tool = tool,
    state = (state ~= "" and state) or nil,
  }
end

--- Report a failed Agent creation, rolling the partial Agent back first:
--- kill the Anchor when this call created it, otherwise just the window.
---@param primary string
---@param created_session boolean
---@param group string
---@param id string
---@return string
local function create_error(primary, created_session, group, id)
  local result
  if created_session then
    result = exec("kill-session", "-t", group)
  else
    result = exec("kill-window", "-t", id)
  end
  if result.code ~= 0 then
    return primary .. "; " .. fail_message("rollback failed", result)
  end
  return primary
end

--- Create an Agent in a Group, creating the Group if it does not exist. The
--- first creation of the server's lifetime starts it via new-session and
--- applies the global config immediately after. Metadata failures roll the
--- partial Agent back so callers never see a half-registered window.
---@param opts { group: string, cmd: string, cwd: string, tool: string }
---@return vantage.Agent?
---@return string?
function M.create(opts)
  local group_exists = exec("has-session", "-t", opts.group).code == 0
  local created_session = not group_exists
  local window_id = ""
  local result

  if group_exists then
    result = exec("new-window", "-d", "-P", "-F", "#{window_id}", "-t", opts.group, "-c", opts.cwd, opts.cmd)
  else
    result = exec("new-session", "-d", "-s", opts.group, "-c", opts.cwd, opts.cmd)
  end
  if result.code ~= 0 then
    return nil, fail_message(("failed to create agent in group '%s'"):format(opts.group), result)
  end

  if created_session then
    local config_ok, config_err = apply_global_config()
    if not config_ok then
      local reason = assert(config_err, "vantage: apply_global_config failed without a reason")
      return nil, create_error(reason, true, opts.group, "")
    end
    result = exec("display", "-p", "-t", opts.group, "#{window_id}")
    if result.code ~= 0 then
      local primary = fail_message(("failed to create agent in group '%s'"):format(opts.group), result)
      return nil, create_error(primary, true, opts.group, "")
    end
  end

  window_id = vim.trim(result.stdout)
  if window_id == "" then
    local primary = ("failed to create agent in group '%s': tmux returned an empty window id"):format(opts.group)
    return nil, create_error(primary, created_session, opts.group, window_id)
  end

  local metadata = {
    { "@agent-group", opts.group },
    { "@agent-cmd", opts.cmd },
    { "@agent-cwd", opts.cwd },
    -- Display form of the cwd for the pane border (static: an Agent's working
    -- directory does not change; tilde-izing once here avoids a runtime #()
    -- process in the border format).
    { "@agent-cwd-tilde", Util.tilde(opts.cwd) },
    { "@agent-tool", opts.tool },
    -- A fresh Agent starts idle; the lifecycle scripts replace it on the first
    -- transition (no backfill: only external tampering can leave it unset).
    { "@agent-state", "idle" },
  }
  for _, item in ipairs(metadata) do
    result = exec("set-window-option", "-t", window_id, item[1], item[2])
    if result.code ~= 0 then
      local primary = fail_message(("failed to mark agent window '%s'"):format(window_id), result)
      return nil, create_error(primary, created_session, opts.group, window_id)
    end
  end

  return agent_record(opts.group, window_id, opts.cmd, opts.cwd, opts.tool, "idle"), nil
end

--- Agent rows: six tab-delimited fields.
local AGENT_FMT = table.concat({
  "#{@agent-group}",
  "#{window_id}",
  "#{@agent-cmd}",
  "#{@agent-cwd}",
  "#{@agent-tool}",
  "#{@agent-state}",
}, "\t")

--- Focus rows: a View's current window id, then that window's Agent fields
--- (empty when the window is not an Agent). A session-targeted display resolves
--- both from the View alone, so a Focus read needs no client.
local VIEW_FOCUS_FMT = table.concat({
  "#{window_id}",
  "#{@agent-group}",
  "#{@agent-cmd}",
  "#{@agent-cwd}",
  "#{@agent-tool}",
  "#{@agent-state}",
}, "\t")

--- The live Agent inventory, in creation order. One multiplexer query; a
--- missing server reads as an empty inventory rather than an error.
---@return vantage.Agent[]?
---@return string?
function M.agents()
  local result = exec("list-windows", "-a", "-f", "#{@agent-cmd}", "-F", AGENT_FMT)
  if result.code ~= 0 then
    if missing_server(result.stderr) then
      return {}, nil
    end
    return nil, fail_message("failed to read vantage state", result)
  end

  local agents = {}
  local seen = {}
  for line in (result.stdout or ""):gmatch("[^\r\n]+") do
    local fields = vim.split(line, "\t", { plain = true })
    if #fields == 6 then
      local group, id, cmd, cwd, tool, state = fields[1], fields[2], fields[3], fields[4], fields[5], fields[6]
      if group ~= "" and id ~= "" and not seen[id] then
        seen[id] = true
        agents[#agents + 1] = agent_record(group, id, cmd, cwd, tool, state)
      end
    end
  end
  table.sort(agents, function(left, right)
    return left.seq < right.seq
  end)
  return agents, nil
end

--- The Agent a View's client displays: the Focus. One multiplexer query reads
--- the View's current window and that window's Agent fields together — a View
--- has exactly one client, and a grouped session's current window is that
--- client's, so no client lookup is involved. A window without Agent metadata
--- answers `nil, Config.FOCUS_NO_FOCUS`; a View that no longer exists, or a
--- server that is gone, answers `nil` plus the reason, because the
--- attachment's own identity is then missing.
---@param view string
---@return vantage.Agent?
---@return string?
local function view_focus(view)
  local result = exec("display", "-p", "-t", view, VIEW_FOCUS_FMT)
  if result.code ~= 0 then
    return nil, fail_message(("can't read view '%s'"):format(view), result)
  end
  -- Do not trim: the row is tab-delimited and may carry a trailing empty State.
  local line = (result.stdout or ""):match("^([^\r\n]*)") or ""
  local fields = vim.split(line, "\t", { plain = true })
  if #fields ~= 6 then
    return nil, ("can't read view '%s': unexpected output"):format(view)
  end
  local window, group = fields[1], fields[2]
  if group == "" then
    return nil, Config.FOCUS_NO_FOCUS
  end
  return agent_record(group, window, fields[3], fields[4], fields[5], fields[6]), nil
end

--- Create this Terminal's View and attach its client through `launch`: the View
--- exists first, `launch(argv)` starts the client, and a client that cannot
--- start takes the View back down with it, so a failed start leaves no session
--- behind. The returned Attachment holds its View privately and answers every
--- method from live state.
---@param agent vantage.Agent
---@param launch fun(argv: string[]): boolean, string?
---@return vantage.Attachment?
---@return string?
function M.attach(agent, launch)
  local view, err = create_view(agent.group, agent.id)
  if not view then
    return nil, err
  end

  local started, launch_err = launch(tmux_argv("attach-session", "-t", view))
  if not started then
    local cleanup_ok, cleanup_err = close_view(view)
    local reason = assert(launch_err, "vantage: attach launch failed without a reason")
    if not cleanup_ok then
      return nil, reason .. "; " .. (cleanup_err or "rollback failed")
    end
    return nil, reason
  end

  local attachment = {}

  --- The Agent this attachment's client currently displays.
  ---@return vantage.Agent?
  ---@return string?
  function attachment:focus()
    return view_focus(view)
  end

  --- Re-point this attachment's client to an Agent without touching any other
  --- client's View. A same-Group move selects the Agent's window in the current
  --- View; a cross-Group move needs the client itself, so it moves the client
  --- into a fresh View of the destination Group and abandons the old one. The
  --- handle adopts the new View before the old one is cleaned up, so a failed
  --- cleanup cannot leave it pointing where the client no longer is.
  ---@param other vantage.Agent
  ---@return boolean
  ---@return string?
  function attachment:retarget(other)
    local current_group, group_err = session_group(view)
    if group_err then
      return false, group_err
    end
    if current_group == other.group then
      local result = exec("select-window", "-t", view .. ":" .. other.id)
      if result.code ~= 0 then
        return false, fail_message(("can't switch to %s:%s"):format(view, other.id), result)
      end
      return true, nil
    end

    local client, client_err = view_client(view)
    if client_err then
      return false, client_err
    end
    if not client then
      return false, ("no client attached to view '%s'"):format(view)
    end
    local new_view, move_err = move_client_to_view(client, other.group, other.id)
    if not new_view then
      return false, move_err
    end
    local old_view = view
    view = new_view
    local cleanup = exec("kill-session", "-t", old_view)
    if cleanup.code ~= 0 then
      return false, fail_message(("switched but failed to clean old view '%s'"):format(old_view), cleanup)
    end
    return true, nil
  end

  return attachment, nil
end

--- Kill a single Agent's window.
---@param agent vantage.Agent
---@return boolean
---@return string?
function M.kill_agent(agent)
  local result = exec("kill-window", "-t", agent.id)
  if result.code ~= 0 then
    return false, fail_message(("can't kill agent '%s'"):format(agent.id), result)
  end
  return true, nil
end

--- Kill an entire Group: its Anchor and every View.
---@param group string
---@return boolean
---@return string?
function M.kill_group(group)
  local sessions, err = group_sessions(group)
  if not sessions then
    return false, err or ("failed to list group '%s'"):format(group)
  end
  if #sessions == 0 then
    return false, ("no such group '%s'"):format(group)
  end
  table.sort(sessions, function(left, right)
    if left == group then
      return false
    end
    if right == group then
      return true
    end
    return left < right
  end)
  for _, session in ipairs(sessions) do
    local result = exec("kill-session", "-t", session)
    if result.code ~= 0 then
      return false, fail_message(("can't kill group '%s'"):format(group), result)
    end
  end
  return true, nil
end

--- Paste text into an Agent's pane via bracketed paste, so embedded newlines
--- survive (multi-line Prompts and Reviews), without submitting (no Enter/CR):
--- the user reviews and presses Enter. `send-keys -l` would collapse newlines
--- in claude, so this uses set-buffer + paste-buffer -p instead.
---@param agent vantage.Agent
---@param text string
---@return boolean
---@return string?
function M.send_keys(agent, text)
  local set_result = exec("set-buffer", "-b", "vantage-send", "--", text)
  if set_result.code ~= 0 then
    return false, fail_message("failed to stage prompt text", set_result)
  end

  local paste_result = exec("paste-buffer", "-p", "-t", agent.id, "-b", "vantage-send")
  local delete_result = exec("delete-buffer", "-b", "vantage-send")
  if paste_result.code ~= 0 then
    local message = fail_message("failed to paste prompt text", paste_result)
    if delete_result.code ~= 0 then
      message = message .. "; " .. fail_message("failed to clean prompt buffer", delete_result)
    end
    return false, message
  end
  if delete_result.code ~= 0 then
    return false, fail_message("failed to clean prompt buffer", delete_result)
  end
  return true, nil
end

--- Snapshot the last `max_lines` lines of an Agent's pane (for picker previews).
---@param agent vantage.Agent
---@param max_lines? integer default 50
---@return string[]?
---@return string?
function M.capture_pane(agent, max_lines)
  local result = exec("capture-pane", "-p", "-S", "-" .. (max_lines or 50), "-t", agent.id)
  if result.code ~= 0 then
    return nil, fail_message(("failed to capture agent '%s'"):format(agent.id), result)
  end
  local lines = vim.split(result.stdout or "", "\n", { plain = true })
  if lines[#lines] == "" then
    lines[#lines] = nil
  end
  return lines, nil
end

--- Thin debug view of clients + sessions.
---@return { clients: string[], sessions: string[] }?
---@return string?
function M.status()
  local clients, clients_err =
    exec_lines("list-clients", "-F", "#{client_name}\t#{client_pid}\t#{session_name}\t#{window_id}")
  local sessions, sessions_err =
    exec_lines("list-sessions", "-F", "#{session_name}\tgroup=#{session_group}\tview=#{@vantage-view}")
  local err = clients_err or sessions_err
  if err and missing_server(err) then
    err = nil
  end
  if err then
    return nil, err
  end
  return {
    clients = clients,
    sessions = sessions,
  }, nil
end

--- Health checks for the tmux driver: binary presence and socket state.
---@return { status: "ok"|"warn"|"err", message: string, fatal?: boolean }[]
function M.health()
  if vim.fn.executable("tmux") ~= 1 then
    return { { status = "err", message = "tmux not found in PATH", fatal = true } }
  end
  local version = vim.trim(exec("-V").stdout)
  local checks = { { status = "ok", message = ("tmux found: %s"):format(version) } }
  local code = exec("list-sessions").code
  if code == 0 then
    checks[#checks + 1] = { status = "ok", message = ("vantage tmux socket '%s' is running"):format(socket()) }
  elseif code == 1 then
    checks[#checks + 1] =
      { status = "ok", message = ("vantage tmux socket '%s' not started yet (starts on first use)"):format(socket()) }
  else
    checks[#checks + 1] =
      { status = "warn", message = ("tmux socket '%s' check returned exit code %s"):format(socket(), tostring(code)) }
  end
  return checks
end

return M
