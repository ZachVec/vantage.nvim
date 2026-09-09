--- tmux driver: pure multiplexer mapping over a private socket.
---
--- Domain model:
---   Group  = one tmux session (persistent, never created alone).
---   Agent  = one single-pane window in it, marked with @agent-cmd and friends.
---   The attachment is the terminal's client, identified by the terminal job's
---   pid; there are no session groups, anchor sessions, or per-view sessions.
local Config = require("vantage.config")
local Util = require("vantage.util")

local M = {}

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
    { "default-terminal", "tmux-256color" },
    { "history-limit", "20000" },
    { "focus-events", "on" },
  }
  -- No tmux status line: the terminal is the raw agent prompt.
  settings[#settings + 1] = { "status", "off" }
  -- Agent info in the pane's top border: Group · Tool · cwd · per-Group State
  -- counts. The counts are computed read-only per status tick by
  -- scripts/vantage-counts inside a #() substitution — never stored; the
  -- command string embeds the expanded #{@agent-group}, so tmux dedupes it to
  -- one small process per Group per tick.
  settings[#settings + 1] = { "status-interval", "1" }
  settings[#settings + 1] = { "pane-border-status", "top" }
  local counts = ('#("%s/vantage-counts" -L %s #{@agent-group})'):format(scripts_dir(), socket())
  local border_format = (" #{@agent-group} · #{@agent-tool} · #{@agent-cwd-tilde}%s "):format(counts)
  settings[#settings + 1] = { "pane-border-format", border_format }

  for _, setting in ipairs(settings) do
    local result = exec_result("set", "-g", setting[1], setting[2])
    if result.code ~= 0 then
      return false, fail_message(("failed to set tmux option '%s'"):format(setting[1]), result)
    end
  end
  return true, nil
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

--- The client attached to the terminal whose job has `pid`, by name.
---@param pid integer
---@return string client name, or "" when none
---@return string?
local function client_name(pid)
  local lines, err = exec_lines("list-clients", "-F", "#{client_pid}\t#{client_name}")
  if err then
    return "", err
  end
  for _, line in ipairs(lines) do
    local client_pid, name = line:match("^(%d+)\t(.*)$")
    if client_pid and tonumber(client_pid) == pid then
      return name, nil
    end
  end
  return "", nil
end

--- Re-point the terminal's client to an Agent: one switch-client, covering a
--- same-Group window change and a cross-Group move alike.
---@param pid integer the terminal job's pid (its client)
---@param agent vantage.Agent
---@return boolean
---@return string?
function M.retarget(pid, agent)
  local name, client_err = client_name(pid)
  if client_err then
    return false, client_err
  end
  if name == "" then
    return false, ("no client attached with pid %d"):format(pid)
  end
  local result = exec_result("switch-client", "-c", name, "-t", agent.group .. ":" .. agent.id)
  if result.code ~= 0 then
    return false, fail_message(("can't switch to %s:%s"):format(agent.group, agent.id), result)
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

--- Kill an entire Group session.
---@param group string
---@return boolean
---@return string?
function M.kill_group(group)
  local result = exec_result("kill-session", "-t", group)
  if result.code ~= 0 then
    return false, fail_message(("can't kill group '%s'"):format(group), result)
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

--- The command to attach a terminal client to an Agent, run as a `term` job by
--- the Terminal. Lives here so the Frontend never hardcodes tmux.
---@param agent vantage.Agent
---@return string[]
function M.attach_command(agent)
  return { "tmux", "-L", socket(), "attach-session", "-t", agent.group .. ":" .. agent.id }
end

--- Thin debug view of clients + sessions.
---@return { clients: string[], sessions: string[] }?
---@return string?
function M.status()
  local clients, clients_err =
    exec_lines("list-clients", "-F", "#{client_name}\t#{client_pid}\t#{session_name}\t#{window_id}")
  local sessions, sessions_err = exec_lines("list-sessions", "-F", "#{session_name}")
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
