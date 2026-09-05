--- The `:Vantage prompt` command: pick a Prompt and type it into the focused
--- Agent's input.
local Annotation = require("vantage.annotation")
local Backend = require("vantage.backend")
local Client = require("vantage.client")
local Config = require("vantage.config")
local Picker = require("vantage.picker")
local Prompt = require("vantage.prompt")
local Select = require("vantage.select")
local Util = require("vantage.util")

local M = {}

--- Render a prompt against the focused Agent's context and type it into the
--- Agent's input (no auto-submit).
---@param name string
local function send_prompt(name)
  local agent = Client.last_agent_alive()
  if not agent then
    Util.warn("no focused agent — use :Vantage toggle or :Vantage switch first")
    return
  end
  local template = Config.options.prompts[name]
  if template == nil then
    Util.warn(("no such prompt '%s'"):format(name))
    return
  end
  local text, failed = Prompt.render(template, Prompt.context(agent))
  if text == nil then
    Util.warn(("prompt '%s' skipped: {%s} resolved empty"):format(name, failed))
    return
  end
  local tool = agent.tool and Config.options.cli.tools[agent.tool]
  if tool and tool.format then
    text = tool.format(text)
    if text == nil or text == "" then
      Util.warn(("prompt '%s' dropped by its format hook"):format(name))
      return
    end
  end
  Backend.get().send_keys(agent.target, text)
  if template:find("{annotations}", 1, true) and Config.options.annotations.clear_on_send then
    Annotation.clear()
  end
end

--- Pick a prompt name through the Picker's plain-select method and send it to
--- the focused Agent. The current window is restored afterwards so the cursor
--- stays where it was (e.g. the terminal).
function M.run()
  local names = {}
  local has_annotations = #Annotation.collect() > 0
  for name in pairs(Config.options.prompts) do
    if name == "{annotations}" and not has_annotations then
      -- hide the built-in {annotations} prompt while there is nothing to send
    else
      names[#names + 1] = name
    end
  end
  table.sort(names)
  local win = vim.api.nvim_get_current_win()
  local function restore()
    if vim.api.nvim_win_is_valid(win) then
      vim.api.nvim_set_current_win(win)
    end
  end
  Picker.get()
    .pick_plain(names, { prompt = "Prompt: ", invoked_from_terminal = Select.invoked_from_terminal() }, function(name)
      if name then
        send_prompt(name)
      end
      restore()
      vim.schedule(restore)
    end)
end

return M
