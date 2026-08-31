--- tmux backend driver: owns all state and domain logic over a private socket.
---
--- Domain model:
---   Group  = a tmux session group; one persistent Anchor session owns the Agents.
---   Agent  = a tmux window marked with @agent-cmd, shared across the Group's Views.
---   View   = a transient grouped session marked @vantage-view 1; the
---            client-detached hook destroys it when its client detaches.
local Config = require("vantage.config")
local Util = require("vantage.util")

local M = {}

--- Destroy a View when its client detaches (frontend closed/crashed). The
--- Anchor is never marked @vantage-view, so it survives and keeps Agents alive
--- headless. The kill runs in a separate tmux process via run-shell: a direct
--- kill-session from the hook's command context does not take effect.
local CLIENT_DETACHED_HOOK =
  [[run-shell "if [ \"#{@vantage-view}\" = \"1\" ]; then tmux -S \"#{socket_path}\" kill-session -t \"#{session_name}\"; fi"]]

local function socket()
  return Config.options.socket
end

--- Run a tmux command; returns exit code.
local function run(...)
  return Util.run({ "tmux", "-L", socket(), ... })
end

--- Exit code only.
local function exec(...)
  local code = run(...)
  return code
end

--- Trimmed stdout, or "" on error.
local function exec_out(...)
  local code, stdout = run(...)
  if code ~= 0 then
    return ""
  end
  return vim.trim(stdout)
end

--- List of non-empty lines, or {} on error.
local function exec_lines(...)
  local code, stdout = run(...)
  if code ~= 0 then
    return {}
  end
  local lines = {}
  -- Do not trim: tmux -F output is tab-delimited and may carry a trailing
  -- empty field (e.g. @agent-state). Only drop empty/whitespace-only lines.
  for line in (stdout or ""):gmatch("[^\r\n]+") do
    if line:find("%S") then
      lines[#lines + 1] = line
    end
  end
  return lines
end

--- Apply the global (server-wide) config. Idempotent and cheap; must only be
--- called while the server is running.
local function apply_global_config()
  exec("set-hook", "-g", "client-detached", CLIENT_DETACHED_HOOK)
  exec("set", "-g", "default-terminal", "tmux-256color")
  exec("set", "-g", "history-limit", "20000")
  exec("set", "-g", "focus-events", "on")
  -- No tmux status line: the terminal is the raw agent prompt.
  exec("set", "-g", "status", "off")
end

--- Ensure the server is configured. Returns true if it is running (a session
--- exists); a sessionless server cannot persist, so the first `create` starts
--- it and applies config immediately after.
---@return boolean
function M.ensure_server()
  local code = exec("list-sessions")
  if code == 0 then
    apply_global_config()
    return true
  end
  return false
end

--- Sessions belonging to a Group (anchor + Views). A standalone anchor has an
--- empty session_group, so fall back to its own name as the group key.
---@param group string
---@return string[]
function M.group_views(group)
  local filter = "#{==:#{?#{session_group},#{session_group},#{session_name}}," .. group .. "}"
  return exec_lines("list-sessions", "-F", "#{session_name}", "-f", filter)
end

--- All Agents, deduplicated by window id (a window is listed once per grouped
--- session, so -a yields duplicates).
---@return vantage.Agent[]
function M.list()
  M.ensure_server()
  local format_fields = table.concat({
    "#{?#{session_group},#{session_group},#{session_name}}", -- group
    "#{window_id}", -- target (@N)
    "#{@agent-cmd}",
    "#{@agent-cwd}",
    "#{@agent-name}",
    "#{@agent-state}",
  }, "\t")
  local lines = exec_lines("list-windows", "-a", "-f", "#{@agent-cmd}", "-F", format_fields)
  local seen = {}
  local agents = {}
  for _, line in ipairs(lines) do
    local group, target, cmd, cwd, name, state =
      line:match("^([^\t]*)\t([^\t]*)\t([^\t]*)\t([^\t]*)\t([^\t]*)\t([^\t]*)$")
    if group ~= "" and target ~= "" and not seen[target] then
      seen[target] = true
      agents[#agents + 1] = {
        group = group,
        target = target,
        cmd = cmd,
        cwd = cwd,
        name = name,
        state = (state ~= "" and state) or nil,
      }
    end
  end
  table.sort(agents, function(left, right)
    return left.target < right.target
  end)
  return agents
end

--- Unique Group names (derived from Agents).
---@return string[]
function M.groups()
  local seen = {}
  local names = {}
  for _, agent in ipairs(M.list()) do
    if not seen[agent.group] then
      seen[agent.group] = true
      names[#names + 1] = agent.group
    end
  end
  table.sort(names)
  return names
end

--- Create an Agent in a Group, creating the Group if it does not exist.
---@param opts { group: string, cmd: string, cwd: string, name?: string }
---@return vantage.Agent?
function M.create(opts)
  local running = M.ensure_server()
  local name = opts.name or ("agent-" .. os.time())
  local views = running and M.group_views(opts.group) or {}

  local window_id
  if #views > 0 then
    window_id =
      exec_out("new-window", "-d", "-P", "-F", "#{window_id}", "-t", views[1], "-n", name, "-c", opts.cwd, opts.cmd)
  else
    exec("new-session", "-d", "-s", opts.group, "-n", name, "-c", opts.cwd, opts.cmd)
    apply_global_config() -- the new-session just started the server
    window_id = exec_out("display", "-p", "-t", opts.group, "#{window_id}")
  end

  if window_id == "" then
    Util.notify(("failed to create agent in group '%s'"):format(opts.group))
    return nil
  end

  exec("set-window-option", "-t", window_id, "@agent-cmd", opts.cmd)
  exec("set-window-option", "-t", window_id, "@agent-cwd", opts.cwd)
  exec("set-window-option", "-t", window_id, "@agent-name", name)

  return { group = opts.group, target = window_id, cmd = opts.cmd, cwd = opts.cwd, name = name, state = nil }
end

--- Re-target an existing View to the given Agent window.
---@param view string tmux View session name
---@param target string Agent window id (@N)
function M.select_window(view, target)
  exec("select-window", "-t", view .. ":" .. target)
end

--- Create a new transient View in a Group and select the target Agent.
---@param group string
---@param target string Agent window id (@N)
---@return string? view session name
function M.attach(group, target)
  M.ensure_server()
  local views = M.group_views(group)
  if #views == 0 then
    Util.warn(("no such group '%s'"):format(group))
    return nil
  end
  local view = exec_out("new-session", "-d", "-P", "-F", "#{session_name}", "-t", views[1])
  if view == "" then
    Util.notify(("failed to create a view for group '%s'"):format(group))
    return nil
  end
  exec("set-option", "-t", view, "@vantage-view", "1")
  if target and target ~= "" then
    exec("select-window", "-t", view .. ":" .. target)
  end
  return view
end

--- Kill a single Agent (@N) or an entire Group.
---@param target string Agent window id (@N) or Group name
function M.kill(target)
  M.ensure_server()
  if vim.startswith(target, "@") then
    exec("kill-window", "-t", target)
    return
  end
  local views = M.group_views(target)
  if #views == 0 then
    Util.warn(("no such group '%s'"):format(target))
    return
  end
  for _, session in ipairs(views) do
    exec("kill-session", "-t", session)
  end
end

--- Thin debug view of clients + sessions.
---@return { clients: string[], sessions: string[] }
function M.status()
  M.ensure_server()
  return {
    clients = exec_lines("list-clients", "-F", "#{client_name}\t#{client_pid}\t#{session_name}\t#{window_id}"),
    sessions = exec_lines("list-sessions", "-F", "#{session_name}\tgroup=#{session_group}"),
  }
end

--- Whether a session with this name currently exists.
---@param name string
---@return boolean
function M.has_session(name)
  return exec("has-session", "-t", name) == 0
end

--- Snapshot the last `max_lines` lines of an Agent's pane (for picker previews).
---@param target string Agent window id (@N)
---@param max_lines? integer default 50
---@return string[]
function M.capture_pane(target, max_lines)
  local code, stdout = run("capture-pane", "-p", "-S", "-" .. (max_lines or 50), "-t", target)
  if code ~= 0 then
    return {}
  end
  local lines = vim.split(stdout or "", "\n", { plain = true })
  if lines[#lines] == "" then
    lines[#lines] = nil
  end
  return lines
end

return M
