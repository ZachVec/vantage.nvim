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
  local captured_opts
  local command_capable
  local focused
  local agent_fixture

  --- The Agent an entry names when chosen, or nil for the pinned Focus entry
  --- and for Tool entries (which create instead of naming).
  ---@param entry vantage.picker.Entry
  ---@return vantage.Agent?
  local function resolved(entry)
    return entry.kind == "agent" and entry.agent or nil
  end

  local function agent_entries(items)
    local out = {}
    for _, entry in ipairs(items) do
      if entry.agent ~= nil then
        out[#out + 1] = entry
      end
    end
    return out
  end

  local function tool_names(items)
    local out = {}
    for _, entry in ipairs(items) do
      if entry.kind == "tool" then
        out[#out + 1] = entry.text:match("%S+$")
      end
    end
    return out
  end

  --- The picker command registered for `lhs` by the last pick.
  ---@param lhs string
  ---@return vantage.PickerCommand
  local function command_for(lhs)
    assert.is_not_nil(captured_opts)
    for _, command in ipairs(captured_opts.commands) do
      if command[1] == lhs then
        return command
      end
    end
    error(("no picker command registered for %s"):format(lhs))
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
    bridge = { created = {}, captured = {}, retargeted = nil, killed = {} }
    function bridge.inventory()
      return {
        agents = vim.deepcopy(agent_fixture),
        groups = { "a", "z" },
      }, nil
    end
    function bridge.focus(pid)
      -- The real Bridge answers "no terminal" for a nil pid; the flows under
      -- test only consume the Agent.
      if pid == nil then
        return nil, Config.FOCUS_NO_TERMINAL
      end
      if focused == nil then
        return nil, Config.FOCUS_NO_FOCUS
      end
      return focused, nil
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
    function bridge.kill_agent(agent)
      bridge.killed[#bridge.killed + 1] = agent.id
      return true, nil
    end

    picker = {}
    function picker.capabilities()
      return { preview = true, command = command_capable }
    end
    function picker.pick(spec, opts)
      captured_spec = spec
      captured_opts = opts
      -- Answer the way an implementation does: the opening read carries the
      -- reason when the list could not be read.
      local items, err = spec.items_provider()
      if picker.auto_select then
        local index = picker.auto_select == true and 1 or picker.auto_select
        if items[index] then
          opts.on_choice(items[index])
        end
      end
      return #items == 0, err
    end
    function picker.pick_plain(_, _, on_choice)
      on_choice(picker.plain_choice)
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
    bridge.killed = {}
    captured_spec = nil
    captured_opts = nil
    command_capable = true
    picker.auto_select = false
    picker.plain_choice = "z"
    terminal.pid_value = 42
    terminal.toggle_result = false
    terminal.opened = nil
    actions.applied = nil
  end)

  it("orders agent entries by group, cwd, tool, then creation seq, and tools by name", function()
    local items = items_for(nil)
    local entries = agent_entries(items)

    assert.are.same(
      { "@1", "@3", "@2", "@4" },
      vim.tbl_map(function(r)
        return resolved(r).id
      end, entries)
    )
    assert.are.same({ "alpha", "zeta" }, tool_names(items))
  end)

  it("pins the focused agent first, excluded from the sorted entries, and choosing it names nothing", function()
    focused = agent_fixture[2]
    command_capable = false
    local items = items_for(42)

    assert.is_true(vim.endswith(items[1].text, "(focused)"))
    assert.are.equal(nil, resolved(items[1]))
    local rest = {}
    for i = 2, #items do
      if items[i].agent ~= nil then
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

  it("scopes the list to the focused agent's group, keeping tool entries", function()
    focused = agent_fixture[2]
    local items = items_for(42)

    assert.are.equal(5, #items) -- pinned + 2 group-mates + 2 tools
    assert.are.equal(3, #agent_entries(items))
  end)

  it("formats entries with tool, group, and cwd", function()
    local entry = items_for(nil)[1]
    assert.are.equal("zeta · a · /a", entry.text:gsub("^.*  ", ""))
  end)

  it("previews agent panes and returns nil for tool entries", function()
    local items = items_for(nil)
    local entries = agent_entries(items)

    assert.are.same({ "line" }, entries[1]:preview())
    assert.are.equal(nil, items[#items]:preview())
    assert.are.same({ "@1" }, bridge.captured)
  end)

  it("creates the agent in the group chosen for a Tool entry", function()
    local items = items_for(42)
    picker.auto_select = #items -- the last entry is a Tool entry

    Attach.toggle()

    assert.are.equal("zeta", bridge.created[1].tool)
    assert.are.equal("z", bridge.created[1].group)
    assert.are.same({ "attach", "@9" }, terminal.opened)
  end)

  it("creates nothing when the Group choice is cancelled", function()
    local items = items_for(42)
    picker.auto_select = #items
    picker.plain_choice = nil

    Attach.toggle()

    assert.are.same({}, bridge.created)
    assert.are.equal(nil, terminal.opened)
  end)

  it("opens a Terminal on an Agent created from a Tool entry when the list has no Focus", function()
    local items = items_for(nil)
    local tool = items[#items]
    picker.auto_select = #items

    Attach.toggle()

    assert.is_true(vim.endswith(tool.text, "zeta")) -- Tool entries sort by name
    assert.are.equal("zeta", bridge.created[1].tool)
    assert.are.same({ "attach", "@9" }, terminal.opened)
  end)

  it("switch retargets the selected agent", function()
    picker.auto_select = true
    Attach.switch()

    assert.are.same({ pid = 42, id = "@1" }, bridge.retargeted)
  end)

  it("kills a non-focused agent entry in place with <c-x>", function()
    focused = agent_fixture[2]
    local items = items_for(42)
    local entry = items[2]

    assert.is_true(command_for("<C-x>")[2]({ item = entry, items = items }))
    assert.are.same({ entry.agent.id }, bridge.killed)
  end)

  it("ignores <c-x> on the pinned focused entry and Tool entries", function()
    focused = agent_fixture[2]
    local items = items_for(42)
    local command = command_for("<C-x>")[2]

    assert.is_false(command({ item = items[1], items = items }))
    assert.is_false(command({ item = items[#items], items = items }))
    assert.are.same({}, bridge.killed)
  end)

  it("toggle opens the terminal and installs keys when no terminal exists", function()
    picker.auto_select = true
    Attach.toggle()

    assert.are.same({ "attach", "@1" }, terminal.opened)
    assert.are.equal(77, actions.applied)
  end)

  it("warns the read's reason instead of the empty list message", function()
    local notified = {}
    local original_notify = vim.notify
    vim.notify = function(msg)
      notified[#notified + 1] = msg
    end
    bridge.inventory = function()
      return nil, "no server running"
    end

    Attach.toggle()
    vim.notify = original_notify

    assert.are.same({ "vantage: no server running" }, notified)
  end)
end)
