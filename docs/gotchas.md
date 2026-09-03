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

### Consecutive pickers over a terminal race during teardown

fzf-lua floats — `vim.ui.select` via `register_ui_select`, and `fzf_exec`
pickers — run fzf in a **terminal window** that is in terminal mode. When such
a float is opened over *another* terminal window (e.g. the Vantage client) and
then closes, Neovim's term-to-term mode transfer (see the Neovim section
below) leaves the underlying terminal in terminal mode for the rest of the
renderer's teardown (~40–80 ms headless). Any terminal UI opened inside that
window — another float, or `startinsert` on a terminal — fails to enter
terminal mode: the picker shows frozen in normal mode with a roaming cursor
and typing does nothing until you press `i`.

The race only fires when the closing float was opened from a terminal in
**normal** mode. Floats opened from genuine terminal mode are closed by
fzf-lua's dedicated mode cleanup (its terminal-context branch) and leave a
consistent state — consecutive opens over the terminal are safe in that lane.
Opening floats from a plain (non-terminal) window never races.

Do not try to repair the mode inside the window (`stopinsert` is ineffective
while the transfer is unsettled); the transient clears by itself once the
teardown finishes. Vantage avoids the pattern structurally: every selection it
makes — the Agent-creation wizard included — renders through the configured
Picker's own engine (`pick_plain`), so a flow is homogeneous by construction
and no wizard step ever opens a second window inside another renderer's
teardown. The residual boundary is a terminal-family renderer (the `fzf-lua`
Picker, or `native` with a terminal-style `vim.ui.select` override) plus a
trigger from a terminal in Normal mode: the first closing float leaves the
transient and the next step can land frozen — press `i`, or invoke from
terminal input state or a plain window.

## Picker · snacks

### Closing returns to Normal mode — not your previous terminal mode

The snacks picker input is a **prompt buffer, not a terminal window**, and on
close it deliberately leaves insert mode (`stopinsert`), returning you to
Normal. If the picker was opened over a terminal window that was in terminal
mode, that terminal does *not* get terminal mode back: it ends in Normal.
(fzf-lua floats do the opposite — the underlying terminal is left in terminal
mode via the term-to-term transfer.) Terminal mode is exclusive to the focused
window, so the terminal drops out of it for the whole time the picker is open.

Consequence: a chain that mixes snacks then fzf-lua feeds the fzf float a
terminal-in-normal-mode context — exactly the context in which fzf-lua's close
leaves the racy transient described in the fzf-lua section. Homogeneous chains
(snacks-only, or fzf-lua floats opened from genuine terminal mode) never hit
it.

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

### Terminal mode transfers between terminal windows (sticky)

When focus moves from a terminal window in terminal mode to **another
terminal window**, Neovim preserves terminal mode on the target even if the
target was in Normal (tracked in fzf-lua issues #2054/#2419). If the target's
real mode was Normal, the forced terminal mode is *transient*: it clears by
itself when the source window's teardown completes (tens of ms) and the
target falls back to Normal. While it is unsettled, the state is neither fully
granted nor transferable — `stopinsert` is ineffective and a new terminal
window cannot acquire terminal mode (`startinsert` silently fails). If the
target's real mode was terminal mode (you were typing there), the transfer
matches reality and nothing is unsettled.

This is the same stickiness that makes a terminal window "remember" terminal
mode when you focus away and back. Leaving terminal mode programmatically
works only from a *settled* terminal state (`stopinsert`, or the explicit
`<C-\><C-N>` transition; terminal-normal mode is reported as `nt` by
`nvim_get_mode` and `n` by `vim.fn.mode()`).

### `--headless` reflects modes and fires `CursorMoved` (0.12+)

On current Neovim (verified 0.12.3) `--headless` does report insert and
terminal modes — `vim.fn.mode()` / `nvim_get_mode()` return `i`, `t`, `nt`,
etc. — and `CursorMoved` fires after `nvim_win_set_cursor`. The mode races in
this file were reproduced and verified headlessly. An earlier version of this
entry claimed the opposite; if that was ever true it predates 0.12 — re-verify
on older target versions.

### `nvim_win_get_config` normalizes title/footer

A `title`/`footer` set as a string is returned by `nvim_win_get_config` as a
list `{ { text, hl } }`. Compare the inner text, not the string.
