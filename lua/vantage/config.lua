--- Configuration and shared types for Vantage.

---@class vantage.Tool A launch command (name -> cmd array).
---@field cmd string[]
---@field format? fun(text: string): string per-Agent text transform before sending a prompt

---@class vantage.Agent A running coding-agent process.
---@field group string
---@field target string tmux window id (@N)
---@field cmd string
---@field cwd string
---@field name string
---@field tool? string the cli.tools key that created it (for the format hook)
---@field state? string

---@class vantage.Win Terminal window options.
---@field layout string full | left | top | bottom | right
---@field split table
---@field keys table[]

---@class vantage.AnnotationKeys Note-float keymaps (normal mode, buffer-local).
---@field exit string commit the note and close the float
---@field delete? string delete the annotation directly (optional; unset by default)

---@class vantage.AnnotationFloatConfig Note-float window options.
---@field style string "inherit" (default) | "minimal"

---@class vantage.AnnotationConfig
---@field item string per-annotation send template ({note}/{lines}/{code}/{file}/{start}/{end})
---@field clear_on_send boolean clear after a sent prompt contains {annotations}
---@field keys vantage.AnnotationKeys
---@field float vantage.AnnotationFloatConfig

---@class vantage.Config
---@field backend string
---@field socket string
---@field picker string
---@field prompts table<string, string> named prompt templates (name -> template)
---@field annotations vantage.AnnotationConfig
---@field cli { tools: table<string, vantage.Tool>, win: vantage.Win }

---@class vantage.PickerImpl A selection-UI implementation (native | fzf-lua | snacks)
--- owning every Vantage selection: the preview-capable lists (the Agent list
--- and the kill list), the annotation picker, and plain list choices (the
--- Agent-creation Tool/Group steps and :Vantage prompt) through `pick_plain`.
--- Each implementation renders plain choices on its own engine — snacks'
--- compact select layout, fzf-lua's ui_select shim, or (native) the live
--- global `vim.ui.select` — so one flow never mixes renderer families.
---@field pick_agent fun(callback: fun(choice: { kind: "agent"|"tool", agent?: vantage.Agent, tool?: string, focused?: boolean }))
---@field pick_kill fun(callback: fun(target: string))
---@field pick_annotation fun(opts: { select: fun(annotation: vantage.Annotation), delete: fun(annotation: vantage.Annotation) })
---@field pick_plain fun(items: any[], opts: { prompt?: string, format_item?: fun(item: any): string }, on_choice: fun(item: any?, index?: integer))

local M = {}

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
    --- Note-float keymaps (normal mode, buffer-local). `exit` commits the note
    --- and closes the float; an empty note deletes the annotation (after a
    --- confirmation). `delete` optionally deletes the annotation directly.
    keys = {
      exit = "<Esc>",
      -- delete = "<leader>d",
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
      --- full | left | top | bottom | right
      --- `full` opens the terminal in a dedicated tab at the full editor size;
      --- the split layouts open it alongside the current window.
      layout = "full",
      split = { width = 80, height = 20 },
      --- Buffer-local keymaps for the terminal buffer (filetype
      --- `vantage_terminal`). Empty by default — add your own. Each entry is a
      --- 4-tuple { lhs, rhs, mode = "n", desc }; `rhs` is passed verbatim to
      --- vim.keymap.set (a key sequence / <cmd> RHS or a Lua function).
      ---
      --- Example:
      ---   keys = {
      ---     { "<c-q>", "<cmd>Vantage toggle<CR>", mode = "t", desc = "toggle the terminal" },
      ---     { "q", "<cmd>Vantage toggle<CR>", mode = "n", desc = "toggle the terminal" },
      ---     { "<c-s>", function() vim.cmd("stopinsert") end, mode = "t", desc = "enter normal mode" },
      ---   },
      keys = {},
    },
  },
}

---@type vantage.Config
M.options = vim.deepcopy(defaults)

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
