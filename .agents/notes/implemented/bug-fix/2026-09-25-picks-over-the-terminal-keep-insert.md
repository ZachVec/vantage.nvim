# Agent Note: A pick over the terminal opens in Insert and hands it back typing

Status: implemented

## Problem

The `files` key's pick opened in Normal mode: the pick's prompt buffer was
current, but typing did nothing until the user pressed `i`. `buffers` — the
other gather key, through the same `Picker.pick_fancy` — opened in Insert. The
two flows differ only in *when* snacks shows the pick. `buffers` emits its
list inside the finder call, so snacks' empty-pattern fast path shows the pick
synchronously, inside the terminal-mode keymap that invoked it. `files`
streams from a lister job
([the listing note](../feature/2026-09-19-streaming-file-listing.md)), so the
finder task is still running when the pick starts and the pick is shown a tick
later, from the job's callback.

snacks enters insert mode from the pick input window's `BufEnter`. Neovim
drops that insert when the float takes focus while a terminal-mode leave is
still in flight — the state a callback-driven focus change lands in. Measured
on nvim 0.12.3 with real snacks and a real `fd` stream: a terminal-mode keymap
over a synchronous source ends in insert, the same keymap over a streaming
source ends in Normal, and the streaming source from terminal-normal mode or
from a plain window ends in insert. A minimal float without snacks reproduces
the split on its own: focused inside the keymap, a scheduled `startinsert`
sticks; focused from a callback, a direct and a next-tick `startinsert` are
both dropped until the transfer settles (tens of ms).

The exit side is the same unsettled transfer. The snacks backend re-entered
terminal mode with one scheduled `startinsert` when the mode was `nt`
([the float focus note](2026-09-05-float-terminal-switch-loses-focus.md)),
which lands inside that window: closing a pick over a floating terminal was
measured still in `nt` 260 ms later, and the picker's float teardown can also
leave focus on the editor behind it.

## Decision

`lua/vantage/frontend/picker/snacks.lua`'s `pick_fancy` treats a pick that
opens from the vantage terminal as a round trip that owns the terminal's mode,
in three parts:

- **Open.** It runs `stopinsert` before handing the pick to snacks, so no
  terminal-mode leave is in flight when the float takes focus and the input
  window's own insert lands. This is the whole open-side fix; the pick does
  not need to be deferred.
- **Restore.** It arms a `WinEnter` autocmd for the window the pick opened
  from — `vantage_picker_restore`, armed when the pick opens and disarmed when
  it closes — that re-enters terminal mode when that window is entered. The
  mode belongs to the window-entry event, not to a timer in the close path.
- **Close.** `on_close` re-asserts that window on the next tick, and nothing
  else. The tick is load-bearing: a synchronous re-assert — or letting
  snacks' own main-window fallback enter the terminal — runs the entry while
  the picker is still tearing down, and the restore's `startinsert` is
  dropped, leaving the client in `nt`.

Measured with the shipped shape, the real adapter and a real `fd` stream, over
{float, split} × {streaming, synchronous source} × {confirm, cancel}: the pick
opens in Insert and the client ends back on the origin window in terminal mode
in all eight.

`Picker.pick_plain` keeps its own single-tick check
([the new-Group note](2026-09-05-snacks-new-group-terminal-mode.md)); the
Group step's cmdline ordering is untouched, and `restore_terminal_mode` now
serves that path alone.

## Alternatives considered

### Why not retry the close handler's `startinsert` until it sticks?

The previous handler already checked the next tick; repeating the check would
have fixed the exit side with the smallest diff. Rejected: it keeps the mode a
function of a timer inside the close path, and it does nothing for the open
side. It also cannot cover a cancel, where no flow callback runs — the
window-entry restore can.

### Why not keep the restore armed for the terminal's lifetime?

sidekick.nvim solves this problem with `stopinsert` before its pick plus a
permanent `WinEnter`/`normal_mode` pair on its terminal window, and re-focuses
the terminal from its `send` path after the pick. Its permanent autocmd is
defensible there because a scrollback buffer makes "Normal in the terminal" a
first-class state; Vantage has no such state, and a permanent rule would
change every way of entering the terminal window, far beyond the pick that
created the problem. Arming the restore for the pick's lifetime keeps the
decision inside the pick.

### Why not let snacks restore the focus (`main = { current = true }`)?

Measured: pointing the pick's main window at the origin still enters it while
the picker tears down, so the restore's `startinsert` is dropped and the
client stays in `nt`; without it, a floated terminal's pick closes onto the
editor behind. Neither replaces the scheduled re-assert.

### Why not fix the open side in the flow (`commands/gather.lua`)?

Leaving terminal mode before the pick is engine compensation, not flow
semantics: the snacks backend already owns the pick's close, the invoked-from
window, and the terminal-mode re-entry, and the seam's contract is that an
implementation compensates for its own engine's teardown. A flow-level
`stopinsert` would fix `files` and leave every other terminal-origin pick
depending on whether its source happens to be synchronous.

### Why not document "press `i`"?

The pick's prompt is dead in Normal and the two gather keys would stay
inconsistent; typing references into the Agent is the whole point of the key.

## Consequences

- `files` opens in Insert like `buffers`, from a terminal-mode key and from
  terminal-normal mode. Its first `Esc` leaves insert (as in `buffers`)
  instead of cancelling the pick outright; README and `doc/vantage.nvim.txt`
  now say cancelling a long listing takes that second `Esc` (or `<C-c>`).
- A cancel and a confirm hand the client back to the origin window in terminal
  mode, floated or split; the window re-assert stays in the implementation's
  close, and the mode is a window-entry event scoped to the pick.
- `Picker.pick_plain`, `fzf-lua`, and `native` are untouched.
- `docs/gotchas.md` records the unsettled-transfer rule, the three-part shape,
  and that the mini.test harness (`nvim --headless -l`) cannot observe modes.
  Its picker spec pins the wiring instead: the restore armed while the pick is
  open, disarmed by its close, and the close re-asserting the invoked-from
  window. The modes themselves stay hand-verified with the `-c`-driven recipe
  in that file.
