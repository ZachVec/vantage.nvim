--- The shared send path of the flows that type text into the focused Agent:
--- resolve the Agent, render location references through its Tool's `format`
--- hook, and paste the result through the Bridge. Flows keep their own
--- warnings; this module owns how a reference is spelled and how a send is
--- shaped.
local Bridge = require("vantage.backend.bridge")
local Config = require("vantage.config")
local Terminal = require("vantage.frontend.terminal")
local Util = require("vantage.util")

local M = {}

--- The focused Agent of this Neovim instance, or nil plus a user-facing
--- reason when there is nothing to send to.
---@return vantage.Agent?
---@return string?
function M.focused()
  local snapshot, err = Bridge.agents(Terminal.pid())
  if snapshot == nil then
    return nil, err or "failed to read agents"
  end
  if not snapshot.focused then
    return nil, "no focused agent — use :Vantage toggle first"
  end
  return snapshot.focused
end

---@param agent vantage.Agent
---@return vantage.Tool?
local function tool_of(agent)
  return Config.options.cli.tools[agent.tool]
end

--- The reference formatter of `agent`'s Tool: its `format(file, loc)` hook, or
--- `Util.reference` when the Tool defines none. A hook that returns nil or ""
--- gives up on that reference, which callers see as nil.
---@param agent vantage.Agent
---@return vantage.ReferenceFormat
function M.formatter(agent)
  local tool = tool_of(agent)
  local format = tool and tool.format or Util.reference
  return function(file, loc)
    local ref = format(file, loc)
    if ref == nil or ref == "" then
      return nil
    end
    return ref
  end
end

--- Paste `text` into the Agent's input (no auto-submit).
---@param agent vantage.Agent
---@param text string
---@return boolean
---@return string?
function M.send(agent, text)
  return Bridge.send(agent, text)
end

--- Paste gathered `files` (one bare `<relpath>` per entry) into the Agent's
--- input. Every path runs through the Tool's reference formatter, the results
--- are joined with `setup { gather = { join = … } }`, and a trailing space
--- keeps continued typing off the last reference; there is no trailing newline
--- (a pasted trailing newline shows as an empty line in the Agent's input). A
--- formatter returning nil or "" drops the send.
---@param agent vantage.Agent
---@param files string[]
---@return boolean
---@return string?
function M.references(agent, files)
  local format = M.formatter(agent)
  local formatted = {}
  for _, file in ipairs(files) do
    local ref = format(file, nil)
    if ref == nil then
      return false, "dropped by its format hook"
    end
    formatted[#formatted + 1] = ref
  end
  return M.send(agent, table.concat(formatted, Config.options.gather.join) .. " ")
end

return M
