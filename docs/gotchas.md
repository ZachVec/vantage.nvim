# External-tool gotchas

Behaviors of external tools (tmux, claude/codex, fzf-lua, snacks, Neovim) that
surprised us during feature work and caused bugs. Read this before building
anything that interacts with these tools.

## Tooling · sandboxed test runners

### `make test` needs a real tmux socket

The tmux backend specs drive tmux over a private unix socket under
`/tmp/tmux-<uid>/vantage-test-<pid>`. A sandbox that blocks socket creation or
`connect()` — the Codex workspace sandbox (seccomp) does — makes every tmux
operation fail with `error connecting to
/tmp/tmux-<uid>/vantage-test-<pid> (Operation not permitted)`. The suite never
reports that as a permission error: the specs fail deeper, with `attempt to
index local 'agent' (a nil value)` in `tests/backend/tmux_spec.lua` or
`no such group '<name>'`. In-sandbox results are not trustworthy in either
direction — the same suite passed once and failed on the next run — so treat
only an unsandboxed `make test` result as authoritative.

A brand-new socket name reproduces the denial on its own:

```sh
tmux -L vantage-probe new-session -d -s probe
# error connecting to /tmp/tmux-<uid>/vantage-probe (Operation not permitted)
```

## Backend · tmux · agent CLI

### Clients attached to one session share its current window

`switch-client -c <client> -t <session>:<window>` and `select-window` change the
session's current window, not a client-local one. Two clients attached to the
same session therefore follow each other. Per-client independence requires a
grouped session per client (Vantage's View); see
[architecture.md](architecture.md#domain-model-over-the-multiplexer).

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

## Picker · dependency checks

### Runtimepath is not a reliable dependency check under lazy.nvim

A configured picker plugin may be installed but not yet on `runtimepath` when
Vantage's `setup()` runs. `nvim_get_runtime_file("lua/fzf-lua/init.lua", …)`
then returns nothing even though lazy.nvim can load the module on demand.
Check availability with `pcall(require, module)` instead; this preserves
fail-fast behavior without misclassifying a lazy-loaded dependency.

## Picker · fzf-lua

### `fzf_exec` function contents writes one item per callback

A function contents is invoked as `contents(on_write_nl, on_write, ...)`. The
**first** callback (`on_write_nl`) writes ONE item (it appends the EOL); call it
once per item, then call it with `nil` to signal end-of-input. Passing a whole
table to the first callback renders `table: 0x…`.

The write lands in a pipe that stays open until the `nil` call, so the callback
may be invoked **after** the contents function returned (from a libuv callback,
say): a pick can push entries as a process produces them. Vantage's adapter
relies on that, and ends the input with `nil` when the flow's stream is done.

### No preview function means no preview pane

`fzf_exec` hides the pane when `opts.preview` is nil and no explicit `--preview`
is set: it writes `--preview-window=hidden:right:0`, which also overrides a
preview in `$FZF_DEFAULT_OPTS`. So omitting the option is how a pick has no
preview pane, while a preview function that returns nothing keeps the pane
empty.

### Native in-place refresh (reload)

To update the list without close/reopen — close/reopen flickers because fzf is
a full-screen terminal process — use an action `{ fn = <function>, reload = true }`
together with **function** contents. Static table contents cannot reload (the
items are baked into the command when the picker opens).

### fzf returns display strings, not objects

`fzf_exec` returns the display string, not the original item. Recover the item
with a numeric-prefix round-trip (`"1. text"` and parse the leading index), and
keep that items array in sync with the content across reloads (mutable state).
The prefix does not have to be visible: `--with-nth=2..` hides it from the list
and fzf still hands actions the original line. Do NOT pair it with
`--nth=2..`: fzf evaluates `--nth` against the *transformed* line, so the
entry loses its prefix and `--nth=2..` then drops the entry's own first
field. A single-token path such as `src/main.lua` is left with an empty search
scope, and any query empties the list — `printf '1. src/main.lua\n' | fzf
--with-nth=2.. --nth=2.. --filter=main` matches nothing while the same command
without `--nth` matches.

### Window options — including `on_close` — live under `winopts`

`fzf_exec(contents, opts)` takes picker-level options (`prompt`, `actions`,
`preview`, `fzf_opts`) at the top level, but every window option lives under
`opts.winopts` — fzf-lua's own providers set `opts.winopts.on_close` (see
`providers/colorschemes.lua`). A top-level `on_close` is **silently ignored**:
the flow's handler never runs and nothing errors, so only a real fzf session
can tell you it is wrong.

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
makes — the Agent-creation Group step and `:Vantage prompt` included — renders
through the configured Picker's own engine (`pick_naive`), so a flow is
homogeneous by construction and no pick step ever opens a second window inside
another renderer's teardown. The residual boundary is a terminal-family
renderer (the `fzf-lua` Picker, or `native` with a terminal-style
`vim.ui.select` override) plus a trigger from a terminal in Normal mode: the
first closing float leaves the transient and the next step can land frozen —
press `i`, or invoke from terminal input state or a plain window.

## Picker · snacks

### Picker entries must not carry a `resolve` field

snacks' picker resolves any item with a `resolve` function during formatting —
`item.resolve(item)`, then sets `item.resolve = nil` — for lazy items. An entry
field named `resolve` therefore gets called by the picker itself, with the entry
as its only argument. Vantage's entry vocabulary (`frontend/entries.lua`) fixes
which fields an entry carries, so the shipped flows stay clear of the name.

### Closing returns to Normal mode — not your previous terminal mode

The snacks picker input is a **prompt buffer, not a terminal window**, and on
close it deliberately leaves insert mode (`stopinsert`), returning you to
Normal. A terminal window the picker was opened over does *not* get terminal
mode back on its own: it ends in Normal, because terminal mode is exclusive to
the focused window and the terminal drops out of it for the whole time the
picker is open. (fzf-lua floats do the opposite — the underlying terminal is
left in terminal mode via the term-to-term transfer.)

Consequence: a chain that mixes snacks then fzf-lua feeds the fzf float a
terminal-in-normal-mode context — exactly the context in which fzf-lua's close
leaves the racy transient described in the fzf-lua section. Homogeneous chains
(snacks-only, or fzf-lua floats opened from genuine terminal mode) never hit
it.

Vantage's snacks Picker takes the terminal out of terminal mode while the pick
is up, and hands it back in terminal mode on the way out. A pick that opens
from the vantage terminal leaves terminal mode first (`stopinsert`, before
snacks' windows take focus): the input window's insert is dropped when a float
is focused *out* of terminal mode from a callback, which is exactly what a
source that streams does — its first batch arrives from the lister's job a
tick after the keymap that started the pick, so `files` would sit in Normal
with a dead prompt while `buffers`, shown inside the keymap, inserts (see the
entry below).

The mode itself is the Terminal's, not the pick's. `Terminal.setup` installs
one unconditional `WinEnter` rule (`vantage_terminal_mode`) that enters
terminal mode whenever the Terminal's own buffer becomes the current window,
and it stays installed for the Terminal's lifetime — the accepted cost is that
a deliberate `<C-q>` into Terminal-Normal is undone by leaving and re-entering
the window. A pick's close therefore only decides *when* that window is
entered. `pick_fancy`'s `confirm` leaves insert mode, captures the choice, and
defers the close one tick: the tick puts the mode change in an earlier event
than the focus switch, so the Terminal's window-entry rule enters a *settled*
window; and inside it the pick names the window it opened from as the pick's
main window before closing, which is what makes snacks' own close focus that
window — `Picker:close()` consumes `main` in the same pass, and Neovim's
float-close fallback would otherwise return to `prevwin` or the first *tiled*
window, landing the focus on the editor behind a floating Terminal. Closing
*synchronously*, or letting snacks' own main-window fallback enter the
terminal, runs the entry while the picker is still tearing down, where the
insert is dropped and the client stays in `nt`. A cancel needs none of that:
snacks' own cancel names the invoking window as its main and closes from
Normal mode. One path covers an Esc cancel, a confirm, and the no-op confirm
of the pinned `(focused)` entry, split or floated (verified on nvim 0.12.3).

`pick_naive` (the Agent-creation Group step and `:Vantage prompt`) hands
terminal mode back from inside snacks' own post-close callback, the one
deferral point the plain select gives the implementation: its wrapped
`on_choice` issues `startinsert` *before* the flow's choice handler runs, so
the insert is pending while the handler runs. The ordering is load-bearing:
the new-Group name prompt (a cmdline `input()` scheduled from inside the
handler) keeps the scheduler alive while its `c` mode is active, so an insert
issued after the handler would see `c` and be dropped, stranding the terminal
in Normal once the prompt closes (verified on nvim 0.12.3). A Tool-entry
creation through `:Vantage show` ends in terminal mode via the show tail's
`Terminal.open` (`startinsert`) and skips the re-entry; a `switch` re-points
without showing (`retarget`), so it depends on the wrapped callback above.

### A pick's insert mode is dropped when the terminal-mode leave is unsettled

snacks enters insert mode from the pick input window's `BufEnter`
(`startinsert!`, scheduled a tick later when the mode it sees is `t`). Neovim
drops that insert whenever the float takes focus while a terminal-mode leave is
still in flight — the state a callback-driven focus change lands in. Measured
on nvim 0.12.3 with real snacks: a `t`-mode keymap over a synchronous source
ends in insert, the same keymap over a streaming source (`files`) ends in
Normal, and the same streaming source from `nt` or from a plain window ends in
insert. A minimal float without snacks reproduces it: focused inside the
keymap, a scheduled `startinsert` sticks; focused from a callback, both a
direct and a next-tick `startinsert` are dropped until the transfer settles
(tens of ms). The fix is the leave, not the insert: Vantage runs `stopinsert`
before handing a terminal-origin pick to snacks, so no transfer is in flight
when the float takes focus.

### The mini.test harness cannot observe modes

`make test` runs `nvim --headless -l`, where `startinsert` never takes effect:
`nvim_get_mode()` stays `n`, in the suite itself and from a deferred callback
(verified on 0.12.3). Mode-level assertions therefore cannot be specs; the
specs cover the wiring instead (the pick arming no restore of its own, its
close naming the invoked-from window as the pick's main window, `pick_naive`
issuing its `startinsert` before the choice handler, and the Terminal
installing its window-entry rule once) and the modes are verified by hand with
a script that reads
`nvim_get_mode()` from `vim.defer_fn` callbacks:

```sh
nvim --headless -u NONE -c 'luafile <script>'
```

A `-c`-driven script runs on the main loop and reports real modes (`i`, `t`,
`nt`); an `nvim -l` script does not. In such a script a `:terminal` window
reaches terminal mode through a deferred `startinsert`, and a float can stand
in for the client.

### Finder signature is `fun(opts, ctx): result`

The finder is `fun(opts, ctx)` returning either an `Item[]` table or an async
`fun(cb)`; it is **not** `fun(cb)` directly. The simplest form just returns the
items table.

The async form runs inside snacks' own task, and its `cb` drives that task's
coroutine, so it must not be called straight from a libuv callback. Queue what
arrives, resume the task, and call `cb` from inside the task's own loop — the
shape `snacks.picker.source.proc` uses. Vantage's adapter does exactly that for
a flow's stream that outlives the finder call; a stream that ended within the
call is returned as the static items table.

### No preview function means an empty pane, not no pane

snacks' layout carries a preview window whether or not a `preview` function is
given, and a nil one leaves it empty. To have no pane at all, pass
`layout = { preview = false }`, which snacks moves into `layout.hidden`.
Vantage's adapter does that when the flow did not ask for a preview.

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

## Gather · file listers

### The three listers do not agree on exit codes

Measured with fd 10.2.0 and ripgrep 15.2.0: `fd` exits 0 whenever it ran (empty
result included) and 1 on error; **`rg --files` exits 1 when it found no
files** and 2 on error; `find` exits 0 whenever it ran and 1 on error. So a
chain that treats every non-zero code as a failure would fall through on rg's
legitimate empty answer — and land on `find`, which reads no ignore files and
would list exactly the files the project ignores. Vantage's chain reads rg's 1
as an answer and only falls through on a real failure.

### fd and rg respect ignore files; find does not

`fd` and `rg --files` honour `.gitignore` and friends, `find` honours nothing
but the arguments it is given. That is why find is the last resort: on a
machine with neither fd nor rg, the listing is whatever find sees.

### None of the three sorts

fd, rg, and find each print in their own walk order, and the file list is
rendered in that order — the listing is not sorted, by design. `find` prints
paths with a leading `./`, which the flow normalizes away.

### `find`'s `-o` grouping decides whether an exclusion applies

`find . -type f -o -type l -not -path "*/.git/*"` parses as
`(-type f) OR ((-type l) AND (not .git below))` because find's implicit `-a`
binds tighter than `-o`: the `.git` files are regular files, so they leak
through the first branch. Grouping — `\( -type f -o -type l \) -not -path …` —
is what makes one exclusion cover both. (Through `vim.system` the parentheses
are plain arguments, no shell escaping.)

### `vim.system` reports a signalled process as exit code 0

A process killed by a signal comes back with `code = 0` and `signal = N`, not
as a failure. Treat `signal ~= 0` as a failure (the shell's `128 + N`) or a
truncated run looks like a finished one.

### A shell script that traps TERM must wait interruptibly

`trap … TERM; sleep 30` runs the trap only after `sleep` returns (the shell
defers it), so a test lister that is supposed to notice a cancel needs
`sleep 30 & wait` — `wait` is interrupted by the signal.

## Neovim

### `vim.notify` raises inside a fast event context

The default `vim.notify` handler calls `nvim_echo`, which is main-loop only:
from a libuv callback (a `vim.system` exit callback, a timer) it raises
`E5560: nvim_echo must not be called in a fast event context`. The raise also
unwinds the callback, so any statement after the notify — a `done()` that ends
a stream, say — does not run and the stream never ends. Route the notification
through `vim.schedule` instead (`vantage.util`'s `notify` already does).

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

### Help text conceals backticks, bars, and tags

Help windows set `conceallevel=2` and the help syntax conceals inline-code
backticks (and `|links|`, `*tags*`) to zero width. A column hand-aligned with
spaces in `doc/*.txt` therefore shifts left by one column per concealed marker
before it. Keep the concealed-marker count uniform per aligned line (each row
of the PROMPTS list has one backticked term), or align with tabs so the
modeline's `ts=8` tab stops absorb the shift.
