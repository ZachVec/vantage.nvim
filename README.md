# vantage.nvim

A coding-agent manager for Neovim. It runs coding agents (Claude Code, Codex,
dsh, …) in tmux and shows them in a single persistent `:terminal`.

## Requirements

- Neovim ≥ 0.10
- tmux 3.0+
- [nvim-treesitter-textobjects](https://github.com/nvim-treesitter/nvim-treesitter-textobjects) (optional; for `{function}` / `{class}` prompts)

## Install

With [lazy.nvim](https://github.com/folke/lazy.nvim):

```lua
{
  "ZachVec/vantage.nvim",
  cmd = "Vantage",
  opts = {},
}
```

The plugin loads on the first `:Vantage`. See `:h vantage.nvim` for the full
reference.

## Usage

```vim
:Vantage toggle          " hide/show the terminal; picks an Agent if none is open
:Vantage detach          " close the terminal; Agents keep running
:Vantage review          " add a review over the current selection/line
:Vantage review list     " open reviews
:Vantage review clear    " remove all reviews
:Vantage kill            " kill an Agent or Group
:Vantage status          " show clients and sessions
```

Create an Agent from the Agent picker: use the `switch` terminal key, or run
`:Vantage toggle` when no terminal is open. Pick a Tool, then choose or create
a Group. Multiple Neovim instances can show different Agents in the same Group.

## Configuration

```lua
require("vantage").setup({
  backend = "tmux",          -- only "tmux" today
  socket = "vantage",        -- private tmux socket
  picker = "native",         -- native | fzf-lua | snacks

  prompts = {                -- add or override prompt templates
    ["{file}"] = "{file}",
    ["{line}"] = "{line}",
    ["{reviews}"] = "{reviews}",
  },

  reviews = {
    item = "{lines} {note}", -- per-review template
    clear_on_send = true,    -- clear reviews after sending {reviews}
    float = { style = "inherit" }, -- "inherit" | "minimal"
  },

  cli = {
    tools = {},              -- name -> { cmd = { ... } }
    win = {
      layout = "float",      -- float | full | left | top | bottom | right
      float = { width = 1.0, height = 1.0, border = "none" },
      split = { width = 80, height = 20 },
      keys = {},             -- no default keymaps
    },
  },
})
```

An unknown or unavailable `backend`/`picker` is an error at setup.

### Tools

`cli.tools` is empty by default. Each entry is a command argv array:

```lua
tools = {
  claude = { cmd = { "claude" } },
  codex = { cmd = { "codex", "--full-auto" } },
}
```

A tool entry needs a non-empty name, a non-empty `cmd`, and an executable first
element. Invalid entries are dropped and reported by `:checkhealth vantage`.
The Agent working directory is Neovim's global cwd (`:cd`; not `:lcd`/`:tcd`).

A tool may also define `format(text)` to transform a prompt before it is sent.

### Prompts

`prompts` maps names to templates. The built-in names are `{file}`, `{line}`,
and `{reviews}`; user entries merge with them. The `prompt` terminal key picks
a prompt and types it into the focused Agent without submitting.

| Placeholder | Expands to |
|-------------|------------|
| `{file}` | `@path/to/file.lua` |
| `{line}` | `@path/to/file.lua :L42` |
| `{function}` | `function foo @path/to/file.lua :L42:C3` |
| `{class}` | `class Foo @path/to/file.lua :L42:C3` |
| `{reviews}` | all Reviews rendered with `reviews.item` |

`{function}` and `{class}` require nvim-treesitter-textobjects. The
`{reviews}` prompt is hidden when there are no Reviews.

```lua
prompts = {
  review = "Review {file} for bugs.",
  fix_line = "Fix {line}.",
}
```

### Reviews

`:Vantage review` adds a Review over the selection or current line.
`:Vantage review list` jumps to and edits Reviews; `:Vantage review clear`
removes them. Reviews live only in memory and are lost when the buffer unloads
or Neovim exits.

In the note window, `<Esc>` saves. An empty note deletes the Review.

Send Reviews with a prompt containing `{reviews}`:

```lua
prompts = { notes = "My notes:\n{reviews}" }
```

`reviews.item` supports `{note}`, `{lines}`, `{code}`, `{file}`, `{start}`, and
`{end}`. The default is `"{lines} {note}"`.

### Pickers

`picker` selects the UI used for Agent, kill, and Review lists:

- `"native"` — `vim.ui.select`
- `"fzf-lua"` — requires fzf-lua
- `"snacks"` — requires snacks.nvim

`fzf-lua` and `snacks` preview Agent output and Reviews. With a focused Agent,
the Agent list starts scoped to its Group; `<c-g>` toggles the scope. The
Review list supports `<c-x>` deletion when the picker supports commands.

### Terminal keymaps

The terminal buffer has filetype `vantage_terminal`. No keymaps are added by
default.

Use `cli.win.keys` for built-in actions or plain keymaps:

```lua
cli = {
  win = {
    keys = {
      { "<c-q>", "toggle", mode = "t", desc = "hide/show terminal" },
      { "q", "toggle", mode = "n", desc = "hide/show terminal" },
      { "s", "switch", mode = "n", desc = "switch Agent" },
      { "p", "prompt", mode = "n", desc = "send prompt" },
    },
  },
}
```

`rhs` may be a built-in action (`"switch"`, `"prompt"`, `"toggle"`) or any
value accepted by `vim.keymap.set`.

You can also use a normal `FileType` autocmd on `vantage_terminal` for full
control with `vim.keymap.set`.
