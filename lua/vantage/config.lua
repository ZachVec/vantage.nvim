--- Configuration and shared types for Vantage: the option table, its
--- validation, and the reference spelling (`Config.tool_reference`). A seam's
--- contract types live with their seam — `vantage.Driver` in backend/init.lua,
--- the picker contract in frontend/picker.

---@alias vantage.ReferenceFormat fun(file: string, loc: string?): string? renders a path plus its optional `:L` suffix in a Tool's dialect

---@class vantage.Tool A launch command (name -> cmd array).
---@field cmd string[]
---@field format? vantage.ReferenceFormat per-Agent reference dialect; optional in user config, always set by `Config.apply` (default: `file` plus a space-separated `loc`). Spelled through `Config.tool_reference`, never read directly.

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

---@class vantage.Config
---@field backend string
---@field backend_opts { tmux: { socket: string } } per-Driver options, keyed by Driver name
---@field picker string
---@field prompts table<string, string> named prompt templates (name -> template)
---@field reviews vantage.ReviewConfig
---@field gather vantage.GatherConfig
---@field cli { tools: table<string, vantage.Tool>, win: vantage.Win }

local M = {}

local Util = require("vantage.util")

--- The default reference spelling: the path and, when there is a position, its
--- `:L` suffix, joined by a space (`src/a.lua :L42`). It is the `format` hook
--- every Tool without one gets in `apply`, so no caller carries that case.
---@param file string path relative to the Agent's cwd, or absolute
---@param loc? string `:L` position suffix; nil for a whole-file reference
---@return string
local function reference(file, loc)
  if loc then
    return file .. " " .. loc
  end
  return file
end

---@type vantage.Config
local defaults = {
  --- Pluggable backend driver name (currently only "tmux").
  backend = "tmux",
  --- Per-Driver options, keyed by the Driver name in `backend`. The shared
  --- option table names no multiplexer concept; each Driver owns and
  --- interprets its own entry.
  backend_opts = {
    --- Private tmux socket name, isolating Vantage from the daily tmux server.
    tmux = { socket = "vantage" },
  },
  --- Pluggable picker (frontend) implementation: "native" | "fzf-lua" | "snacks".
  picker = "native",
  --- Named prompt templates (name -> template string) offered by the `prompt`
  --- terminal action. Three are built in — {file}, {line}, and {reviews}, as
  --- identity templates ("{file}" -> "{file}") — so the raw location
  --- references and the accumulated Reviews are always available. The
  --- {reviews} prompt is hidden when there are no Reviews. User prompts merge
  --- additively: a name you set overrides the built-in, and names you leave
  --- unset are kept. Templates may use the placeholders {file}, {line}, and
  --- {reviews}, rendered relative to the focused Agent's cwd.
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
    --- cwd (absolute when it escapes) and `loc` the `:L` position suffix, nil for a
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

--- Why a Focus read came back empty, for the flows that warn about it. The
--- Driver answers it and callers only report it, so it is a message rather than
--- a cause vocabulary nobody branches on.
M.FOCUS_NO_FOCUS = "no focused agent"

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

--- The reference for one location, spelled by the Tool's `format` hook: the
--- path relativized against `cwd`, the `:L` suffix built from the position, and
--- the hook applied. `tool` is nil with no Focus, or names a Tool a later
--- setup dropped; both spell the default form (`apply` guarantees every
--- surviving Tool a hook). The reference does not exist — nil — when there is
--- no path, or when the hook declines it with nil or "": that interpretation
--- lives here, and the caller owns what to do about it.
---@param tool string? the Focus's Tool name; nil spells the default form
---@param cwd string relativization base (the focused Agent's cwd)
---@param path string absolute path, or one already relative to `cwd`
---@param start_row? integer 1-based first line; nil for a whole-file reference
---@param end_row? integer 1-based last line; only meaningful with `start_row`
---@return string?
function M.tool_reference(tool, cwd, path, start_row, end_row)
  if path == "" then
    return nil
  end
  local tool_cfg = tool and M.options.cli.tools[tool]
  local format = (tool_cfg and tool_cfg.format) or reference
  local loc
  if start_row ~= nil then
    if end_row ~= nil and end_row ~= start_row then
      loc = (":L%d-%d"):format(start_row, end_row)
    else
      loc = (":L%d"):format(start_row)
    end
  end
  local rendered = format(Util.relpath(cwd, path), loc)
  if rendered == nil or rendered == "" then
    return nil
  end
  return rendered
end

---@param opts? vantage.Config
function M.apply(opts)
  M.options = vim.tbl_deep_extend("force", vim.deepcopy(defaults), opts or {})
  local dropped = {}
  M.sanitize_tools(M.options.cli.tools, dropped)
  -- Every surviving Tool gets a reference spelling, so no caller has to carry
  -- the "user configured no hook" case.
  for _, tool in pairs(M.options.cli.tools) do
    if type(tool.format) ~= "function" then
      tool.format = reference
    end
  end
  M.dropped_tools = dropped
  for name, reason in pairs(dropped) do
    Util.warn(("dropping invalid cli.tools entry '%s' (%s)"):format(name, reason))
  end
end

return M
