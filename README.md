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
:Vantage status                            " debug: clients + sessions
```

Creating an Agent happens through two channels: `:Vantage toggle` when there
are no Agents yet, or the `+ new agent` entry in the `:Vantage switch` picker.
When no Group exists yet, you go straight to the Group-name prompt.

The first focus opens the `:terminal` and attaches it to the agent; later
focuses re-target that same terminal. Closing the terminal detaches the client
and destroys its View — Agents keep running headless until killed.

## Configuration

```lua
require("vantage").setup({
  backend = "tmux",          -- pluggable backend driver (only "tmux" today)
  socket  = "vantage",       -- private tmux socket name
  picker  = "native",        -- native | fzf-lua | snacks
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
`create --cwd <dir>`.

### Pickers & prompts

Selections go through a pluggable picker, chosen by `picker`:

- `"native"` — built-in `vim.ui.select` (default). Respects any global
  `vim.ui.select` override (dressing.nvim, snacks' ui_select, …).
- `"fzf-lua"` — fzf-lua; requires the fzf-lua plugin.
- `"snacks"` — snacks.nvim picker; requires snacks.nvim.

`fzf-lua` and `snacks` preview the selected Agent's pane (its recent terminal
output). Free-text prompts (e.g. the new-Group name) use `input()` and are
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

