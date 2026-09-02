# External-tool gotchas

Behaviors of external tools (tmux, claude/codex, fzf-lua, snacks, Neovim) that
surprised us during feature work and caused bugs. Read this before building
anything that interacts with these tools.

## Backend · tmux · agent CLI

### `tmux send-keys -l` collapses newlines in claude

`send-keys -l` sends raw LF; **claude** collapses those newlines onto one line
(codex preserves them). To send multi-line text to an agent, use **bracketed
paste** instead:

```
tmux set-buffer -b <name> -- <text>
tmux paste-buffer -p -t <pane> -b <name>
tmux delete-buffer -b <name>
```

Consequence: bracketed paste inserts the text verbatim, so a trailing `\n`
becomes a **visible empty line**. Do NOT append `\n` to the pasted text — the
old `send-keys -l` needed the LF to move the cursor to the next line; paste
does not.

## Picker · fzf-lua

### `fzf_exec` function contents writes one item per callback

A function contents is invoked as `contents(on_write_nl, on_write, ...)`. The
**first** callback (`on_write_nl`) writes ONE item (it appends the EOL); call it
once per item, then call it with `nil` to signal end-of-input. Passing a whole
table to the first callback renders `table: 0x…`.

### Native in-place refresh (reload)

To update the list without close/reopen — close/reopen flickers because fzf is
a full-screen terminal process — use an action `{ fn = <function>, reload = true }`
together with **function** contents. Static table contents cannot reload (the
items are baked into the command when the picker opens).

### fzf returns display strings, not objects

`fzf_exec` returns the display string, not the original item. Recover the item
with a numeric-prefix round-trip (`"1. text"` and parse the leading index), and
keep that items array in sync with the content across reloads (mutable state).

## Picker · snacks

### Finder signature is `fun(opts, ctx): result`

The finder is `fun(opts, ctx)` returning either an `Item[]` table or an async
`fun(cb)`; it is **not** `fun(cb)` directly. The simplest form just returns the
items table.

### Native in-place refresh

`picker:refresh()` re-runs the finder. Use it (with a finder that re-reads the
items) instead of close/reopen.

### Keymaps field is `win.<pane>.keys`, not `keymaps`

Custom keys live in `win.input.keys` / `win.list.keys` / `win.preview.keys`;
values are action names (a string) or `{ "name", mode = { … } }`. `actions` is
`{ name = fun(picker, item) }`, and the keymaps bind a key to an action name.
`win.*.keys` **merges** with the defaults (it does not replace them).

### Schedule picker callbacks that change the UI

A `confirm`/action callback that jumps, opens a float, or otherwise changes the
UI must be wrapped in `vim.schedule`, so it runs only after the picker window
has closed.

## Neovim

### `<cmd>` mappings keep Visual mode active

With a `<cmd>` (or Lua-fn) visual mapping, the `'<` / `'>` marks are not set yet
(they are written when Visual mode exits). To read the visual range, run
`normal! \27` first, then `line("'<")` / `line("'>")`.

### `CursorMoved` fires deferred

`nvim_win_set_cursor` triggers `CursorMoved` on the next main-loop tick, not
synchronously. A close-on-`CursorMoved` autocmd registered immediately after a
jump will catch that positioning move and close prematurely; guard against the
positioning position.

### `--headless` cannot test cursor/insert behavior

Under `--headless`, `CursorMoved` never fires and `nvim_get_mode()` stays `"n"`
(insert mode is not reflected). Verify cursor placement and insert/normal mode
interactively, not headlessly.

### `nvim_win_get_config` normalizes title/footer

A `title`/`footer` set as a string is returned by `nvim_win_get_config` as a
list `{ { text, hl } }`. Compare the inner text, not the string.
