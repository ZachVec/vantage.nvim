--- Configuration and shared types for Vantage.

---@alias vantage.ReferenceFormat fun(file: string, loc: string?): string? renders a path plus its optional `:L`/`:C` suffix in a Tool's dialect

---@class vantage.Tool A launch command (name -> cmd array).
---@field cmd string[]
---@field format? vantage.ReferenceFormat per-Agent reference dialect; without it a reference is `file` plus a space-separated `loc`

---@class vantage.Agent A running coding-agent process.
---@field id string opaque Driver identity
---@field seq integer driver-neutral creation order
---@field group string
---@field cmd string
---@field cwd string
---@field tool string the cli.tools key that created it (for the format hook)
---@field state? string

---@class vantage.Attachment A Terminal's transient View and attach command.
---@field view string
---@field argv string[]

---@class vantage.Driver The multiplexer contract behind the Bridge.
---@field create fun(opts: { group: string, cmd: string, cwd: string, tool: string }): vantage.Agent?, string?
---@field snapshot fun(pid?: integer): { agents: vantage.Agent[], groups: string[], focused?: vantage.Agent }?, string?
---@field retarget fun(pid: integer, agent: vantage.Agent): boolean, string?
---@field attach fun(agent: vantage.Agent): vantage.Attachment?, string?
---@field kill_view fun(view: string): boolean, string?
---@field kill_agent fun(agent: vantage.Agent): boolean, string?
---@field kill_group fun(group: string): boolean, string?
---@field send_keys fun(agent: vantage.Agent, text: string): boolean, string?
---@field capture_pane fun(agent: vantage.Agent, max_lines?: integer): string[]?, string?
---@field status fun(): { clients: string[], sessions: string[] }?, string?
---@field health fun(): { status: "ok"|"warn"|"err", message: string, fatal?: boolean }[]

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

---@class vantage.GatherConfig
---@field join string separator between gathered references ("\n" = one per line, " " = one line)

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
---@field gather vantage.GatherConfig
---@field cli { tools: table<string, vantage.Tool>, win: vantage.Win }

---@class vantage.PickSpec The selection contract passed to a picker
--- implementation. Each field is an input to the picker: the items to render
--- (`items_provider`) and the prompt glyph (`prompt`). Rows expose
--- `format()` / `preview()`; commands are supplied through `PickOpts`.
---@field prompt string
---@field items_provider fun(): table[]

---@class vantage.PickerCommandCtx
---@field item any
---@field items any[]

---@class vantage.PickerCommand A keymap-shaped picker command:
--- `{ lhs, rhs, desc? }`. `rhs` receives the neutral context and returns true
--- when the item list may have changed.
---@field [1] string lhs
---@field [2] fun(ctx: vantage.PickerCommandCtx): boolean
---@field desc? string

---@class vantage.PickOpts
---@field on_choice fun(item: any)
---@field on_close? fun() run when the picker closes, whether chosen or cancelled
---@field commands? vantage.PickerCommand[]

---@class vantage.PickMultiOpts Options for a multi-selection pick. A picker
--- without the `multi` capability degrades to one choice, so `on_choices`
--- always receives a list of at least one item.
---@field on_choices fun(items: any[])
---@field on_close? fun() run when the picker closes, whether chosen or cancelled

---@class vantage.PlainSelectOpts Options for the plain-list select form
--- (`pick_plain`), mirroring `vim.ui.select`'s opts.
---@field prompt? string
---@field format_item? fun(item: any): string

---@class vantage.PickerCapabilities
---@field preview boolean
---@field command boolean
---@field multi boolean

---@class vantage.PickerImpl A selection-UI implementation (native | fzf-lua |
--- snacks) rendering every Vantage selection on its own engine. The command
--- flows assemble a PickSpec per flow; the implementations stay
--- presentation-only and depend on nothing but their engine.
---@field requires? string optional runtime module dependency
---@field capabilities vantage.PickerCapabilities
---@field pick fun(spec: vantage.PickSpec, opts: vantage.PickOpts): boolean
---@field pick_multi? fun(spec: vantage.PickSpec, opts: vantage.PickMultiOpts): boolean
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
    --- Fields: {note} (the text), {lines} (`<relpath>:L<start>-<end>`,
    --- spelled through the Tool's `format` hook)
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
  --- The gather flow (`files`/`buffers`): every selected reference runs
  --- through the focused Tool's `format` hook, then the results are joined
  --- with `join` and typed into the Agent's input.
  gather = {
    --- Separator between references: "\n" puts one per line, " " keeps them
    --- on one line.
    join = "\n",
  },
  cli = {
    --- Launch commands offered when creating an Agent (name -> cmd array).
    --- Empty by default: provide your own; invalid entries are dropped at
    --- setup with a warning.
    --- A tool may also carry a `format(file, loc)` function: it renders every
    --- location reference a Prompt or the `files`/`buffers` terminal actions
    --- produce, deciding the dialect. `file` is a path relative to the Agent's
    --- cwd (absolute when it escapes) and `loc` the `:L`/`:C` suffix, nil for a
    --- whole-file reference.
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

--- Prompt placeholder vocabulary shared by the Prompt flow and health.
---@type table<string, boolean>
M.PROMPT_PLACEHOLDERS = {
  file = true,
  line = true,
  ["function"] = true,
  ["class"] = true,
  reviews = true,
}

--- Invalid cli.tools entries dropped by the last Config.apply() run (name -> reason),
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

---@param opts? vantage.Config
function M.apply(opts)
  M.options = vim.tbl_deep_extend("force", vim.deepcopy(defaults), opts or {})
  local dropped = {}
  M.sanitize_tools(M.options.cli.tools, dropped)
  M.dropped_tools = dropped
  for name, reason in pairs(dropped) do
    Util.warn(("dropping invalid cli.tools entry '%s' (%s)"):format(name, reason))
  end
end

return M
