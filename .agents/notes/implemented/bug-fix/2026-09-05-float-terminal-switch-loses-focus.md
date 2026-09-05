# Agent Note: Float client loses window focus when a snacks pick closes

Status: implemented

## Problem

With `cli.win.layout = "float"` and `picker = "snacks"`, any pick that was
invoked from the vantage terminal — `:Vantage switch` to another Agent, the
kill pick, the annotation pick, the Group step, `:Vantage prompt` — left the
cursor in the editor window behind the float instead of back on the agent
terminal after the picker closed. The pick succeeded (the Client re-pointed),
but focus was on the "next" tiled window, as if the pick came from the editor.

The trigger is Neovim's float-close focus machinery, not snacks: closing a
float that is current computes the alternative window with
`win_float_find_altwin`, which returns `prevwin` and falls back to the first
*tiled* window when `prevwin` is invalid or already destroyed. Snacks'
layout teardown destroys its input/list/preview floats in arbitrary order
(`pairs`), so `prevwin` is normally a sibling picker float that has just been
freed — the fallback fires, and the focus lands on `firstwin`, the editor
window behind the float. With a tiled Client in the `full` layout the same
fallback coincidentally lands on the terminal (the dedicated tab holds one
window, so `firstwin` is it), which is why the defect was invisible before the
float layout: closing the picker never restored *the terminal the pick was
invoked from*, it restored the default first window.

## Decision

The snacks close compensation (`restore_terminal_mode` in
`lua/vantage/picker/snacks.lua`) now also re-asserts window focus. At pick
start, when `invoked_from_terminal` is set, the implementation captures
`vim.api.nvim_get_current_win()` — at that moment the current window *is* the
Client window, since the fact means "the terminal is open and current" — and
passes it into the same scheduled close handler. In the scheduled handler the
terminal window is re-focused with `nvim_set_current_win` when it is still
valid and not already current, *before* the existing terminal-mode re-entry
(`startinsert` when the mode is `nt`), whose check then runs against the
re-focused window. When the engine's own teardown (or another picker) already
restored the terminal, the re-assert is a no-op — focus re-assertion is
universal, not float-specific — so split and `full` layouts gain the same
guarantee (with `full` they were covered only by the coincidental
first-window fallback).

The re-assert stays inside the picker implementation: like the terminal-mode
re-entry, it is compensation for the engine's own close semantics, and the
[picker-pure-renderers boundary](../architecture/2026-09-05-picker-pure-renderers.md)
is kept — the implementation still requires nothing but its engine
(`nvim_get_current_win()`/`nvim_set_current_win()` are core API, and the
invoked-from window is captured, not looked up through a Vantage module).

## Alternatives considered

### Why not re-assert the Client window in the command layer (`Client.retarget`)?

`retarget` does not know it was reached through a picker close (it is also the
non-interactive `:Vantage switch @N` path), and focusing from there would steal
the cursor from a user who invoked switch from the editor — re-pointing must
not change focus. The compensation belongs to the engine that loses it, the
same reasoning as the [new-Group terminal-mode note](2026-09-05-snacks-new-group-terminal-mode.md).

### Why not fix the teardown (close picker floats in reverse-open order)?

The close order is snacks' layout `pairs` iteration, and Neovim's
`win_float_find_altwin` fallback would still land on `firstwin` once the
`prevwin` chain is exhausted for any close order where the last destroyed
window is current. Compensating on the Vantage side is deterministic and does
not fork snacks' internals.

### Why not re-focus only when the Client is a float?

The tiled paths are already restored by the same fallback only in the `full`
layout; split layouts have the identical defect (the terminal is not
`firstwin` then). A single unconditional re-assert — no-op when the restore
already happened — covers both without layout-specific branches.

## Consequences

- Every snacks pick invoked from the vantage terminal returns the focus — and
  terminal mode — to the terminal window, float or tiled; Esc-cancel paths are
  covered by the same `on_close` handler.
- fzf-lua is untouched: it restores the window it was invoked from on its own
  (`set_current_win(self.src_winid)` in its exit path), so the defect was
  snacks (and the builtin `vim.ui.select`, which uses a cmdline `inputlist`,
  with no window to lose).
- `docs/gotchas.md` and the
  [snacks terminal-mode re-entry note](2026-09-05-snacks-new-group-terminal-mode.md)
  describe the re-asserted close handler; the picker-pure-renderers note's
  snacks section references the same handler. No config or user-visible API
  change; the float layout note is unaffected (it is another consequence of
  the same layout, not a re-decision).

## Verification

Headless reproduction on nvim 0.12.3 with plain floats (the mechanics are
Neovim's, snacks' teardown is only the close): editor + terminal float +
two picker floats, destroy picker floats in either order — focus lands on the
tiled editor window (`curwin` = editor), and the scheduled re-assert puts it
back on the terminal float (`curwin` = terminal). The `full`-layout path was
left as the control: the single-window tab's `firstwin` is the terminal, no
re-assert needed.
