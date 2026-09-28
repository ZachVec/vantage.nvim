# Agent Note: The Terminal owns the mode a pick hands back

Status: implemented

## Problem

The vantage terminal has no Normal-mode state of its own. It exists to type
into an Agent, and terminal mode is exclusive to the focused window, so a
selection UI opened over it leaves it in Normal for as long as the pick is up.
Every pick that opens from the terminal therefore has to put the Terminal back
in terminal mode on the way out.

The shape that did this scoped the restore to the pick. `pick_fancy` armed a
`WinEnter` autocmd on the invoked-from window for the pick's lifetime, its
`on_close` re-asserted that window one tick later, and the same module wrapped
`pick_naive`'s choice callback in a scheduled "is the mode `nt`?" check. The
Terminal's mode was thus owned by whichever pick happened to be on screen and
by a timer inside that pick's close path — with two different mechanisms,
because the plain select call hands the implementation no close hook of its
own ([the shape this
replaces](../../archived/bug-fix/2026-09-25-picks-over-the-terminal-keep-insert.md)).

The exit side is Neovim's unsettled window transfer. Closing a pick
*synchronously*, or letting snacks' own main-window fallback enter the
terminal, runs the entry while the picker is still tearing down, and the
`startinsert` is dropped — the client stays in `nt`.

## Decision

The Terminal owns its own mode. `Terminal.setup` installs one unconditional
`WinEnter` autocmd (augroup `vantage_terminal_mode`) that enters terminal mode
whenever the Terminal's own buffer becomes the current window. It is installed
once, for the Terminal's lifetime, is inert while no Terminal buffer exists,
and is not scoped to a pick or an intent flag. A pick's close, or anything
else that focuses the window, therefore only decides *when* the window is
entered; the mode follows from the entry.

`lua/vantage/frontend/picker/snacks.lua`'s `pick_fancy` keeps the open-side
leave and drops the rest of the armour:

- **Open.** `stopinsert` before handing the pick to snacks, when the current
  window is the Terminal (unchanged).
- **Confirm.** `stopinsert`, capture the choice (`spec.many` and
  `picker:selected({ fallback = true })`, or the entry under the cursor), and
  `vim.schedule` the close. Inside the scheduled close it names the
  invoked-from window as the pick's main window (`picker.main = terminal_win`)
  and calls `picker:close()`, then schedules `opts.on_choices`. A second
  confirm before that tick is ignored.
- **Cancel.** Nothing: snacks' own cancel names the invoking window as its main
  and closes from Normal mode, and the Terminal's rule restores the mode when
  that window is entered.

The deferral is load-bearing: it puts the mode change in an earlier event than
the focus switch, so the Terminal's window-entry rule enters a settled window,
and `picker.main` must be set before `close()` because `Picker:close()` consumes
it in the same pass.

`pick_naive` issues `vim.cmd("startinsert")` before the flow's choice handler
when the pick opened from the Terminal. That callback is snacks' own
post-close tick — the naive path's deferral point — so the insert lands on the
settled window and stays pending while the handler runs.

## Alternatives considered

### Why not keep the restore armed for the pick's lifetime?

That was the shape this replaces, and it loses on ownership: it makes the
Terminal's mode a function of one pick's lifetime and of a timer in its close
path, needs a second mechanism for the plain select because that call exposes
no close hook, and leaves the cancel path depending on the engine's own close
entering the window. A rule keyed on window entry is the Terminal's own fact,
and every path that hands the window back — a confirm, a cancel, a flow that
shows it later — gets it for free. The cost is that the rule is unconditional,
accepted in Consequences.

### Why not retry the close's `startinsert` until it sticks?

Measured to work, and rejected: the deferral already makes the entry land on a
settled window, so a retry adds a timer-shaped mode restoration for no gain,
and it would still not cover a cancel, where no flow callback runs.

### Why not let snacks restore the focus (`main = { current = true }`)?

Measured with the real picker: pointing the pick's main window at the origin
still enters it while the picker tears down, so the entry's `startinsert` is
dropped and the client stays in `nt`; without it, a floated terminal's pick
closes onto the editor behind. Neither replaces naming `picker.main` inside
the deferred close.

### Why not fix the open side in the flow (`commands/gather.lua`)?

Leaving terminal mode before the pick is engine compensation, not flow
semantics: the snacks backend already owns the pick's close, and the seam's
contract is that an implementation compensates for its own engine's teardown.
A flow-level `stopinsert` would fix `files` and leave every other
terminal-origin pick depending on whether its source happens to be
synchronous.

### Why not document "press `i`"?

The pick's prompt is dead in Normal and the two gather keys would stay
inconsistent; typing references into the Agent is the whole point of the key.

## Consequences

- `files` opens in Insert like `buffers`, from a terminal-mode key and from
  terminal-normal mode. Its first `Esc` leaves insert (as in `buffers`) instead
  of cancelling the pick outright; README and `doc/vantage.nvim.txt` say
  cancelling a long listing takes that second `Esc` (or `<C-c>`).
- A cancel and a confirm hand the client back to the origin window in terminal
  mode, floated or split.
- The rule is unconditional, so a deliberate `<C-q>` into Terminal-Normal is
  undone by leaving and re-entering the window; README and `doc/vantage.nvim.txt`
  state it, and it is the price of having no pick-scoped intent flag.
- Accepted, not fixed: a pick that never shows (zero results) closes itself and
  leaves the terminal in Terminal-Normal, and a pick window closed by other
  means is undefined — there is no fallback.
- `fzf-lua` and `native` are untouched, and the picker facade and the
  `vantage.PickerImpl` surface are unchanged — its statement of the close
  guarantee now says the window's own owner settles the mode.
- `docs/gotchas.md` records the window-entry rule, the deferred close, and the
  plain wrapper's ordering. Mode-level assertions cannot be specs
  (`nvim --headless -l` never enters insert, so `nvim_get_mode()` stays `n`), so
  the specs pin the wiring instead: the pick arms no restore of its own, its
  close names the invoked-from window as the pick's main window, `pick_naive`
  issues its insert before the choice handler, and `Terminal.setup` installs
  one window-entry rule.

## Verification

The finalized shape was measured with the real snacks and the real adapter
through a `-c`-driven script (which does report real modes, unlike `nvim -l`):
{float, split} × {streaming, synchronous source} × {confirm, cancel} from a
terminal-mode keymap, the same matrix from Terminal-Normal mode and from a plain
window, and the naive path with a cmdline after the choice. The pick opens in
Insert and the client ends back on the origin window in terminal mode (`t`) in
every case, and a plain-window origin leaves the terminal untouched. The
counter-examples that justify the deferral were measured against it too:
`pick_fancy` with a synchronous close ends `terminal/nt`, and the naive wrapper
without its insert ends `terminal/nt`.

The shipped modules were then re-run the same way, with no line substitutions,
against a real `Terminal.open` client: {float, split} × {confirm, cancel} plus
the naive cmdline path all end `terminal/t`, and a zero-result source leaves the
client in `nt` — the accepted, unfixed case.
