---@module 'luassert'

local Helpers = require("helpers")

describe("vantage.backend.tmux", function()
  local Backend
  local Config
  local Util
  local socket
  local jobs

  local function tmux(...)
    return Util.run({ "tmux", "-L", socket, ... })
  end

  local function reset_server()
    tmux("kill-server") -- exit 1 when no server exists; that is expected here
  end

  local function stop_jobs()
    for _, job in ipairs(jobs) do
      pcall(vim.fn.jobstop, job)
    end
    jobs = {}
  end

  local function wait_until(condition, timeout_ms)
    local waited = 0
    while waited < timeout_ms do
      if condition() then
        return true
      end
      vim.wait(50)
      waited = waited + 50
    end
    return condition()
  end

  local function capture_contains(agent, needle)
    local lines = Backend.capture_pane(agent, 200)
    for _, line in ipairs(lines) do
      if line:find(needle, 1, true) then
        return true
      end
    end
    return false
  end

  local function find_agent(id)
    for _, agent in ipairs(Backend.agents()) do
      if agent.id == id then
        return agent
      end
    end
    return nil
  end

  --- The private socket's paste buffers, by name.
  ---@return string[]
  local function staged_buffers()
    local _, out = tmux("list-buffers", "-F", "#{buffer_name}")
    local names = {}
    for line in (out or ""):gmatch("[^\r\n]+") do
      names[#names + 1] = line
    end
    return names
  end

  --- The Group's View sessions, by name: the group's sessions minus its Anchor.
  ---@param group string
  ---@return string[]
  local function group_views(group)
    local filter = "#{==:#{?#{session_group},#{session_group},#{session_name}}," .. group .. "}"
    local _, out = tmux("list-sessions", "-F", "#{session_name}", "-f", filter)
    local views = {}
    for line in (out or ""):gmatch("[^\r\n]+") do
      if line ~= group then
        views[#views + 1] = line
      end
    end
    return views
  end

  local function create(group, tag, cmd)
    return Backend.create({
      group = group,
      cmd = cmd or "exec sleep 300",
      cwd = "/tmp",
      tool = tag,
    })
  end

  --- Attach an Agent with a client that really starts, so the tests can move it.
  ---@param agent vantage.Agent
  ---@return vantage.Attachment
  local function attach(agent)
    local attachment, err = Backend.attach(agent, function(argv)
      local job = vim.fn.jobstart(argv, { pty = true })
      if job <= 0 then
        return false, "failed to start the terminal"
      end
      jobs[#jobs + 1] = job
      return true
    end)
    assert.are.equal(nil, err)
    assert.is_not_nil(attachment)
    return attachment
  end

  --- Attach an Agent with no client at all: the View exists, nobody sits on it.
  ---@param agent vantage.Agent
  ---@return vantage.Attachment
  local function attach_without_client(agent)
    local attachment, err = Backend.attach(agent, function()
      return true
    end)
    assert.are.equal(nil, err)
    assert.is_not_nil(attachment)
    return attachment
  end

  setup(function()
    if vim.fn.executable("tmux") ~= 1 then
      error("tmux is required for vantage.backend.tmux specs")
    end
    Helpers.reload_vantage()
    Config = require("vantage.config")
    Util = require("vantage.util")
    socket = "vantage-test-" .. vim.fn.getpid()
    Config.options.backend_opts.tmux.socket = socket
    local BackendModule = require("vantage.backend")
    BackendModule.setup()
    Backend = BackendModule.get()
    jobs = {}
    reset_server()
  end)

  before_each(function()
    stop_jobs()
    reset_server()
  end)

  teardown(function()
    stop_jobs()
    reset_server()
    Helpers.reload_vantage()
  end)

  it("reports an empty inventory before the first agent is created", function()
    local agents, agents_err = Backend.agents()
    local status_info, status_err = Backend.status()
    assert.are.equal(nil, agents_err)
    assert.are.equal(nil, status_err)
    assert.are.same({}, agents)
    assert.are.same({ clients = {}, sessions = {} }, status_info)
    assert.are.equal("tmux", vim.split(Backend.health()[1].message, " ", { plain = true })[1])
  end)

  it("implements the vantage.Driver surface", function()
    for _, name in ipairs({
      "create",
      "agents",
      "attach",
      "kill_agent",
      "send_keys",
      "capture_pane",
      "status",
      "health",
    }) do
      assert.are.equal("function", type(Backend[name]), name)
    end
  end)

  it("creates an agent in a new group with the domain metadata", function()
    local agent, err = create("g-one", "codex")
    assert.are.equal(nil, err)
    assert.are.equal("g-one", agent.group)
    assert.are.equal("codex", agent.tool)
    assert.are.equal("/tmp", agent.cwd)
    assert.are.equal("idle", agent.state)
    assert.is_true(agent.id:match("^@%d+$") ~= nil)
    assert.are.equal("number", type(agent.seq))

    assert.are.same(agent, find_agent(agent.id))
  end)

  it("attaches through the launch callback and hands back an Attachment", function()
    local agent = create("g-attach", "codex")
    local launched
    local attachment, attach_err = Backend.attach(agent, function(argv)
      launched = argv
      return true
    end)

    assert.are.equal(nil, attach_err)
    assert.is_not_nil(attachment)
    assert.are.equal("function", type(attachment.focus))
    assert.are.equal("function", type(attachment.retarget))
    assert.are.same({ "tmux", "-L", socket, "attach-session", "-t" }, {
      launched[1],
      launched[2],
      launched[3],
      launched[4],
      launched[5],
    })
    assert.is_true(launched[6] ~= "" and launched[6] ~= nil)
    assert.are.equal(1, #group_views("g-attach"))
  end)

  it("destroys the View when the client cannot start", function()
    local agent = create("g-rollback", "codex")

    local attachment, err = Backend.attach(agent, function()
      return false, "no pty"
    end)
    assert.are.equal(nil, attachment)
    assert.are.equal("no pty", err)
    assert.are.same({}, group_views("g-rollback"))
  end)

  it("reads the Focus from the Attachment's View without a client", function()
    local agent = create("g-focus", "codex")
    local attachment = attach_without_client(agent)

    local focused, focus_err = attachment:focus()
    assert.are.equal(nil, focus_err)
    assert.are.equal(agent.id, focused.id)
    assert.are.equal("g-focus", focused.group)
  end)

  it("reports no focused agent when the View's window is not an Agent window", function()
    local agent = create("g-plain", "codex")
    local attachment = attach_without_client(agent)
    local _, out = tmux("new-window", "-d", "-P", "-F", "#{window_id}", "-t", "g-plain", "exec sleep 300")
    local plain = vim.trim(out)

    local view = group_views("g-plain")[1]
    assert.is_true(view ~= nil)
    tmux("select-window", "-t", view .. ":" .. plain)

    local focused, reason = attachment:focus()
    assert.are.equal(nil, focused)
    assert.are.equal(Config.FOCUS_NO_FOCUS, reason)
  end)

  it("reports the reason when the Attachment's View is gone, and a missing server as empty", function()
    local agent = create("g-gone", "codex")
    local attachment = attach_without_client(agent)
    reset_server()

    local focused, focus_err = attachment:focus()
    assert.are.equal(nil, focused)
    assert.is_not_nil(focus_err)
    -- tmux says either "no server running" or "error connecting to <socket>".
    assert.is_true(
      focus_err:find("no server running", 1, true) ~= nil or focus_err:find("error connecting", 1, true) ~= nil
    )
    -- The inventory answers the same situation as "nothing there", not as a
    -- failure: every flow treats a never-started multiplexer as empty.
    assert.are.same({}, Backend.agents())
  end)

  it("adds a second agent to an existing group", function()
    local first = create("g-shared", "codex")
    local second = create("g-shared", "claude", "exec sleep 200")

    assert.are.equal(2, #Backend.agents())
    assert.are.same(second, find_agent(second.id))
    assert.is_true(find_agent(first.id) ~= nil)
  end)

  it("keeps two Attachments in one group on independent views", function()
    local first = create("g-two", "codex")
    local second = create("g-two", "claude")
    local one = attach(first)
    local two = attach(first)

    assert.is_true(wait_until(function()
      local focused = one:focus()
      return focused ~= nil and focused.id == first.id
    end, 3000))
    assert.is_true(wait_until(function()
      local focused = two:focus()
      return focused ~= nil and focused.id == first.id
    end, 3000))

    assert.are.equal(true, one:retarget(second))
    assert.is_true(wait_until(function()
      local mine = one:focus()
      local other = two:focus()
      return mine ~= nil and mine.id == second.id and other ~= nil and other.id == first.id
    end, 3000))
  end)

  it("moves a client to a fresh view when retargeting across groups", function()
    local first = create("g-cross-a", "codex")
    local second = create("g-cross-b", "claude")
    local attachment = attach(first)

    assert.are.equal(true, attachment:retarget(second))
    -- The handle adopted the fresh View: it still answers, and the group the
    -- client left no longer holds one.
    assert.is_true(wait_until(function()
      local focused = attachment:focus()
      return focused ~= nil and focused.id == second.id
    end, 3000))
    assert.are.same({}, group_views("g-cross-a"))
    assert.are.equal(1, #group_views("g-cross-b"))
  end)

  it("fails retarget with a readable reason when the View has no client", function()
    local first = create("g-empty-a", "codex")
    local second = create("g-empty-b", "claude")
    local attachment = attach_without_client(first)

    local ok, err = attachment:retarget(second)
    assert.are.equal(false, ok)
    assert.is_true(err:find("no client attached", 1, true) ~= nil)
  end)

  it("captures recent pane output", function()
    local agent = create("g-capture", "codex", "printf 'READY\\n'; exec sleep 300")
    assert.are.equal(
      true,
      wait_until(function()
        return capture_contains(agent, "READY")
      end, 3000)
    )
  end)

  it("sends text without submitting and leaves it readable from the pane", function()
    local agent = create("g-cat", "codex", "stty raw -echo; exec cat")
    vim.wait(300)

    assert.are.equal(true, Backend.send_keys(agent, "hello world"))
    assert.are.equal(
      true,
      wait_until(function()
        return capture_contains(agent, "hello world")
      end, 3000)
    )
  end)

  it("stages under this instance's pid name, consuming it and leaving others alone", function()
    local agent = create("g-send-name", "codex", "stty raw -echo; exec cat")
    vim.wait(300)
    -- A stale buffer under our own name, and one that belongs to a different
    -- Neovim instance: the send overwrites and consumes ours, and touches
    -- neither state nor the other instance's buffer.
    tmux("set-buffer", "-b", "vantage-send-" .. vim.fn.getpid(), "--", "stale")
    tmux("set-buffer", "-b", "vantage-send-999999", "--", "other instance")

    assert.are.equal(true, Backend.send_keys(agent, "mine"))

    assert.are.same({ "vantage-send-999999" }, staged_buffers())
    assert.are.equal(
      true,
      wait_until(function()
        return capture_contains(agent, "mine")
      end, 3000)
    )
  end)

  it("cleans up its own staging buffer when the paste target is gone", function()
    local agent = create("g-send-fail", "codex", "exec sleep 300")
    local gone = vim.tbl_extend("force", agent, { id = "@9999" })

    local ok, err = Backend.send_keys(gone, "text")

    assert.is_false(ok)
    assert.is_true(err:find("failed to paste prompt text", 1, true) ~= nil)
    assert.are.same({}, staged_buffers())
  end)

  it("kills one agent and leaves its group-mates alive", function()
    local first = create("g-kill-agent", "codex")
    local second = create("g-kill-agent", "codex")

    assert.are.equal(true, Backend.kill_agent(first))
    assert.are.equal(nil, find_agent(first.id))
    assert.are.same(second, find_agent(second.id))
  end)
end)
