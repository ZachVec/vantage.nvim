---@module 'luassert'

local Helpers = require("helpers")

describe("vantage.backend.tmux", function()
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

  local function sleep(ms)
    vim.wait(ms)
  end

  local function wait_until(condition, timeout_ms)
    local waited = 0
    while waited < timeout_ms do
      if condition() then
        return true
      end
      sleep(50)
      waited = waited + 50
    end
    return condition()
  end

  local function capture_contains(target, needle)
    for _, line in ipairs(Backend.capture_pane(target, 200)) do
      if line:find(needle, 1, true) then
        return true
      end
    end
    return false
  end

  local function find_agent(target)
    for _, agent in ipairs(Backend.list()) do
      if agent.target == target then
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

  setup(function()
    if vim.fn.executable("tmux") ~= 1 then
      error("tmux is required for vantage.backend.tmux specs")
    end
    Helpers.reload_vantage()
    Config = require("vantage.config")
    Util = require("vantage.util")
    socket = "vantage-test-" .. vim.fn.getpid()
    Config.options.socket = socket
    Backend = require("vantage.backend").get()
    reset_server()
  end)

  before_each(function()
    reset_server()
  end)

  teardown(function()
    reset_server()
    Helpers.reload_vantage()
  end)

  it("reports no server before the first agent is created", function()
    assert.are.equal(false, Backend.ensure_server())
    assert.are.equal(false, Backend.has_session("g-missing"))
  end)

  it("creates an agent in a new group with the domain metadata", function()
    local agent = create("g-one", "codex")
    assert.are.equal("g-one", agent.group)
    assert.are.equal("codex", agent.tool)
    assert.are.equal("/tmp", agent.cwd)
    assert.are.equal("idle", agent.state)
    assert.is_true(agent.target:match("^@%d+$") ~= nil)

    assert.are.equal(true, Backend.has_session("g-one"))
    assert.are.same({ "g-one" }, Backend.groups())
    assert.are.same(agent, find_agent(agent.target))
    assert.are.equal(1, #Backend.group_views("g-one"))

    local status = Backend.status()
    assert.is_true(#status.sessions >= 1)
    assert.are.equal("tmux", vim.split(Backend.health()[1].message, " ", { plain = true })[1])
  end)

  it("adds a second agent to an existing group and dedupes list windows", function()
    local first = create("g-shared", "codex")
    local second = create("g-shared", "claude", "exec sleep 200")

    assert.are.same({ "g-shared" }, Backend.groups())
    assert.are.equal(2, #Backend.list())
    assert.are.same(second, find_agent(second.target))
    assert.is_true(find_agent(first.target) ~= nil)
  end)

  it("snapshot returns agents and derived groups from one inventory read", function()
    create("g-snap-a", "codex")
    create("g-snap-b", "claude")

    local snapshot = Backend.snapshot()
    assert.are.equal(2, #snapshot.agents)
    assert.are.same({ "g-snap-a", "g-snap-b" }, snapshot.groups)
  end)

  it("captures recent pane output", function()
    local agent = create("g-capture", "codex", "printf 'READY\\n'; exec sleep 300")
    assert.are.equal(
      true,
      wait_until(function()
        return capture_contains(agent.target, "READY")
      end, 3000)
    )
  end)

  it("sends text without submitting and leaves it readable from the pane", function()
    local agent = create("g-cat", "codex", "stty raw -echo; exec cat")
    sleep(300)

    Backend.send_keys(agent.target, "hello world")
    assert.are.equal(
      true,
      wait_until(function()
        return capture_contains(agent.target, "hello world")
      end, 3000)
    )
  end)

  it("attaches a view and retargets within the same group", function()
    local agent = create("g-retarget", "codex")
    local view = Backend.attach("g-retarget", agent.target)

    assert.is_true(view ~= nil)
    assert.are.equal(true, Backend.has_session(view))
    assert.are.equal(2, #Backend.group_views("g-retarget"))
    assert.are.equal(view, Backend.retarget(view, "g-retarget", agent.target))
    assert.are.equal(true, Backend.has_session(view))

    assert.are.same({ "tmux", "-L", socket, "attach-session", "-t", view }, Backend.client_command(view))
  end)

  it("fails a cross-group retarget cleanly when no client is attached", function()
    local first = create("g-cross-a", "codex")
    local second = create("g-cross-b", "codex")
    local view = Backend.attach("g-cross-a", first.target)
    local second_views = #Backend.group_views("g-cross-b")

    assert.are.equal(nil, Backend.retarget(view, "g-cross-b", second.target))
    assert.are.equal(true, Backend.has_session(view))
    assert.are.equal(second_views, #Backend.group_views("g-cross-b"))
  end)

  it("kills one agent and leaves its group-mates alive", function()
    local first = create("g-kill-agent", "codex")
    local second = create("g-kill-agent", "codex")

    Backend.kill(first.target)
    assert.are.equal(nil, find_agent(first.target))
    assert.are.same(second, find_agent(second.target))
  end)

  it("kills an entire group", function()
    create("g-kill-group", "codex")

    Backend.kill("g-kill-group")
    assert.are.equal(false, Backend.has_session("g-kill-group"))
    assert.are.same({}, Backend.groups())
  end)
end)
