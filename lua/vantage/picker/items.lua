--- Shared picker domain: builds the rich items each picker implementation
--- renders (the Agent list and the kill list). Every item carries a `text`
--- display string plus whatever domain fields its callback needs;
--- implementations own only the rendering and the recovery of the chosen item.
--- Plain selections with nothing to preview (the Tool and Group choice) live in
--- `vantage.select`.
local Backend = require("vantage.backend")
local Util = require("vantage.util")

local M = {}

--- The picker prompt: a single angle-right glyph (U+F105, e.g. Nerd Font).
M.prompt = Util.picker_prompt

---@param agent vantage.Agent
---@return string
function M.format_agent(agent)
  return ("%s  %s  [%s]"):format(agent.cmd, Util.tilde(agent.cwd), agent.group)
end

--- Agent items + the "+ new agent" sentinel. nil (with a warning) when there
--- are no Agents yet.
---@return { kind: "agent"|"new", agent?: vantage.Agent, text: string }[]?
function M.agent_items()
  local agents = Backend.get().list()
  if #agents == 0 then
    Util.warn("no agents yet — use :Vantage toggle to create")
    return nil
  end
  local items = {}
  for _, agent in ipairs(agents) do
    items[#items + 1] = { kind = "agent", agent = agent, text = M.format_agent(agent) }
  end
  items[#items + 1] = { kind = "new", text = "+ new agent" }
  return items
end

--- The absolute file path of a buffer, or nil when it has no readable real
--- file (unnamed, non-"file" buftype, or the file is not on disk). Shared by
--- the fzf-lua and snacks buffer pickers to filter selections down to paths an
--- Agent can read.
---@param buf integer
---@return string?
function M.buffer_file_path(buf)
  if not vim.api.nvim_buf_is_valid(buf) then
    return nil
  end
  if vim.bo[buf].buftype ~= "" then
    return nil
  end
  local name = vim.api.nvim_buf_get_name(buf)
  if name == nil or name == "" then
    return nil
  end
  if vim.fn.filereadable(name) ~= 1 then
    return nil
  end
  return vim.fs.normalize(vim.fn.fnamemodify(name, ":p"))
end

--- Agents (as { target, agent }) + Groups (as { target }) to kill.
--- nil (with a warning) when there is nothing to kill.
---@return { target: string, agent?: vantage.Agent, text: string }[]?
function M.kill_items()
  local items = {}
  for _, agent in ipairs(Backend.get().list()) do
    items[#items + 1] = { target = agent.target, agent = agent, text = M.format_agent(agent) }
  end
  for _, group in ipairs(Backend.get().groups()) do
    items[#items + 1] = { target = group, text = ("group %s"):format(group) }
  end
  if #items == 0 then
    Util.warn("nothing to kill")
    return nil
  end
  return items
end

--- The cwd to relativize annotation previews against: the focused Agent's cwd,
--- else the current window's local cwd.
---@return string
function M.annotation_cwd()
  local agent = require("vantage.client").last_agent_alive()
  return agent and agent.cwd or Util.cwd()
end

--- Annotations (as { annotation, text }) for the picker, or nil when there are
--- none (warned unless `silent`).
---@param silent? boolean
---@return { annotation: vantage.Annotation, text: string }[]?
function M.annotation_items(silent)
  local Annotation = require("vantage.annotation")
  local annotations = Annotation.collect()
  if #annotations == 0 then
    if not silent then
      Util.warn("no annotations — add one with :Vantage annotate")
    end
    return nil
  end
  local items = {}
  for _, annotation in ipairs(annotations) do
    local path = Util.tilde(vim.api.nvim_buf_get_name(annotation.buf) or "")
    local first = (vim.split(annotation.note, "\n", { plain = true })[1] or ""):gsub("%s+", " ")
    items[#items + 1] = {
      annotation = annotation,
      text = ("%s:L%d-%d  %s"):format(path, annotation.start_row, annotation.end_row, first),
    }
  end
  return items
end

return M
