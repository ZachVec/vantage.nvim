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
  return Config.options.socket
end

--- The repo's scripts/ directory (this file lives at
--- <repo>/lua/vantage/backend/driver/tmux.lua; five dirnames up). Used to call
--- scripts/vantage-counts from a tmux #() substitution: tmux runs #() with the
--- server's environment, where the scripts are not on PATH.
---@return string
local function scripts_dir()
  local src = debug.getinfo(1, "S").source
  if src:sub(1, 1) == "@" then
    src = src:sub(2)
  end
  return vim.fs.joinpath(vim.fn.fnamemodify(src, ":p:h:h:h:h:h"), "scripts")
end

--- Run a tmux command synchronously.
---@return integer code
---@return string stdout
---@return string stderr
local function run(...)
  return Util.run({ "tmux", "-L", socket(), ... })
end

--- Run a tmux command and return a structured result, so callers that need
--- diagnostics can read `stderr` without every caller handling three return
--- values.
---@return { code: integer, stdout: string, stderr: string }
local function exec_result(...)
  local code, stdout, stderr = run(...)
  return { code = code, stdout = stdout, stderr = stderr }
end

--- Exit code only, for the many commands where success/failure is the whole
--- question.
local function exec(...)
  return exec_result(...).code
end

local fail_message

--- List of non-empty lines, or {} plus the failure message on error.
---@return string[]
---@return string?
local function exec_lines(...)
  local result = exec_result(...)
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

--- Build a user-facing failure message from a failed tmux result, including
--- stderr when tmux supplied a reason.
---@param prefix string
---@param result { code: integer, stdout: string, stderr: string }
---@return string
function fail_message(prefix, result)
  local detail = vim.trim(result.stderr or "")
  if detail == "" then
    return prefix
  end
  return ("%s: %s"):format(prefix, detail)
end

--- True when tmux reports that its server/socket does not exist yet.
---@param value table|string
---@return boolean
local function missing_server(value)
  local text = type(value) == "table" and (value.stderr or "") or tostring(value)
  return text:find("no server running", 1, true) ~= nil or text:find("error connecting", 1, true) ~= nil
end

--- Apply the global (server-wide) config. Idempotent and cheap; only called
--- right after a `new-session` starts the server, exactly once per server
--- lifetime (L1: never re-checked afterwards, fail-and-warn on external kill).
---@return boolean
---@return string?
local function apply_global_config()
  local settings = {
    { "set-hook", "-g", "client-detached", CLIENT_DETACHED_HOOK },
    { "set", "-g", "default-terminal", "tmux-256color" },
    { "set", "-g", "history-limit", "20000" },
    { "set", "-g", "focus-events", "on" },
  }
  -- No tmux status line: the terminal is the raw agent prompt.
  settings[#settings + 1] = { "set", "-g", "status", "off" }
  -- Agent info in the pane's top border: Group · Tool · cwd · per-Group State
  -- counts. The counts are computed read-only per status tick by
  -- scripts/vantage-counts inside a #() substitution — never stored; the
  -- command string embeds the expanded #{@agent-group}, so tmux dedupes it to
  -- one small process per Group per tick.
  settings[#settings + 1] = { "set", "-g", "status-interval", "1" }
  settings[#settings + 1] = { "set", "-g", "pane-border-status", "top" }
  local counts = ('#("%s/vantage-counts" -L %s #{@agent-group})'):format(scripts_dir(), socket())
  local border_format = (" #{@agent-group} · #{@agent-tool} · #{@agent-cwd-tilde}%s "):format(counts)
  settings[#settings + 1] = { "set", "-g", "pane-border-format", border_format }

  for _, setting in ipairs(settings) do
    local result = exec_result(setting[1], setting[2], setting[3], setting[4])
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
  local result = exec_result("display", "-p", "-t", session, "#{?#{session_group},#{session_group},#{session_name}}")
  if result.code ~= 0 then
    return nil, fail_message(("can't read session group for '%s'"):format(session), result)
  end
  return vim.trim(result.stdout), nil
end

--- True when a session is a Vantage View.
---@param session string
---@return boolean
---@return string?
local function is_view(session)
  local result = exec_result("display", "-p", "-t", session, "#{@vantage-view}")
  if result.code ~= 0 then
    return false, fail_message(("can't inspect session '%s'"):format(session), result)
  end
  return vim.trim(result.stdout) == "1", nil
end

--- Create a fresh View in a Group and point it at an Agent window.
---@param group string
---@param target string Agent window id (@N)
---@return string?
---@return string?
local function create_view(group, target)
  if exec("has-session", "-t", group) ~= 0 then
    return nil, ("no such group '%s'"):format(group)
  end
  local result = exec_result("new-session", "-d", "-P", "-F", "#{session_name}", "-t", group)
  if result.code ~= 0 then
    return nil, fail_message(("failed to create a view for group '%s'"):format(group), result)
  end
  local view = vim.trim(result.stdout)
  if view == "" then
    return nil, ("failed to create a view for group '%s': tmux returned an empty session name"):format(group)
  end

  local mark = exec_result("set-option", "-t", view, "@vantage-view", "1")
  if mark.code ~= 0 then
    exec("kill-session", "-t", view)
    return nil, fail_message(("failed to mark view '%s'"):format(view), mark)
  end
  local select = exec_result("select-window", "-t", view .. ":" .. target)
  if select.code ~= 0 then
    exec("kill-session", "-t", view)
    return nil, fail_message(("failed to point view '%s' at %s"):format(view, target), select)
  end
  return view, nil
end

--- Find the client attached to the terminal job whose pid is `pid`.
---@param pid integer
---@return { name: string, session: string }?
---@return string?
local function client_info(pid)
  local lines, err = exec_lines("list-clients", "-F", "#{client_pid}\t#{client_name}\t#{session_name}")
  if err then
    return nil, err
  end
  for _, line in ipairs(lines) do
    local client_pid, name, session = line:match("^(%d+)\t([^\t]*)\t([^\t]*)$")
    if client_pid and tonumber(client_pid) == pid then
      return { name = name, session = session }, nil
    end
  end
  return nil, nil
end

--- Move a client into a fresh View in the target Group.
---@param client { name: string, session: string }
---@param group string
---@param target string Agent window id (@N)
---@return string?
---@return string?
local function move_client_to_view(client, group, target)
  local view, err = create_view(group, target)
  if not view then
    return nil, err
  end
  local switch = exec_result("switch-client", "-c", client.name, "-t", view)
  if switch.code ~= 0 then
    exec("kill-session", "-t", view)
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

--- Remove a partially-created Agent. Returns an additional failure message
--- when rollback itself could not complete.
---@param created_session boolean
---@param group string
---@param id string
---@return string?
local function rollback_create(created_session, group, id)
  local result
  if created_session then
    result = exec_result("kill-session", "-t", group)
  else
    result = exec_result("kill-window", "-t", id)
  end
  if result.code ~= 0 then
    return fail_message("rollback failed", result)
  end
  return nil
end

--- Create an Agent in a Group, creating the Group if it does not exist. The
--- first creation of the server's lifetime starts it via new-session and
--- applies the global config immediately after. Metadata failures roll the
--- partial Agent back so callers never see a half-registered window.
---@param opts { group: string, cmd: string, cwd: string, tool: string }
---@return vantage.Agent?
---@return string?
function M.create(opts)
  local group_exists = exec("has-session", "-t", opts.group) == 0
  local created_session = not group_exists
  local window_id = ""
  local result

  if group_exists then
    result = exec_result("new-window", "-d", "-P", "-F", "#{window_id}", "-t", opts.group, "-c", opts.cwd, opts.cmd)
  else
    result = exec_result("new-session", "-d", "-s", opts.group, "-c", opts.cwd, opts.cmd)
  end
  if result.code ~= 0 then
    return nil, fail_message(("failed to create agent in group '%s'"):format(opts.group), result)
  end

  if created_session then
    local config_ok, config_err = apply_global_config()
    if not config_ok then
      local rollback_err = rollback_create(true, opts.group, "")
      return nil, rollback_err and (config_err .. "; " .. rollback_err) or config_err
    end
    result = exec_result("display", "-p", "-t", opts.group, "#{window_id}")
    if result.code ~= 0 then
      local primary = fail_message(("failed to create agent in group '%s'"):format(opts.group), result)
      local rollback_err = rollback_create(true, opts.group, "")
      return nil, rollback_err and (primary .. "; " .. rollback_err) or primary
    end
  end

  window_id = vim.trim(result.stdout)
  if window_id == "" then
    local primary = ("failed to create agent in group '%s': tmux returned an empty window id"):format(opts.group)
    local rollback_err = rollback_create(created_session, opts.group, window_id)
    return nil, rollback_err and (primary .. "; " .. rollback_err) or primary
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
    result = exec_result("set-window-option", "-t", window_id, item[1], item[2])
    if result.code ~= 0 then
      local primary = fail_message(("failed to mark agent window '%s'"):format(window_id), result)
      local rollback_err = rollback_create(created_session, opts.group, window_id)
      return nil, rollback_err and (primary .. "; " .. rollback_err) or primary
    end
  end

  return {
    id = window_id,
    seq = window_seq(window_id),
    group = opts.group,
    cmd = opts.cmd,
    cwd = opts.cwd,
    tool = opts.tool,
    state = "idle",
  },
    nil
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

--- Client rows: two tab-delimited fields (pid, current window id).
local CLIENT_FMT = "#{client_pid}\t#{window_id}"

local function find_agent_by_id(agents, id)
  for _, agent in ipairs(agents) do
    if agent.id == id then
      return agent
    end
  end
  return nil
end

--- One read of the live Agent inventory plus, when a terminal pid is supplied,
--- the Agent that terminal is displaying. Both multiplexer queries are chained
--- with a `;` argument into one shell process (one fork, zero polling).
---@param pid? integer the terminal job's pid (its client)
---@return { agents: vantage.Agent[], groups: string[], focused?: vantage.Agent }?
---@return string?
function M.snapshot(pid)
  local result =
    exec_result("list-windows", "-a", "-f", "#{@agent-cmd}", "-F", AGENT_FMT, ";", "list-clients", "-F", CLIENT_FMT)
  if result.code ~= 0 then
    if missing_server(result) then
      return {
        agents = {},
        groups = {},
      }, nil
    end
    return nil, fail_message("failed to read vantage state", result)
  end

  local agents = {}
  local focused_id
  local seen = {}
  for line in (result.stdout or ""):gmatch("[^\r\n]+") do
    local fields = vim.split(line, "\t", { plain = true })
    if #fields == 6 then
      local group, id, cmd, cwd, tool, state = fields[1], fields[2], fields[3], fields[4], fields[5], fields[6]
      if group ~= "" and id ~= "" and not seen[id] then
        seen[id] = true
        agents[#agents + 1] = {
          id = id,
          seq = window_seq(id),
          group = group,
          cmd = cmd,
          cwd = cwd,
          tool = tool,
          state = (state ~= "" and state) or nil,
        }
      end
    elseif #fields == 2 and pid ~= nil and tonumber(fields[1]) == pid then
      focused_id = fields[2]
    end
  end
  table.sort(agents, function(left, right)
    return left.seq < right.seq
  end)
  local seen_groups = {}
  local groups = {}
  for _, agent in ipairs(agents) do
    if not seen_groups[agent.group] then
      seen_groups[agent.group] = true
      groups[#groups + 1] = agent.group
    end
  end
  table.sort(groups)
  return {
    agents = agents,
    groups = groups,
    focused = find_agent_by_id(agents, focused_id or ""),
  }, nil
end

--- Re-point a client to an Agent without changing any other client's View.
---@param pid integer the terminal job's pid (its client)
---@param agent vantage.Agent
---@return boolean
---@return string?
function M.retarget(pid, agent)
  local client, client_err = client_info(pid)
  if client_err then
    return false, client_err
  end
  if not client then
    return false, ("no client attached with pid %d"):format(pid)
  end

  local current_group, group_err = session_group(client.session)
  if group_err then
    return false, group_err
  end
  local old_is_view = is_view(client.session)

  if current_group == agent.group and old_is_view then
    local result = exec_result("select-window", "-t", client.session .. ":" .. agent.id)
    if result.code ~= 0 then
      return false, fail_message(("can't switch to %s:%s"):format(client.session, agent.id), result)
    end
    return true, nil
  end

  local _, move_err = move_client_to_view(client, agent.group, agent.id)
  if move_err then
    return false, move_err
  end
  if old_is_view then
    local cleanup = exec_result("kill-session", "-t", client.session)
    if cleanup.code ~= 0 then
      return false, fail_message(("switched but failed to clean old view '%s'"):format(client.session), cleanup)
    end
  end
  return true, nil
end

--- Create a fresh View for this Terminal and return its attach command.
---@param agent vantage.Agent
---@return { view: string, argv: string[] }?
---@return string?
function M.attach(agent)
  local view, err = create_view(agent.group, agent.id)
  if not view then
    return nil, err
  end
  return {
    view = view,
    argv = { "tmux", "-L", socket(), "attach-session", "-t", view },
  }, nil
end

--- Remove a View created for a Terminal that failed to start.
---@param view string
---@return boolean
---@return string?
function M.kill_view(view)
  local view_ok, inspect_err = is_view(view)
  if inspect_err then
    return false, inspect_err
  end
  if not view_ok then
    return false, ("session '%s' is not a view"):format(view)
  end
  local result = exec_result("kill-session", "-t", view)
  if result.code ~= 0 then
    return false, fail_message(("can't kill view '%s'"):format(view), result)
  end
  return true, nil
end

--- Kill a single Agent's window.
---@param agent vantage.Agent
---@return boolean
---@return string?
function M.kill_agent(agent)
  local result = exec_result("kill-window", "-t", agent.id)
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
    local result = exec_result("kill-session", "-t", session)
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
  local set_result = exec_result("set-buffer", "-b", "vantage-send", "--", text)
  if set_result.code ~= 0 then
    return false, fail_message("failed to stage prompt text", set_result)
  end

  local paste_result = exec_result("paste-buffer", "-p", "-t", agent.id, "-b", "vantage-send")
  local delete_result = exec_result("delete-buffer", "-b", "vantage-send")
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
  local result = exec_result("capture-pane", "-p", "-S", "-" .. (max_lines or 50), "-t", agent.id)
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
  }, err
end

--- Health checks for the tmux driver: binary presence and socket state.
---@return { status: "ok"|"warn"|"err", message: string, fatal?: boolean }[]
function M.health()
  if vim.fn.executable("tmux") ~= 1 then
    return { { status = "err", message = "tmux not found in PATH", fatal = true } }
  end
  local version = vim.trim(vim.fn.system({ "tmux", "-V" }))
  local checks = { { status = "ok", message = ("tmux found: %s"):format(version) } }
  local code = exec("list-sessions")
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
