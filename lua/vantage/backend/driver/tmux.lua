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

--- Trimmed stdout, or "" on error.
local function exec_out(...)
  local result = exec_result(...)
  if result.code ~= 0 then
    return ""
  end
  return vim.trim(result.stdout)
end

--- List of non-empty lines, or {} on error.
local function exec_lines(...)
  local result = exec_result(...)
  if result.code ~= 0 then
    return {}
  end
  local lines = {}
  -- Do not trim: tmux -F output is tab-delimited and may carry a trailing
  -- empty field (e.g. @agent-state). Only drop empty/whitespace-only lines.
  for line in (result.stdout or ""):gmatch("[^\r\n]+") do
    if line:find("%S") then
      lines[#lines + 1] = line
    end
  end
  return lines
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

--- Apply the global (server-wide) config. Idempotent and cheap; only called
--- right after a `new-session` starts the server, exactly once per server
--- lifetime (L1: never re-checked afterwards, fail-and-warn on external kill).
local function apply_global_config()
  exec("set", "-g", "default-terminal", "tmux-256color")
  exec("set", "-g", "history-limit", "20000")
  exec("set", "-g", "focus-events", "on")
  -- No tmux status line: the terminal is the raw agent prompt.
  exec("set", "-g", "status", "off")
  -- Agent info in the pane's top border: Group · Tool · cwd · per-Group State
  -- counts. The counts are computed read-only per status tick by
  -- scripts/vantage-counts inside a #() substitution — never stored; the
  -- command string embeds the expanded #{@agent-group}, so tmux dedupes it to
  -- one small process per Group per tick.
  exec("set", "-g", "status-interval", "1")
  exec("set", "-g", "pane-border-status", "top")
  local counts = ('#("%s/vantage-counts" -L %s #{@agent-group})'):format(scripts_dir(), socket())
  local border_format = (" #{@agent-group} · #{@agent-tool} · #{@agent-cwd-tilde}%s "):format(counts)
  exec("set", "-g", "pane-border-format", border_format)
end

--- Create an Agent in a Group, creating the Group if it does not exist. The
--- first creation of the server's lifetime starts it via new-session and
--- applies the global config immediately after.
---@param opts { group: string, cmd: string, cwd: string, tool: string }
---@return vantage.Agent?
function M.create(opts)
  local group_exists = exec("has-session", "-t", opts.group) == 0

  local window_id
  local failed
  if group_exists then
    failed = exec_result("new-window", "-d", "-P", "-F", "#{window_id}", "-t", opts.group, "-c", opts.cwd, opts.cmd)
    window_id = failed.code == 0 and vim.trim(failed.stdout) or ""
  else
    failed = exec_result("new-session", "-d", "-s", opts.group, "-c", opts.cwd, opts.cmd)
    if failed.code ~= 0 then
      Util.notify(fail_message(("failed to create agent in group '%s'"):format(opts.group), failed))
      return nil
    end
    apply_global_config() -- the new-session just started the server
    failed = exec_result("display", "-p", "-t", opts.group, "#{window_id}")
    window_id = failed.code == 0 and vim.trim(failed.stdout) or ""
  end

  if window_id == "" then
    Util.notify(fail_message(("failed to create agent in group '%s'"):format(opts.group), failed))
    return nil
  end

  exec("set-window-option", "-t", window_id, "@agent-group", opts.group)
  exec("set-window-option", "-t", window_id, "@agent-cmd", opts.cmd)
  exec("set-window-option", "-t", window_id, "@agent-cwd", opts.cwd)
  -- Display form of the cwd for the pane border (static: an Agent's working
  -- directory does not change; tilde-izing once here avoids a runtime #()
  -- process in the border format).
  exec("set-window-option", "-t", window_id, "@agent-cwd-tilde", Util.tilde(opts.cwd))
  exec("set-window-option", "-t", window_id, "@agent-tool", opts.tool)
  -- A fresh Agent starts idle; the lifecycle scripts replace it on the first
  -- transition (no backfill: only external tampering can leave it unset).
  exec("set-window-option", "-t", window_id, "@agent-state", "idle")

  return {
    group = opts.group,
    target = window_id,
    cmd = opts.cmd,
    cwd = opts.cwd,
    tool = opts.tool,
    state = "idle",
  }
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

local function find_agent_by_target(agents, target)
  for _, agent in ipairs(agents) do
    if agent.target == target then
      return agent
    end
  end
  return nil
end

--- One read of the live Agent inventory plus, when a terminal pid is supplied,
--- the Agent that terminal is displaying. Both multiplexer queries are chained
--- with a `;` argument into one shell process (one fork, zero polling).
---@param pid? integer the terminal job's pid (its client)
---@return { agents: vantage.Agent[], groups: string[], focused?: vantage.Agent }
function M.snapshot(pid)
  local code, stdout =
    run("list-windows", "-a", "-f", "#{@agent-cmd}", "-F", AGENT_FMT, ";", "list-clients", "-F", CLIENT_FMT)
  local agents = {}
  local focused_target
  if code == 0 then
    local seen = {}
    for line in (stdout or ""):gmatch("[^\r\n]+") do
      local fields = vim.split(line, "\t", { plain = true })
      if #fields == 6 then
        local group, target, cmd, cwd, tool, state = fields[1], fields[2], fields[3], fields[4], fields[5], fields[6]
        if group ~= "" and target ~= "" and not seen[target] then
          seen[target] = true
          agents[#agents + 1] = {
            group = group,
            target = target,
            cmd = cmd,
            cwd = cwd,
            tool = tool,
            state = (state ~= "" and state) or nil,
          }
        end
      elseif #fields == 2 and pid ~= nil and tonumber(fields[1]) == pid then
        focused_target = fields[2]
      end
    end
  end
  table.sort(agents, function(left, right)
    return Util.agent_window_index(left.target) < Util.agent_window_index(right.target)
  end)
  local seen = {}
  local groups = {}
  for _, agent in ipairs(agents) do
    if not seen[agent.group] then
      seen[agent.group] = true
      groups[#groups + 1] = agent.group
    end
  end
  table.sort(groups)
  return {
    agents = agents,
    groups = groups,
    focused = find_agent_by_target(agents, focused_target or ""),
  }
end

--- The client attached to the terminal whose job has `pid`, by name.
---@param pid integer
---@return string client name, or "" when none
local function client_name(pid)
  for _, line in ipairs(exec_lines("list-clients", "-F", "#{client_pid}\t#{client_name}")) do
    local client_pid, name = line:match("^(%d+)\t(.*)$")
    if client_pid and tonumber(client_pid) == pid then
      return name
    end
  end
  return ""
end

--- Re-point the terminal's client to an Agent: one switch-client, covering a
--- same-Group window change and a cross-Group move alike.
---@param pid integer the terminal job's pid (its client)
---@param agent vantage.Agent
---@return boolean
function M.retarget(pid, agent)
  local name = client_name(pid)
  if name == "" then
    Util.warn(("no client attached with pid %d"):format(pid))
    return false
  end
  local result = exec_result("switch-client", "-c", name, "-t", agent.group .. ":" .. agent.target)
  if result.code ~= 0 then
    Util.warn(fail_message(("can't switch to %s:%s"):format(agent.group, agent.target), result))
    return false
  end
  return true
end

--- Kill a single Agent's window.
---@param agent vantage.Agent
function M.kill_agent(agent)
  exec("kill-window", "-t", agent.target)
end

--- Kill an entire Group session.
---@param group string
function M.kill_group(group)
  exec("kill-session", "-t", group)
end

--- Paste text into an Agent's pane via bracketed paste, so embedded newlines
--- survive (multi-line Prompts and Reviews), without submitting (no Enter/CR):
--- the user reviews and presses Enter. `send-keys -l` would collapse newlines
--- in claude, so this uses set-buffer + paste-buffer -p instead.
---@param agent vantage.Agent
---@param text string
function M.send_keys(agent, text)
  exec("set-buffer", "-b", "vantage-send", "--", text)
  exec("paste-buffer", "-p", "-t", agent.target, "-b", "vantage-send")
  exec("delete-buffer", "-b", "vantage-send")
end

--- Snapshot the last `max_lines` lines of an Agent's pane (for picker previews).
---@param agent vantage.Agent
---@param max_lines? integer default 50
---@return string[]
function M.capture_pane(agent, max_lines)
  local code, stdout = run("capture-pane", "-p", "-S", "-" .. (max_lines or 50), "-t", agent.target)
  if code ~= 0 then
    return {}
  end
  local lines = vim.split(stdout or "", "\n", { plain = true })
  if lines[#lines] == "" then
    lines[#lines] = nil
  end
  return lines
end

--- The command to attach a terminal client to (Group, Agent), run as a `term`
--- job by the Terminal. Lives here so the Frontend never hardcodes tmux.
---@param group string
---@param agent string Agent window id (@N)
---@return string[]
function M.attach_command(group, agent)
  return { "tmux", "-L", socket(), "attach-session", "-t", group .. ":" .. agent }
end

--- Thin debug view of clients + sessions.
---@return { clients: string[], sessions: string[] }
function M.status()
  return {
    clients = exec_lines("list-clients", "-F", "#{client_name}\t#{client_pid}\t#{session_name}\t#{window_id}"),
    sessions = exec_lines("list-sessions", "-F", "#{session_name}"),
  }
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
