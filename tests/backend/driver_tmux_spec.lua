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
    for _, line in ipairs(Backend.capture_pane(agent, 200)) do
      if line:find(needle, 1, true) then
        return true
      end
    end
    return false
  end

  local function find_agent(target)
    for _, agent in ipairs(Backend.snapshot().agents) do
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
      error("tmux is required for vantage.backend.driver.tmux specs")
    end
    Helpers.reload_vantage()
    Config = require("vantage.config")
    Util = require("vantage.util")
    socket = "vantage-test-" .. vim.fn.getpid()
    Config.options.socket = socket
    Backend = require("vantage.backend.driver").get()
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
    assert.are.same({ agents = {}, groups = {}, focused = nil }, Backend.snapshot())
    assert.are.same({ clients = {}, sessions = {} }, Backend.status())
    assert.are.equal("tmux", vim.split(Backend.health()[1].message, " ", { plain = true })[1])
  end)

  it("creates an agent in a new group with the domain metadata", function()
    local agent = create("g-one", "codex")
    assert.are.equal("g-one", agent.group)
    assert.are.equal("codex", agent.tool)
    assert.are.equal("/tmp", agent.cwd)
    assert.are.equal("idle", agent.state)
    assert.is_true(agent.target:match("^@%d+$") ~= nil)

    assert.are.same(agent, find_agent(agent.target))
    assert.are.same(
      { "tmux", "-L", socket, "attach-session", "-t", "g-one:" .. agent.target },
      Backend.attach_command("g-one", agent.target)
    )
    assert.is_true(#Backend.status().sessions >= 1)
  end)

  it("adds a second agent to an existing group", function()
    local first = create("g-shared", "codex")
    local second = create("g-shared", "claude", "exec sleep 200")

    assert.are.equal(2, #Backend.snapshot().agents)
    assert.are.same(second, find_agent(second.target))
    assert.is_true(find_agent(first.target) ~= nil)
  end)

  it("derives the focused agent from the terminal job's pid and retargets across groups", function()
    local first = create("g-focus-a", "codex")
    local second = create("g-focus-b", "claude")

    local job = vim.fn.jobstart(
      { "tmux", "-L", socket, "attach-session", "-t", "g-focus-a:" .. first.target },
      { pty = true }
    )
    local pid = vim.fn.jobpid(job)
    assert.is_true(wait_until(function()
      return Backend.snapshot(pid).focused ~= nil and Backend.snapshot(pid).focused.target == first.target
    end, 3000))

    assert.are.equal(true, Backend.retarget(pid, second))
    assert.is_true(wait_until(function()
      return Backend.snapshot(pid).focused ~= nil and Backend.snapshot(pid).focused.target == second.target
    end, 3000))
    vim.fn.jobstop(job)
  end)

  it("warns and fails retarget when no client has the pid", function()
    local agent = create("g-noclient", "codex")
    assert.are.equal(false, Backend.retarget(123456789, agent))
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

    Backend.send_keys(agent, "hello world")
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

    Backend.kill_agent(first)
    assert.are.equal(nil, find_agent(first.target))
    assert.are.same(second, find_agent(second.target))
  end)

  it("kills an entire group", function()
    create("g-kill-group", "codex")

    Backend.kill_group("g-kill-group")
    assert.are.same({}, Backend.snapshot().agents)
  end)
end)
