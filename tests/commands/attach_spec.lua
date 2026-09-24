---@module 'luassert'

local Helpers = require("helpers")

describe("vantage.commands.attach", function()
  local Config
  local Attach
  local Entries
  local backend
  local picker
  local terminal
  local attachment_fixture
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
  --- to the Picker. `attached` runs the switch flow, which needs a live
  --- Terminal; without it the show flow finds none.
  ---@param attached? boolean
  ---@return table[]
  local function items_for(attached)
    captured_spec = nil
    if attached then
      terminal.attachment = attachment_fixture
      Attach.switch()
    else
      Attach.show()
    end
    assert.is_not_nil(captured_spec)
    return Helpers.entries(captured_spec)
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
    backend = { created = {}, captured = {}, retargeted = nil, killed = {} }
    function backend.inventory()
      return {
        agents = vim.deepcopy(agent_fixture),
        groups = { "a", "z" },
      }, nil
    end
    function backend.capture(agent)
      backend.captured[#backend.captured + 1] = agent.id
      return { "line" }, nil
    end
    function backend.create(opts)
      backend.created[#backend.created + 1] = opts
      return { group = opts.group, tool = opts.tool, id = "@9", seq = 9 }, nil
    end
    function backend.attach(agent, launch)
      if not launch({ "attach", agent.id }) then
        return nil, "failed to start the terminal"
      end
      return attachment_fixture, nil
    end
    function backend.kill_agent(agent)
      backend.killed[#backend.killed + 1] = agent.id
      return true, nil
    end

    picker = {}
    function picker.capabilities()
      return { command = command_capable }
    end
    function picker.pick_fancy(spec, opts)
      captured_spec, captured_opts = spec, opts
      if picker.auto_select then
        local index = picker.auto_select == true and 1 or picker.auto_select
        local items = Helpers.entries(spec)
        if items[index] then
          opts.on_choices({ items[index] })
        end
      end
    end
    function picker.pick_naive(_, _, on_choice)
      on_choice(picker.plain_choice)
    end

    attachment_fixture = {}
    function attachment_fixture:focus()
      if focused == nil then
        return nil, Config.FOCUS_NO_FOCUS
      end
      return focused, nil
    end
    function attachment_fixture:retarget(agent)
      backend.retargeted = { id = agent.id }
      return true, nil
    end

    terminal = {
      buffer = 77,
      attachment = nil,
      show_result = false,
      opened = nil,
      open_result = true,
    }
    function terminal.show()
      return terminal.show_result
    end
    function terminal.open(argv)
      terminal.opened = argv
      return terminal.open_result
    end
    function terminal.hold(attachment)
      terminal.attachment = attachment
    end

    package.loaded["vantage.backend"] = backend
    package.loaded["vantage.frontend.picker"] = picker
    package.loaded["vantage.frontend.terminal"] = terminal
    Attach = require("vantage.commands.attach")
    Entries = require("vantage.frontend.entries")
  end)

  teardown(function()
    Helpers.reload_vantage()
  end)

  before_each(function()
    focused = nil
    backend.created = {}
    backend.captured = {}
    backend.retargeted = nil
    backend.killed = {}
    captured_spec = nil
    captured_opts = nil
    command_capable = true
    picker.auto_select = false
    picker.plain_choice = "z"
    terminal.attachment = nil
    terminal.show_result = false
    terminal.opened = nil
    terminal.open_result = true
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
    local items = items_for(true)

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
    local items = items_for(true)

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

    assert.are.same({ "line" }, Entries.preview(entries[1]))
    assert.are.equal(nil, Entries.preview(items[#items]))
    assert.are.same({ "@1" }, backend.captured)
  end)

  it("creates the agent in the group chosen for a Tool entry", function()
    local items = items_for(true)
    picker.auto_select = #items -- the last entry is a Tool entry

    Attach.show()

    assert.are.equal("zeta", backend.created[1].tool)
    assert.are.equal("z", backend.created[1].group)
    assert.are.same({ "attach", "@9" }, terminal.opened)
  end)

  it("creates nothing when the Group choice is cancelled", function()
    local items = items_for(true)
    picker.auto_select = #items
    picker.plain_choice = nil

    Attach.show()

    assert.are.same({}, backend.created)
    assert.are.equal(nil, terminal.opened)
  end)

  it("opens a Terminal on an Agent created from a Tool entry when the list has no Focus", function()
    local items = items_for(nil)
    local tool = items[#items]
    picker.auto_select = #items

    Attach.show()

    assert.is_true(vim.endswith(tool.text, "zeta")) -- Tool entries sort by name
    assert.are.equal("zeta", backend.created[1].tool)
    assert.are.same({ "attach", "@9" }, terminal.opened)
  end)

  it("switch retargets the selected agent", function()
    terminal.attachment = attachment_fixture
    picker.auto_select = true
    Attach.switch()

    assert.are.same({ id = "@1" }, backend.retargeted)
  end)

  it("kills a non-focused agent entry in place with <c-x>", function()
    focused = agent_fixture[2]
    local items = items_for(true)
    local entry = items[2]

    assert.is_true(command_for("<C-x>")[2]({ item = entry, items = items }))
    assert.are.same({ entry.agent.id }, backend.killed)
  end)

  it("ignores <c-x> on the pinned focused entry and Tool entries", function()
    focused = agent_fixture[2]
    local items = items_for(true)
    local command = command_for("<C-x>")[2]

    assert.is_false(command({ item = items[1], items = items }))
    assert.is_false(command({ item = items[#items], items = items }))
    assert.are.same({}, backend.killed)
  end)

  it("show opens the terminal on the chosen agent, handing it only argv", function()
    picker.auto_select = true
    Attach.show()

    assert.are.same({ "attach", "@1" }, terminal.opened)
  end)

  it("shows a live Terminal without picking an Agent", function()
    terminal.show_result = true

    Attach.show()

    assert.is_nil(captured_spec)
    assert.is_nil(terminal.opened)
  end)

  it("holds no attachment when the terminal cannot start", function()
    picker.auto_select = true
    terminal.open_result = false

    Attach.show()

    assert.are.same({ "attach", "@1" }, terminal.opened)
    assert.is_nil(terminal.attachment)
  end)

  it("warns the read's reason from its own source", function()
    local notified = {}
    local original_notify = vim.notify
    vim.notify = function(msg)
      notified[#notified + 1] = msg
    end
    backend.inventory = function()
      return nil, "no server running"
    end

    Attach.show()
    local items = Helpers.entries(captured_spec)
    vim.notify = original_notify

    assert.are.same({}, items)
    assert.are.same({ "vantage: no server running" }, notified)
  end)
end)
