---@module 'luassert'

local Helpers = require("helpers")

describe("vantage.backend.driver.tmux", function()
  local Backend
  local Config
  local Util
  local socket

  local function tmux(...)
    return Util.run({ "tmux", "-L", socket, ... })
  end

  local function reset_server()
    tmux("kill-server") -- exit 1 when no server exists; that is expected here
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
    local snapshot = Backend.snapshot()
    for _, agent in ipairs(snapshot.agents) do
      if agent.id == id then
        return agent
      end
    end
    return nil
  end

  local function create(group, tag, cmd)
    return Backend.create({
      group = group,
      cmd = cmd or "exec sleep 300",
      cwd = "/tmp",
      tool = tag,
    })
  end

  local function attach_job(agent)
    local attachment, err = Backend.attach(agent)
    assert.are.equal(nil, err)
    assert.is_not_nil(attachment)
    local job = vim.fn.jobstart(attachment.argv, { pty = true })
    assert.is_true(job > 0)
    return job, vim.fn.jobpid(job), attachment.view
  end

  setup(function()
    if vim.fn.executable("tmux") ~= 1 then
      error("tmux is required for vantage.backend.driver.tmux specs")
    end
    Helpers.reload_vantage()
    Config = require("vantage.config")
    Util = require("vantage.util")
    socket = "vantage-test-" .. vim.fn.getpid()
    Config.options.socket = socket
    local Driver = require("vantage.backend.driver")
    Driver.setup()
    Backend = Driver.get()
    reset_server()
  end)

  before_each(function()
    reset_server()
  end)

  teardown(function()
    reset_server()
    Helpers.reload_vantage()
  end)

  it("reports an empty snapshot before the first agent is created", function()
    local snapshot, snapshot_err = Backend.snapshot()
    local status_info, status_err = Backend.status()
    assert.are.equal(nil, snapshot_err)
    assert.are.equal(nil, status_err)
    assert.are.same({ agents = {}, groups = {}, focused = nil }, snapshot)
    assert.are.same({ clients = {}, sessions = {} }, status_info)
    assert.are.equal("tmux", vim.split(Backend.health()[1].message, " ", { plain = true })[1])
  end)

  it("implements the vantage.Driver surface", function()
    for _, name in ipairs({
      "create",
      "snapshot",
      "retarget",
      "attach",
      "kill_view",
      "kill_agent",
      "kill_group",
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
    local attachment, attach_err = Backend.attach(agent)
    assert.are.equal(nil, attach_err)
    assert.is_not_nil(attachment)
    assert.are.same({ "tmux", "-L", socket, "attach-session", "-t", attachment.view }, attachment.argv)
    assert.is_true(#Backend.status().sessions >= 2)
  end)

  it("adds a second agent to an existing group", function()
    local first = create("g-shared", "codex")
    local second = create("g-shared", "claude", "exec sleep 200")

    local snapshot = Backend.snapshot()
    assert.are.equal(2, #snapshot.agents)
    assert.are.same(second, find_agent(second.id))
    assert.is_true(find_agent(first.id) ~= nil)
  end)

  it("keeps two clients in one group on independent views", function()
    local first = create("g-focus", "codex")
    local second = create("g-focus", "claude")
    local job1, pid1 = attach_job(first)
    local job2, pid2 = attach_job(first)

    assert.is_true(wait_until(function()
      local snapshot = Backend.snapshot(pid1)
      return snapshot.focused ~= nil and snapshot.focused.id == first.id
    end, 3000))
    assert.is_true(wait_until(function()
      local snapshot = Backend.snapshot(pid2)
      return snapshot.focused ~= nil and snapshot.focused.id == first.id
    end, 3000))

    assert.are.equal(true, Backend.retarget(pid1, second))
    assert.is_true(wait_until(function()
      local one = Backend.snapshot(pid1)
      local two = Backend.snapshot(pid2)
      return one.focused ~= nil and one.focused.id == second.id and two.focused ~= nil and two.focused.id == first.id
    end, 3000))
    vim.fn.jobstop(job1)
    vim.fn.jobstop(job2)
  end)

  it("moves a client to a fresh view when retargeting across groups", function()
    local first = create("g-cross-a", "codex")
    local second = create("g-cross-b", "claude")
    local job, pid = attach_job(first)

    assert.are.equal(true, Backend.retarget(pid, second))
    assert.is_true(wait_until(function()
      local snapshot = Backend.snapshot(pid)
      return snapshot.focused ~= nil and snapshot.focused.id == second.id
    end, 3000))
    vim.fn.jobstop(job)
  end)

  it("warns and fails retarget when no client has the pid", function()
    local agent = create("g-noclient", "codex")
    local ok, err = Backend.retarget(123456789, agent)
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

  it("kills one agent and leaves its group-mates alive", function()
    local first = create("g-kill-agent", "codex")
    local second = create("g-kill-agent", "codex")

    assert.are.equal(true, Backend.kill_agent(first))
    assert.are.equal(nil, find_agent(first.id))
    assert.are.same(second, find_agent(second.id))
  end)

  it("kills an entire group", function()
    create("g-kill-group", "codex")

    assert.are.equal(true, Backend.kill_group("g-kill-group"))
    assert.are.same({}, Backend.snapshot().agents)
  end)
end)
