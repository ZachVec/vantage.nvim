# vantage.nvim

A coding-agent manager for Neovim. It runs coding agents (Claude Code, Codex,
dsh, …) in tmux and shows them in a single persistent `:terminal`.

## Requirements

- Neovim ≥ 0.10
- tmux 3.0+

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
:Vantage show            " show the terminal; picks an Agent if none is open
:Vantage hide            " hide the terminal window; the client stays attached
:Vantage detach          " close the terminal; Agents keep running
:Vantage review          " add a review over the current selection/line
:Vantage review list     " open reviews
:Vantage review clear    " remove all reviews
:Vantage kill            " kill an Agent or Group
:Vantage status          " show clients and sessions
```

Create an Agent from the Agent picker: use the `switch` terminal key, or run
`:Vantage show` when no terminal is open. Pick a Tool, then choose or create
a Group. Multiple Neovim instances can show different Agents in the same Group.

## Configuration

```lua
require("vantage").setup({
  backend = "tmux",          -- only "tmux" today
  backend_opts = {           -- options for the chosen backend
    tmux = { socket = "vantage" }, -- private tmux socket
  },
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

  gather = {
    join = "\n",             -- separator between gathered references
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

A tool may also define `format(file, loc)`, the reference formatter: `file` is
a path relative to the Agent's cwd (absolute when it escapes) and `loc` the
`:L` position suffix, or nil for a whole-file reference.

### Prompts

`prompts` maps names to templates. The built-in names are `{file}`, `{line}`,
and `{reviews}`; user entries merge with them. The `prompt` terminal key picks
a prompt and types it into the focused Agent without submitting.

| Placeholder | Expands to |
|-------------|------------|
| `{file}` | `path/to/file.lua` |
| `{line}` | `path/to/file.lua :L42` |
| `{reviews}` | all Reviews rendered with `reviews.item` |

Locations are spelled by the focused tool's `format` hook; without one the
path and its `:L` suffix are joined by a space.

The `{reviews}` prompt is hidden when there are no Reviews.

```lua
prompts = {
  review = "Review {file} for bugs.",
  fix_line = "Fix {line}.",
}
```

### Files and buffers

The `files` and `buffers` terminal keys pick several files or buffers and type
their references into the focused Agent without submitting:

```lua
cli = {
  win = {
    keys = {
      { "<c-f>", "files", mode = "t", desc = "send file references" },
      { "<c-b>", "buffers", mode = "t", desc = "send buffer references" },
    },
  },
}
```

`files` lists files under Neovim's global cwd (`:cd`; not `:lcd`/`:tcd`) — the
tree you are browsing, wherever the Agent was started: `fd` when available,
then `ripgrep`, then `find` — all three skip `.git`. With `fzf-lua` or `snacks`
the list appears as the lister prints it, so `Esc` stops a long listing;
`native` waits for the whole listing before it opens. `buffers` lists listed
buffers whose file exists on disk, most recently used first; a modified buffer
is marked `[+]` because the Agent reads the on-disk version. Each chosen entry
is typed as its path relative to the Agent's cwd (absolute when the file lies
outside it), spelled by the tool's `format` hook (a gathered entry has no
position, so `loc` is nil) — no `@` unless you add one — then `gather.join`
decides the separator (default one per line), and a trailing space follows the
last reference.

```lua
tools = {
  claude = {
    cmd = { "claude" },
    format = function(file, loc)
      return "@" .. file .. (loc and (" " .. loc) or "")
    end,
  },
  codex = { cmd = { "codex", "--full-auto" } },
}
```

`fzf-lua` and `snacks` select several entries at once (`<Tab>` marks, Enter
sends the marked set or the entry under the cursor when none is marked);
`native` sends one entry at a time.

### Reviews

```vim
:Vantage review          " add a review over the selection or current line
:Vantage review list     " jump to and edit reviews
:Vantage review clear    " remove all reviews
```

Reviews live only in memory and are lost when the buffer unloads or Neovim
exits.

In the note window, `<Esc>` saves. An empty note deletes the Review.

Send Reviews with a prompt containing `{reviews}`:

```lua
prompts = { notes = "My notes:\n{reviews}" }
```

`reviews.item` supports `{note}`, `{lines}`, `{code}`, `{file}`, `{start}`, and
`{end}`. The default is `"{lines} {note}"`; `{lines}` and `{file}` are spelled
through the tool's `format` hook.

### Pickers

`picker` selects the UI used for Agent, kill, Review, and gathered
file/buffer lists:

| Picker | Provided by | Previews |
|--------|-------------|----------|
| `"native"` | `vim.ui.select` | — |
| `"fzf-lua"` | fzf-lua | Agent output, Reviews, files/buffers |
| `"snacks"` | snacks.nvim | Agent output, Reviews, files/buffers |

`fzf-lua` and `snacks` also support these keys:

| Key | Agent list | Review list |
|-----|------------|-------------|
| `<c-g>` | toggle Group scope | — |
| `<c-x>` | kill the selected Agent | delete the selected Review |

With a focused Agent, the Agent list opens scoped to its Group; its `<c-x>`
ignores the pinned `(focused)` entry and Tool entries. `"native"` binds no keys.
Marking several entries (`<Tab>`) selects several: the kill list kills every
marked Agent or Group, the `files` and `buffers` keys gather every marked
reference, and the Agent and Review lists act on the entry under the cursor.
`native` acts on one entry at a time.

### Terminal keymaps

The terminal buffer has filetype `vantage_terminal`. No keymaps are added by
default.

Use `cli.win.keys` for Terminal actions or plain keymaps:

```lua
cli = {
  win = {
    keys = {
      { "<c-q>", "hide", mode = "t", desc = "hide terminal" },
      { "s", "switch", mode = "n", desc = "switch Agent" },
      { "p", "prompt", mode = "n", desc = "send prompt" },
      { "<c-f>", "files", mode = "t", desc = "send file references" },
      { "<c-b>", "buffers", mode = "t", desc = "send buffer references" },
    },
  },
}
```

`rhs` may be a Terminal action (`"hide"`, `"switch"`, `"prompt"`, `"files"`,
`"buffers"`) or any value accepted by `vim.keymap.set`. Those keys live on the
terminal buffer; showing the terminal again is `:Vantage show`, which you bind
in an ordinary window:

```lua
vim.keymap.set("n", "<c-q>", "<cmd>Vantage show<CR>", {
  desc = "show terminal",
})
```

You can also use a normal `FileType` autocmd on `vantage_terminal` for full
control with `vim.keymap.set`.
