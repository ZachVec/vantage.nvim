--- Configuration and shared types for Vantage.

---@class vantage.Tool A launch command (name -> cmd array).
---@field cmd string[]
---@field format? fun(text: string): string per-Agent text transform before sending a prompt

---@class vantage.Agent A running coding-agent process.
---@field group string
---@field target string multiplexer window id (@N for tmux)
---@field cmd string
---@field cwd string
---@field tool string the cli.tools key that created it (for the format hook)
---@field state? string

---@class vantage.Win Terminal window options.
---@field layout string full | left | top | bottom | right | float
---@field float table relative-to-editor float window options (width/height/border)
---@field split table
---@field keys table[]

---@class vantage.ReviewFloatConfig Note-float window options.
---@field style string "inherit" (default) | "minimal"

---@class vantage.ReviewConfig
---@field item string per-review send template ({note}/{lines}/{code}/{file}/{start}/{end})
---@field clear_on_send boolean clear after a sent prompt contains {reviews}
---@field float vantage.ReviewFloatConfig

---@class vantage.NoteOpts Options for the editable-note UI (vantage.frontend.note).
---@field text string
---@field title? string
---@field footer? string
---@field on_commit fun(note: string) commit the text (Esc); every policy is the caller's
---@field on_close? fun() run when the note window is wiped
---@field style? string raw `nvim_open_win` style ("minimal"); nil inherits the source window
---@field insert? boolean start in insert mode

---@class vantage.Config
---@field backend string
---@field socket string
---@field picker string
---@field prompts table<string, string> named prompt templates (name -> template)
---@field reviews vantage.ReviewConfig
---@field cli { tools: table<string, vantage.Tool>, win: vantage.Win }

---@class vantage.PickSpec The selection contract passed to a picker
--- implementation. Each field is an input to the picker: the items to render
--- (`items_provider`), the prompt glyph (`prompt`), and an optional live group
--- filter (`group`, the picker's `<c-g>` toggle). Rows expose `format()` /
--- `preview()`, and a flow-enabled in-place `<c-x>` calls `delete()`; the
--- chosen row is delivered through the positional `on_choice`, and the picker
--- returns a boolean `empty`.
---@field prompt string
---@field items_provider fun(): table[]
---@field group? fun(items: table[]): table[] the flow's live group filter:
---   applied to freshly read items while the picker's group toggle is on (the
---   default when `group` exists), re-invoked after every re-read.

---@class vantage.PlainSelectOpts Options for the plain-list select form
--- (`pick_plain`), mirroring `vim.ui.select`'s opts.
---@field prompt? string
---@field format_item? fun(item: any): string

---@class vantage.PickerImpl A selection-UI implementation (native | fzf-lua |
--- snacks) rendering every Vantage selection on its own engine. The command
--- flows assemble a PickSpec per flow; the implementations stay
--- presentation-only and depend on nothing but their engine.
---@field pick_agent fun(spec: vantage.PickSpec, on_choice: fun(item: any)): boolean
---@field pick_kill fun(spec: vantage.PickSpec, on_choice: fun(item: any)): boolean
---@field pick_review fun(spec: vantage.PickSpec, on_choice: fun(item: any)): boolean
---@field pick_plain fun(items: any[], opts: vantage.PlainSelectOpts, on_choice: fun(item: any?, index?: integer))

local M = {}

local Util = require("vantage.util")

---@type vantage.Config
local defaults = {
  --- Pluggable backend driver name (currently only "tmux").
  backend = "tmux",
  --- Private tmux socket name, isolating Vantage from the daily tmux server.
  socket = "vantage",
  --- Pluggable picker (frontend) implementation: "native" | "fzf-lua" | "snacks".
  picker = "native",
  --- Named prompt templates (name -> template string) offered by the `prompt`
  --- terminal action. Three are built in — {file}, {line}, and {reviews}, as
  --- identity templates ("{file}" -> "{file}") — so the raw location
  --- references and the accumulated Reviews are always available. The
  --- {reviews} prompt is hidden when there are no Reviews. User prompts merge
  --- additively: a name you set overrides the built-in, and names you leave
  --- unset are kept. Templates may use the placeholders {file}, {line},
  --- {function}, {class}, and {reviews}, rendered relative to the focused
  --- Agent's cwd.
  prompts = {
    ["{file}"] = "{file}",
    ["{line}"] = "{line}",
    ["{reviews}"] = "{reviews}",
  },
  --- Reviews: notes anchored to line ranges in normal files, batched into
  --- the focused Agent through the {reviews} prompt placeholder.
  reviews = {
    --- Per-review template rendered for each review inside {reviews}.
    --- Fields: {note} (the text), {lines} (`@<relpath> :L<start>-<end>`),
    --- {code} (the selected lines), and {file}/{start}/{end} as building blocks.
    item = "{lines} {note}",
    --- Clear every review after a prompt containing {reviews} is typed into
    --- the Agent. Set false to keep them for re-sending.
    clear_on_send = true,
    --- Note-float window options. `float.style = "inherit"` (default) passes
    --- no float style, so the window takes the options of the window it opens
    --- from and reads as an editable buffer; `"minimal"` forces Neovim's
    --- minimal float style, a clean dialog look with those options off.
    float = {
      style = "inherit",
    },
  },
  cli = {
    --- Launch commands offered when creating an Agent (name -> cmd array).
    --- Empty by default: provide your own; invalid entries are dropped at
    --- setup with a warning.
    --- A tool may also carry a `format` function, applied to a rendered prompt
    --- just before it is sent to the Agent.
    tools = {},
    --- The persistent :terminal window that is the tmux client.
    win = {
      --- full | left | top | bottom | right | float
      --- `float` opens a centered floating window at the full editor size —
      --- floats render no statusline or winbar, so the view is a pure terminal.
      layout = "float",
      float = { width = 1.0, height = 1.0, border = "none" },
      split = { width = 80, height = 20 },
      --- Buffer-local keymaps for the terminal buffer (filetype
      --- `vantage_terminal`). Empty by default — add your own. Each entry is a
      --- 4-tuple { lhs, rhs, mode = "n", desc }; `rhs` is passed verbatim to
      --- vim.keymap.set, except a string naming a built-in terminal action —
      --- "switch", "prompt", or "toggle" — which resolves to that action.
      keys = {},
    },
  },
}

---@type vantage.Config
M.options = vim.deepcopy(defaults)

--- Invalid cli.tools entries dropped by the last setup() run (name -> reason),
--- surfaced by :checkhealth.
---@type table<string, string>
M.dropped_tools = {}

--- Validate a cli.tools table in place: drop invalid entries, recording each
--- in `dropped`. An entry is valid when its name is non-empty and its value
--- is a table with a non-empty `cmd` array whose first element is executable
--- on PATH.
---@param tools table<string, vantage.Tool>
---@param dropped? table<string, string> records name -> reason for each dropped entry
---@return table<string, vantage.Tool> the same table, invalid entries removed
function M.sanitize_tools(tools, dropped)
  for name, tool in pairs(tools) do
    local reason
    if name == "" then
      reason = "empty name"
    elseif type(tool) ~= "table" then
      reason = "value is not a table"
    elseif type(tool.cmd) ~= "table" or #tool.cmd == 0 then
      reason = "cmd is missing or empty"
    elseif vim.fn.executable(tool.cmd[1]) ~= 1 then
      reason = ("command '%s' not found"):format(tool.cmd[1])
    end
    if reason then
      if dropped then
        dropped[name] = reason
      end
      tools[name] = nil
    end
  end
  return tools
end

--- Monotonic stamp for the most-recently-visited window, read by the prompt
--- flow's context resolution.
local visit_counter = 0

--- (Re)register the WinEnter autocmd that stamps each window with the visit
--- counter, so Prompt context resolves against the last non-terminal window.
function M.track_window_visits()
  vim.api.nvim_create_augroup("VantageWinVisit", { clear = true })
  vim.api.nvim_create_autocmd("WinEnter", {
    group = "VantageWinVisit",
    callback = function()
      visit_counter = visit_counter + 1
      vim.w[vim.api.nvim_get_current_win()].vantage_visit = visit_counter
    end,
  })
end

---@param opts? vantage.Config
function M.setup(opts)
  M.options = vim.tbl_deep_extend("force", vim.deepcopy(defaults), opts or {})
  local dropped = {}
  M.sanitize_tools(M.options.cli.tools, dropped)
  M.dropped_tools = dropped
  for name, reason in pairs(dropped) do
    Util.warn(("dropping invalid cli.tools entry '%s' (%s)"):format(name, reason))
  end
  M.track_window_visits()
  require("vantage.frontend.review").setup()

  pcall(vim.api.nvim_create_user_command, "Vantage", function(args)
    require("vantage.commands").run(args)
  end, {
    nargs = "*",
    range = true, -- `:Vantage review` uses the range as the review span
    complete = function(arglead, cmdline)
      return require("vantage.commands").complete(arglead, cmdline)
    end,
    desc = "Vantage coding-agent manager",
  })
end

return M
