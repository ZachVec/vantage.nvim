---@module 'luassert'

local Helpers = require("helpers")

describe("vantage.commands.attach", function()
  local Config
  local Attach
  local bridge
  local picker
  local terminal
  local actions
  local captured_spec
  local command_capable
  local focused
  local agent_fixture

  --- Capture what a row hands to its target continuation.
  ---@param item vantage.AgentPickerEntry
  ---@return vantage.Agent?
  local function resolved(item)
    local agent
    item:target(function(a)
      agent = a
    end)
    return agent
  end

  local function agent_rows(items)
    local out = {}
    for _, item in ipairs(items) do
      if item.group ~= nil then
        out[#out + 1] = item
      end
    end
    return out
  end

  local function tool_names(items)
    local out = {}
    for _, item in ipairs(items) do
      if item.group == nil then
        out[#out + 1] = item:format():match("%S+$")
      end
    end
    return out
  end

  --- Run a public flow without selecting a row and return the spec it passed
  --- to the Picker.
  ---@param pid? integer
  ---@return table[]
  local function items_for(pid)
    captured_spec = nil
    if pid then
      terminal.pid_value = pid
      Attach.switch()
    else
      Attach.toggle()
    end
    assert.is_not_nil(captured_spec)
    return captured_spec.items_provider()
  end

  setup(function()
    Helpers.reload_vantage()
    Config = require("vantage.config")
    Config.options.cli.tools = {
      zeta = { cmd = { "zeta" } },
      alpha = { cmd = { "alpha" } },
    }

    agent_fixture = {
      { group = "z", cwd = "/z", tool = "codex", id = "@4", seq = 4, cmd = "codex" },
      { group = "a", cwd = "/b", tool = "codex", id = "@2", seq = 2, cmd = "codex" },
      { group = "a", cwd = "/a", tool = "zeta", id = "@3", seq = 3, cmd = "zeta" },
      { group = "a", cwd = "/a", tool = "zeta", id = "@1", seq = 1, cmd = "zeta" },
    }
    bridge = { created = {}, captured = {}, retargeted = nil }
    function bridge.agents(pid)
      return {
        agents = vim.deepcopy(agent_fixture),
        groups = { "a", "z" },
        focused = (pid ~= nil and focused) or nil,
      },
        nil
    end
    function bridge.capture(agent)
      bridge.captured[#bridge.captured + 1] = agent.id
      return { "line" }, nil
    end
    function bridge.create(opts)
      bridge.created[#bridge.created + 1] = opts
      return { group = opts.group, tool = opts.tool, id = "@9", seq = 9 }, nil
    end
    function bridge.attach(agent)
      return { view = "view-1", argv = { "attach", agent.id } }, nil
    end
    function bridge.kill_view(view)
      bridge.killed_view = view
      return true, nil
    end
    function bridge.retarget(pid, agent)
      bridge.retargeted = { pid = pid, id = agent.id }
      return true, nil
    end

    picker = {}
    function picker.capabilities()
      return { preview = true, command = command_capable }
    end
    function picker.pick(spec, opts)
      captured_spec = spec
      if picker.auto_select then
        local items = spec.items_provider()
        if #items > 0 then
          opts.on_choice(items[1])
        end
      end
      return false
    end
    function picker.pick_plain(_, _, on_choice)
      on_choice("z")
    end

    terminal = { buffer = 77, pid_value = 42, toggle_result = false, opened = nil }
    function terminal.toggle()
      return terminal.toggle_result
    end
    function terminal.pid()
      return terminal.pid_value
    end
    function terminal.open(argv)
      terminal.opened = argv
      return true
    end

    actions = { applied = nil }
    package.loaded["vantage.backend.bridge"] = bridge
    package.loaded["vantage.frontend.picker"] = picker
    package.loaded["vantage.frontend.terminal"] = terminal
    package.loaded["vantage.commands.actions"] = {
      apply = function(buffer)
        actions.applied = buffer
      end,
    }
    Attach = require("vantage.commands.attach")
  end)

  teardown(function()
    Helpers.reload_vantage()
  end)

  before_each(function()
    focused = nil
    bridge.created = {}
    bridge.captured = {}
    bridge.retargeted = nil
    bridge.killed_view = nil
    captured_spec = nil
    command_capable = true
    picker.auto_select = false
    terminal.pid_value = 42
    terminal.toggle_result = false
    terminal.opened = nil
    actions.applied = nil
  end)

  it("orders agent rows by group, cwd, tool, then creation seq, and tools by name", function()
    local items = items_for(nil)
    local rows = agent_rows(items)

    assert.are.same(
      { "@1", "@3", "@2", "@4" },
      vim.tbl_map(function(r)
        return resolved(r).id
      end, rows)
    )
    assert.are.same({ "alpha", "zeta" }, tool_names(items))
  end)

  it("pins the focused agent first, excluded from the sorted rows, and its resolve no-ops", function()
    focused = agent_fixture[2]
    command_capable = false
    local items = items_for(42)

    assert.is_true(vim.endswith(items[1]:format(), "(focused)"))
    assert.are.equal(nil, resolved(items[1]))
    local rest = {}
    for i = 2, #items do
      if items[i].group ~= nil then
        rest[#rest + 1] = items[i]
      end
    end
    assert.are.same(
      { "@1", "@3", "@4" },
      vim.tbl_map(function(r)
        return resolved(r).id
      end, rest)
    )
  end)

  it("scopes the list to the focused agent's group, keeping tool rows", function()
    focused = agent_fixture[2]
    local items = items_for(42)

    assert.are.equal(5, #items) -- pinned + 2 group-mates + 2 tools
    assert.are.equal(3, #agent_rows(items))
  end)

  it("formats rows with tool, group, and cwd", function()
    local item = items_for(nil)[1]
    assert.are.equal("zeta · a · /a", item:format():gsub("^.*  ", ""))
  end)

  it("previews agent panes and returns nil for tool rows", function()
    local items = items_for(nil)
    local rows = agent_rows(items)

    assert.are.same({ "line" }, rows[1]:preview())
    assert.are.equal(nil, items[#items]:preview())
    assert.are.same({ "@1" }, bridge.captured)
  end)

  it("tool rows ask for a group and create the agent there", function()
    local items = items_for(42)
    local tool = items[#items]
    assert.are.equal("z", resolved(tool).group)
    assert.are.equal("z", bridge.created[1].group)
  end)

  it("switch retargets the selected agent", function()
    picker.auto_select = true
    Attach.switch()

    assert.are.same({ pid = 42, id = "@1" }, bridge.retargeted)
  end)

  it("toggle opens the terminal and installs keys when no terminal exists", function()
    picker.auto_select = true
    Attach.toggle()

    assert.are.same({ "attach", "@1" }, terminal.opened)
    assert.are.equal(77, actions.applied)
  end)
end)
