# Agent Note: The pick's close belongs to the picker implementation

Status: implemented

## Problem

Two flows restored the invoking window after a pick, duplicating a
compensation the Picker implementation already performed.

`commands/gather.lua` captured the current window at pick start and restored
it from `PickOpts.on_close`; `commands/prompt.lua` captured the window and
restored it from its plain-select choice callback (so a cancelled prompt was
never restored at all). Both flows are Terminal actions, so the window they
restored is the Vantage Terminal — and that window already had an owner. The
snacks implementation names the terminal window as the pick's main window on
close and lets the Terminal's window-entry rule restore the mode, because two
of the properties are snacks' own: its picker input is a prompt buffer that
closes with `stopinsert` (so a terminal comes back in `nt`, not `t`), and its
layout teardown destroys its floats in `pairs` order, which turns Neovim's
float-close fallback
(`win_float_find_altwin` → `firstwin`) into a move to the editor behind the
terminal. fzf-lua restores the window it was invoked from in its own exit path
(`set_current_win(src_winid)`), and `native` follows the global
`vim.ui.select`, whose builtin `inputlist` has no window to lose — see
[float client loses window focus when a snacks pick closes](../bug-fix/2026-09-05-float-terminal-switch-loses-focus.md).

`PickOpts`/`PickMultiOpts` therefore carried an `on_close` with exactly one
consumer, and that consumer existed only to re-do the implementation's job.
The interface invited the next flow to write the same compensation again,
which is what `gather` had just done.

## Decision

An implementation owns what its own close does: it leaves the window the pick
was invoked from current when the picker closes, with that window's mode
intact, and compensates for its own teardown whenever its engine loses either.
The guarantee is stated on `vantage.PickerImpl` in
`frontend/picker/init.lua`, described in `docs/architecture.md`, and its engine
mechanics stay in `docs/gotchas.md`; the global `vim.ui.select` that `native`
follows is the one named exception.

`on_close` is gone from `PickOpts`, `PickMultiOpts`, the facade, and the three
implementations. The snacks implementation still owns its own close — its
`confirm` names the invoked-from window as the pick's main window, and the
Terminal's window-entry rule restores the mode
([the Terminal-owns-its-mode note](../bug-fix/2026-09-25-the-terminal-owns-its-mode.md))
— and no longer wraps a flow callback; fzf-lua no longer sets
`winopts.on_close`; `native` no longer calls one. `gather` and `prompt` are back
to what a flow knows: which entries to offer and what a choice means.

## Alternatives considered

### Why not have the facade own the restore?

That was the first proposal, and it loses on the facts: the mode re-entry is
snacks' semantics (a prompt-buffer input that closes with `stopinsert`), and
the lost focus is Neovim's float-close fallback triggered by snacks' teardown
order. fzf-lua and `native` never lose either, so a facade-level restore would
apply every engine a compensation only one of them needs, and would have to
carry engine knowledge it cannot have. The ownership decision predates this
note and stands:
[picker implementations are pure renderers](../architecture/2026-09-05-picker-pure-renderers.md).

### Why not keep `on_close` as an extension point?

One adapter means a hypothetical seam. After the two flow compensations go,
nothing calls it: a callback kept for a caller that does not exist is surface
area that every implementation must keep threading and every spec must keep
faking. If a flow ever needs to act after a close, the cost of adding a close
hook back is one small change — that reintroduction condition is what this
section records.

### Why not delete only the flow compensations and leave the interface alone?

Leaving `on_close` in the contract while deleting its only user leaves a
callback the next `gather` would reach for again. Deleting the compensations
and the hook together is what makes the guarantee legible: the interface now
says who is responsible, instead of leaving it to `docs/gotchas.md`.

## Consequences

- No flow restores a window or a mode, and no flow passes a close callback;
  `vantage.PickerImpl` is where that promise is written down.
- A `native` install whose global `vim.ui.select` override does not hand the
  window back keeps that renderer's behaviour — Vantage never promised it for
  someone else's renderer, and the contract says so.
- The four flow-side spec surfaces shrink: nothing asserts a forwarded
  `on_close` any more, and `gather`/`prompt` no longer capture a window.
- The redundant compensation is gone, so the redundant *verification* is too:
  the focus and mode guarantees are the snacks implementation's to keep, and
  its own specs and `docs/gotchas.md` cover them.
- `docs/architecture.md` states the ownership; the
  [file/buffer references note](../feature/2026-09-11-file-buffer-references.md)
  no longer claims `PickOpts` carries `on_close`.

## Verification

The premise was re-reproduced on nvim 0.12.3 with a one-shot headless script:
an editor window, a terminal float, and two picker floats opened over it.
Closing the two picker floats left `curwin` on the editor window — the
float-close fallback — while the picker's own close, with the terminal named as
its main window, put `curwin` back on the terminal float. That half of the
compensation is therefore still doing the work the deleted flow code was
duplicating.

The terminal-mode half could not be measured in that headless run: under
`--headless -l` the terminal job never reached `t`, so the `nt` → `t`
re-entry still rests on the real-UI reproduction in
[float client loses window focus when a snacks pick closes](../bug-fix/2026-09-05-float-terminal-switch-loses-focus.md)
and on the snacks behaviours recorded in `docs/gotchas.md`. A manual pass with
the real snacks and fzf-lua plugins over the `float`, `full`, and split
layouts closes it: focus and terminal mode both come back to the terminal
window on every path a flow picks from, which is the behaviour the deleted
flow code was duplicating.
