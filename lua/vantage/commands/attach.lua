--- The Terminal attachment flows and the shared Agent picker they use.
---
--- `show` owns Terminal presence; `switch` owns the attached client's
--- target. The Agent/Tool entries, Group prompt, and creation handoff are
--- local to this module because both flows are their only consumers.
local Backend = require("vantage.backend")
local Config = require("vantage.config")
local Entries = require("vantage.frontend.entries")
local Picker = require("vantage.frontend.picker")
local Terminal = require("vantage.frontend.terminal")
local Util = require("vantage.util")

local M = {}

local PROMPT = Util.picker_prompt

--- The Group prompt's completion: existing Group names with `lead` as a
--- prefix. `customlist` completion does no filtering of its own, so the
--- function does it; the prompt's own spelling is not rewritten — a partial
--- name the user confirms stays that name.
---@param lead string
---@param _line string
---@param _pos integer
---@return string[]
function M.complete_groups(lead, _line, _pos)
  local inventory = Backend.inventory()
  if inventory == nil then
    return {}
  end
  local names = {}
  for _, group in ipairs(inventory.groups) do
    if vim.startswith(group, lead) then
      names[#names + 1] = group
    end
  end
  table.sort(names)
  return names
end

--- The Agent entries' ascending order: group, cwd, tool name, then creation seq.
---@param left vantage.Agent
---@param right vantage.Agent
---@return boolean
local function agent_order(left, right)
  if left.group ~= right.group then
    return left.group < right.group
  end
  if left.cwd ~= right.cwd then
    return left.cwd < right.cwd
  end
  if left.tool ~= right.tool then
    return left.tool < right.tool
  end
  return left.seq < right.seq
end

---@param agents vantage.Agent[]
---@param focused vantage.Agent?
---@return vantage.picker.Entry[]
local function build_items(agents, focused)
  local items = {}
  table.sort(agents, agent_order)
  if focused then
    items[#items + 1] = Entries.agent(focused, true)
  end
  for _, agent in ipairs(agents) do
    if not focused or agent.id ~= focused.id then
      items[#items + 1] = Entries.agent(agent)
    end
  end
  local tools = vim.tbl_keys(Config.options.cli.tools)
  table.sort(tools)
  for _, name in ipairs(tools) do
    items[#items + 1] = Entries.tool(name)
  end
  return items
end

--- The Agent-list selection spec: every Group's Agents plus the configured
--- Tools, with the Terminal's own Focus pinned first when it has one.
---@param attachment? vantage.Attachment this Terminal's attachment, when it has one
---@return vantage.PickSpec
local function spec(attachment)
  return {
    prompt = PROMPT,
    many = false,
    preview = Entries.preview,
    items = function(emit, done)
      local inventory, err = Backend.inventory()
      if inventory == nil then
        Util.warn(err or "failed to read agents")
        return done()
      end
      -- The Focus is a second read: the inventory never carries it, and only
      -- the Terminal's own attachment can answer it.
      local focused = attachment and attachment:focus() or nil
      emit(build_items(inventory.agents, focused))
      done()
    end,
  }
end

--- Kill the current entry's Agent in place. The pinned `(focused)` entry is
--- the Agent the Terminal is attached to, and a Tool entry has no Agent yet,
--- so both are no-ops. Returns true when the list may have changed.
---@param ctx vantage.PickerCommandCtx
---@return boolean
local function kill_agent(ctx)
  local entry = ctx.item
  if not entry or entry.kind ~= "agent" then
    return false
  end
  ---@cast entry vantage.picker.AgentEntry
  local ok, err = Backend.kill_agent(entry.agent)
  if not ok then
    Util.warn(err or "failed to kill agent")
    return false
  end
  return true
end

--- Pick an Agent to act on, resolving the chosen entry (creating an Agent from
--- a Tool entry when that is what was chosen). Creating from a Tool entry asks
--- for a Group through a synchronous completion-backed cmdline prompt; the
--- name it answers is this creation's Group and nothing else.
---@param after fun(agent: vantage.Agent)
---@param attachment? vantage.Attachment the Terminal's attachment, when it has one
local function pick(after, attachment)
  Picker.pick_fancy(spec(attachment), {
    on_choices = function(entries)
      local entry = entries[1]
      if entry.kind == "focused" then
        return
      end
      if entry.kind == "agent" then
        ---@cast entry vantage.picker.AgentEntry
        after(entry.agent)
        return
      end
      ---@cast entry vantage.picker.ToolEntry
      -- The prompt takes the whole creation flow inline: its return value is
      -- this call's Group, so no continuation wraps the step. `cancelreturn`
      -- answers Esc with vim.NIL (userdata, not nil), and CTRL-C interrupts
      -- the prompt with an error; both mean "no Group", so nothing is created.
      local ok, answer = pcall(vim.fn.input, {
        prompt = "Group: ",
        default = "",
        completion = "customlist,v:lua.require'vantage.commands.attach'.complete_groups",
        cancelreturn = vim.NIL,
      })
      if not ok or answer == nil or answer == vim.NIL then
        return
      end
      local group = vim.trim(answer)
      if group == "" then
        return
      end
      local agent, err = Backend.create({ group = group, tool = entry.name, cwd = Util.cwd() })
      if not agent then
        Util.warn(err or "failed to create agent")
        return
      end
      after(agent)
    end,
    commands = {
      {
        "<C-x>",
        kill_agent,
        desc = "kill agent",
      },
    },
  })
end

--- Attach a new Terminal client to `agent`. The Terminal installs its own
--- keymaps from the resolver the composition root installed. The Backend rolls
--- its View back when the client cannot start, so a failed open leaves no
--- session behind.
---@param agent vantage.Agent
local function open_on(agent)
  local attachment, err = Backend.attach(agent, function(argv)
    return Terminal.open(argv)
  end)
  if not attachment then
    Util.warn(err or "failed to attach the terminal")
    return
  end
  Terminal.hold(attachment)
end

--- Show the Terminal: focus it when it is up, re-open it when it is hidden, and
--- with no Terminal pick an Agent and open one on it.
function M.show()
  if Terminal.show() then
    return
  end
  pick(open_on)
end

--- Re-point the live Terminal to another Agent.
function M.switch()
  -- `switch` is installed only on the Terminal's own buffer, so its client
  -- exists by construction.
  local attachment = assert(Terminal.attachment, "vantage: switch needs an attached terminal")

  pick(function(agent)
    local ok, err = attachment:retarget(agent)
    if not ok then
      Util.warn(err or "failed to switch agent")
    end
  end, attachment)
end

return M
