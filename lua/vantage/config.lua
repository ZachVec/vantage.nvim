--- Configuration and shared types for Vantage.

---@class vantage.Tool A launch command (name -> cmd array).
---@field cmd string[]
---@field format? fun(text: string): string per-Agent text transform before sending a prompt

---@class vantage.Agent A running coding-agent process.
---@field group string
---@field target string tmux window id (@N)
---@field cmd string
---@field cwd string
---@field tool string the cli.tools key that created it (for the format hook)
---@field state? string

---@class vantage.Win Terminal window options.
---@field layout string full | left | top | bottom | right | float
---@field float table relative-to-editor float window options (width/height/border)
---@field split table
---@field keys table[]

---@class vantage.AnnotationFloatConfig Note-float window options.
---@field style string "inherit" (default) | "minimal"

---@class vantage.AnnotationConfig
---@field item string per-annotation send template ({note}/{lines}/{code}/{file}/{start}/{end})
---@field clear_on_send boolean clear after a sent prompt contains {annotations}
---@field float vantage.AnnotationFloatConfig

---@class vantage.NoteOpts Options for the editable-note UI (vantage.ui.note).
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
---@field annotations vantage.AnnotationConfig
---@field cli { tools: table<string, vantage.Tool>, win: vantage.Win }

---@class vantage.PickSpec The selection contract passed to a picker
--- implementation. Each field is an input to the picker — the items to render
--- (`items_provider`), the prompt glyph (`prompt`), a caller-declared fact
--- (`from_terminal`), and an optional live group filter (`group`, the
--- picker's `<c-g>` toggle). Preview content and the `<c-x>` in-place removal
--- are read directly off the chosen item through its `preview()` and
--- `delete()` methods, so the spec carries no per-item behavior. The chosen
--- item is delivered through the positional `on_choice`; the picker returns a
--- boolean `empty`.
---@field prompt string
---@field items_provider fun(): table[]
---@field from_terminal? boolean
---@field group? fun(items: table[]): table[] the flow's live group filter:
---   applied to freshly read items while the picker's group toggle is on (the
---   default when `group` exists), re-invoked after every re-read (an
---   in-place delete or the toggle itself). Absent → no toggle key and no
---   filtering.

---@class vantage.PlainSelectOpts Options for the plain-list select form
--- (`pick_plain`), mirroring `vim.ui.select`'s opts plus the caller-declared
--- `from_terminal` fact the snacks implementation uses to restore terminal mode.
---@field prompt? string
---@field format_item? fun(item: any): string
---@field from_terminal? boolean

---@class vantage.PickerImpl A selection-UI implementation (native | fzf-lua |
--- snacks) rendering every Vantage selection on its own engine. The frontend
--- orchestrator (vantage.select) assembles a PickSpec per flow; the
--- implementations stay presentation-only and depend on nothing but their
--- engine. `on_choice` receives the chosen item itself — an Agent, Tool,
--- Group, or Annotation domain object carrying its own `format`, `preview`,
--- `delete`, `activate`, and `group` methods.
---@field pick_agent fun(spec: vantage.PickSpec, on_choice: fun(item: any)): boolean
---@field pick_kill fun(spec: vantage.PickSpec, on_choice: fun(item: any)): boolean
---@field pick_annotation fun(spec: vantage.PickSpec, on_choice: fun(item: any)): boolean
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
  --- Named prompt templates (name -> template string) offered by
  --- `:Vantage prompt`. Three are built in — {file}, {line}, and {annotations},
  --- as identity templates ("{file}" -> "{file}") — so the raw location
  --- references and the accumulated Annotations are always available. The
  --- {annotations} prompt is hidden when there are no Annotations. User prompts
  --- merge additively: a name you set overrides the built-in, and names you
  --- leave unset are kept. Templates may use the placeholders {file}, {line},
  --- {function}, {class}, and {annotations}, rendered relative to the focused
  --- Agent's cwd.
  prompts = {
    ["{file}"] = "{file}",
    ["{line}"] = "{line}",
    ["{annotations}"] = "{annotations}",
  },
  --- Annotations: notes anchored to line ranges in normal files, batched into
  --- the focused Agent through the {annotations} prompt placeholder.
  annotations = {
    --- Per-annotation template rendered for each annotation inside {annotations}.
    --- Fields: {note} (the text), {lines} (`@<relpath> :L<start>-<end>`),
    --- {code} (the selected lines), and {file}/{start}/{end} as building blocks.
    item = "{lines} {note}",
    --- Clear every annotation after a prompt containing {annotations} is typed
    --- into the Agent. Set false to keep them for re-sending.
    clear_on_send = true,
    --- Note-float window options. `float.style = "inherit"` (default) passes
    --- no float style, so the window takes the options of the window it opens
    --- from (line numbers, cursorline, … follow the user's config) and reads
    --- as an editable buffer; `"minimal"` forces Neovim's minimal float style,
    --- a clean dialog look with those options off.
    float = {
      style = "inherit",
    },
  },
  cli = {
    --- Launch commands offered when creating an Agent (name -> cmd array).
    --- Empty by default: provide your own; nothing is built in or validated.
    --- A tool may also carry a `format` function, applied to a rendered prompt
    --- just before it is sent to the Agent.
    --- Example:
    ---   tools = {
    ---     claude = { cmd = { "claude" } },
    ---     codex  = { cmd = { "codex" }, format = function(text) return text end },
    ---   },
    tools = {},
    --- The persistent :terminal window that is the tmux client.
    win = {
      --- full | left | top | bottom | right | float
      --- `float` opens a centered floating window at the full editor size —
      --- floats render no statusline or winbar, so the view is a pure terminal
      --- (a normal window's statusline row cannot be removed per window while
      --- 'laststatus' >= 2). The per-frame terminal-cursor redraw inside
      --- floats can flicker on some Agent-TUI repaints; `full` (a dedicated
      --- tab) is the alternative for users who see it, and the split layouts
      --- open the terminal alongside the current window.
      layout = "float",
      --- `float` layout window options. width/height are fractions of the
      --- editor area (0 < v <= 1); border is a `nvim_open_win` border value
      --- ("none" | "single" | "double" | "rounded" | "solid"), or false for
      --- no border.
      float = { width = 1.0, height = 1.0, border = "none" },
      split = { width = 80, height = 20 },
      --- Buffer-local keymaps for the terminal buffer (filetype
      --- `vantage_terminal`). Empty by default — add your own. Each entry is a
      --- 4-tuple { lhs, rhs, mode = "n", desc }; `rhs` is passed verbatim to
      --- vim.keymap.set (a key sequence / <cmd> RHS or a Lua function), except
      --- a string naming a built-in terminal action — "switch", "kill",
      --- "prompt", or "toggle" — which resolves to that action.
      ---
      --- Example:
      ---   keys = {
      ---     { "<c-q>", "toggle", mode = "t", desc = "hide/show the terminal" },
      ---     { "<c-s>", function() vim.cmd("stopinsert") end, mode = "t", desc = "enter normal mode" },
      ---     { "s", "switch", mode = "n", desc = "switch Agent" },
      ---     { "k", "kill", mode = "n", desc = "kill Agent/Group" },
      ---     { "p", "prompt", mode = "n", desc = "send a prompt" },
      ---   },
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
--- is a table with a non-empty `cmd` array. This is what keeps create()'s
--- Tool-required contract (and the pane border's unconditional @agent-tool)
--- honest.
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

--- Monotonic stamp for the most-recently-visited window, read by prompt.lua.
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
  require("vantage.annotation").setup()

  pcall(vim.api.nvim_create_user_command, "Vantage", function(args)
    require("vantage.commands").run(args)
  end, {
    nargs = "*",
    range = true, -- `:Vantage annotate` uses the range as the annotation span
    complete = function(arglead, cmdline)
      return require("vantage.commands").complete(arglead, cmdline)
    end,
    desc = "Vantage coding-agent manager",
  })
end

return M
