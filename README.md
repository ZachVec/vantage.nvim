# vantage.nvim

A coding-agent manager for Neovim. It runs coding agents (Claude Code, Codex,
dsh, …) in a tmux server and shows them in a single persistent `:terminal`.
tmux is the state store, multiplexer, renderer, and input layer — there is no
custom TUI.

Vantage is a single Neovim plugin:

- **Backend** — the plugin's Lua domain layer, driving a private tmux socket
  directly. It is a pluggable interface (`tmux` today, room for `zellij` later)
  and holds all state and domain logic.
- **Frontend** — a pluggable picker (`native` / `fzf-lua` / `snacks`) plus the
  `:terminal` window that is the tmux client.

## Requirements

- Neovim ≥ 0.10
- tmux 3.0+ (developed against 3.6a)
- [nvim-treesitter-textobjects](https://github.com/nvim-treesitter/nvim-treesitter-textobjects) (optional; for the `{function}` / `{class}` prompt placeholders)

## Install

Install with your favorite package manager. With
[lazy.nvim](https://github.com/folke/lazy.nvim):

```lua
{
  "ZachVec/vantage.nvim",
  cmd  = "Vantage",
  opts = {},
}
```

The plugin loads lazily on the first `:Vantage`. See `:h vantage.nvim` for full
docs.

## Usage

```vim
:Vantage                                   " show help (no default action)
:Vantage switch                            " switch: focus an Agent, or create a new one
:Vantage switch @1                         " focus a specific Agent
:Vantage kill @1                           " kill an Agent (or a Group by name)
:Vantage toggle                            " hide/show the terminal (creates if empty)
:Vantage detach                            " detach the client (kills the View; Agents survive)
:Vantage prompt                            " pick a prompt and type it into the focused Agent
:Vantage annotate                          " open the annotation picker (read/edit a note)
:Vantage annotate add                      " annotate a range (visual selection, or current line)
:Vantage annotate clear                    " remove every annotation
:Vantage status                            " debug: clients + sessions
```

Creating an Agent happens through two channels: `:Vantage toggle` when there
are no Agents yet, or the `+ new agent` entry in the `:Vantage switch` picker.
The tool and Group choice use `vim.ui.select` (there is nothing to preview);
when no Group exists yet, you go straight to the Group-name prompt.

The first focus opens the `:terminal` and attaches it to the agent; later
focuses re-target that same terminal. Closing the terminal detaches the client
and destroys its View — Agents keep running headless until killed.

## Configuration

```lua
require("vantage").setup({
  backend = "tmux",          -- pluggable backend driver (only "tmux" today)
  socket  = "vantage",       -- private tmux socket name
  picker  = "native",        -- native | fzf-lua | snacks
  prompts = {               -- built-in {file}/{line}/{annotations}; add/override yours
    ["{file}"] = "{file}",
    ["{line}"] = "{line}",
    ["{annotations}"] = "{annotations}",
  },
  annotations = {           -- notes on line ranges, sent via {annotations}
    item = "{lines} {note}",  -- per-annotation template
    clear_on_send = true,     -- clear after a sent prompt uses {annotations}
    keys = {                  -- note-float keymaps (normal mode)
      exit = "<Esc>",         -- commit the note and close (empty = delete)
      -- delete = "<leader>d", -- optional: delete directly
    },
  },
  cli = {
    tools = {},              -- provide your own (name -> cmd array); nothing built in
    win = {                  -- the terminal window that is the tmux client
      layout = "float",      -- float | left | top | bottom | right
      float  = { width = 0.9, height = 0.9, border = "rounded" },  -- border = "none" to hide
      split  = { width = 80, height = 20 },
      keys = {},             -- no keymaps by default; add your own (see below)
    },
  },
})
```

`cli.tools` is empty by default — provide every tool yourself, e.g.:

```lua
tools = {
  claude = { cmd = { "claude" } },
  codex  = { cmd = { "codex" } },
}
```

`tools.<name>.cmd` is run verbatim when creating an Agent (it may include
arguments); nothing is built in or validated. An Agent's working directory is
the current window's local cwd (respects `:lcd`/`:tcd`), overridable with
`create --cwd <dir>`. A tool may also carry a `format` function
(`fun(text): string`), applied to a rendered prompt just before it is sent.

### Prompt templates

`prompts` maps names to text templates. Three are built in — `{file}`, `{line}`,
and `{annotations}`, as identity templates (`"{file}"` → `"{file}"`) — so the raw
location references and the accumulated Annotations are always available. The
`{annotations}` prompt is hidden while there are no Annotations. `:Vantage
prompt` picks one via `vim.ui.select` (not the pluggable picker — there is
nothing to preview) and pastes it into the focused Agent's input; it never
auto-submits. Your `prompts` merge additively: a name you set overrides the
built-in, and names you leave unset are kept. Templates may use five
placeholders, four of which are Claude-style location references relative to
the focused Agent's cwd:

| Placeholder | Expands to |
|-------------|------------|
| `{file}`     | `@path/to/file.lua` |
| `{line}`     | `@path/to/file.lua :L42` (cursor line) |
| `{function}` | `function foo @path/to/file.lua :L42:C3` |
| `{class}`    | `class Foo @path/to/file.lua :L42:C3` |
| `{annotations}` | every Annotation, rendered by `annotations.item` |

`{function}` / `{class}` need nvim-treesitter-textobjects; without it (or
outside a function/class) the prompt is skipped with a warning — that is why
they are not built in. An unknown placeholder is left literal at runtime and
reported by `:checkhealth vantage`.

```lua
prompts = {
  review   = "Review {file} for bugs and improvements.",
  fix_line = "Fix {line}.",
  document = "Add documentation to {function}.",
}
```

### Annotations

An Annotation is a note anchored to a line range in a normal file. Add one with
`:Vantage annotate add` (over the visual selection, or the current line when
there is none); `:Vantage annotate` opens a picker — selecting one jumps to its
range and opens an editable note float — and `:Vantage annotate clear` removes
them all. Annotations tint the range's line numbers only — no layout shift, no
code obscuring; when the number column is off they are not drawn. They live in
memory only: lost on buffer unload/reload or Neovim exit.

The note float is a normal scratch buffer (normal mode), so editing is ordinary
Vim — multi-line notes and undo included. The only added keymap is
`annotations.keys.exit` (default `<Esc>`): it commits the note and closes the
float; an empty note deletes the annotation after a confirmation. The picker is
pluggable: fzf-lua/snacks preview each note through `annotations.item` and offer
an in-place `<c-x>` delete; native is selection-only.

Send them to the focused Agent through a prompt that uses `{annotations}`:

```lua
require("vantage").setup({
  prompts = { notes = "My notes:\n{annotations}" },
})
```

`annotations.item` is the per-annotation template, with fields `{note}`,
`{lines}` (`@path/to/file.lua :L10-L20`), `{code}` (the selected lines),
`{file}`, `{start}`, `{end}`. Default is `"{lines} {note}"`; to include the
code use `item = "{lines} {note}\n{code}"`. With `clear_on_send = true`
(default), a successful send that used `{annotations}` clears the annotations.

### Pickers & prompts

The Agent list (`:Vantage switch`) and the kill list (`:Vantage kill`) go
through a pluggable picker, chosen by `picker`:

- `"native"` — built-in `vim.ui.select` (default). Respects any global
  `vim.ui.select` override (dressing.nvim, snacks' ui_select, …).
- `"fzf-lua"` — fzf-lua; requires the fzf-lua plugin.
- `"snacks"` — snacks.nvim picker; requires snacks.nvim.

`fzf-lua` and `snacks` preview the selected Agent's pane (its recent terminal
output). Selections with nothing to preview — the tool and Group choice when
creating an Agent, and `:Vantage prompt` — use `vim.ui.select` directly, not
the picker. Free-text prompts (e.g. the new-Group name) use `input()` and are
insert-mode by default.

### Terminal filetype & keymaps

**No keymaps are added by default.** The terminal buffer has filetype
`vantage_terminal`. Two ways to add keys:

**A. `cli.win.keys`** — a list of 4-tuples `{ lhs, rhs, mode = "n", desc }`,
applied buffer-locally when the terminal is created. `rhs` is passed verbatim to
`vim.keymap.set` — a key sequence / `<cmd>` RHS, or a Lua function. `mode` is
`"n"` / `"t"` / `"nt"`.

```lua
require("vantage").setup({
  cli = {
    win = {
      keys = {
        { "<c-q>", "<cmd>Vantage toggle<CR>", mode = "t", desc = "toggle the terminal" },
        { "q", "<cmd>Vantage toggle<CR>", mode = "n", desc = "toggle the terminal" },
        { "<c-s>", function() vim.cmd("stopinsert") end, mode = "t", desc = "enter normal mode" },
      },
    },
  },
})
```

**B. `FileType` autocmd on `vantage_terminal`** — full control with plain
`vim.keymap.set`:

```lua
vim.api.nvim_create_autocmd("FileType", {
  pattern = "vantage_terminal",
  callback = function(ev)
    vim.keymap.set("n", "q", ":Vantage toggle<CR>", { buffer = ev.buf })
    vim.keymap.set("t", "<c-q>", "<cmd>Vantage toggle<CR>", { buffer = ev.buf })
  end,
})
```

For a normal-mode keymap that opens/toggles from anywhere (not just inside the
terminal):

```lua
vim.keymap.set("n", "<leader>vt", "<cmd>Vantage toggle<CR>", { desc = "Toggle Vantage" })
```

