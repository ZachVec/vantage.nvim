# Agent Note: Float client loses window focus when a snacks pick closes

Status: implemented

## Problem

With `cli.win.layout = "float"` and `picker = "snacks"`, any pick that was
invoked from the vantage terminal — the `switch` key to another Agent, the
kill pick, the `prompt` key — left the
cursor in the editor window behind the float instead of back on the agent
terminal after the picker closed. The pick succeeded (the Terminal re-pointed),
but focus was on the "next" tiled window, as if the pick came from the editor.

The trigger is Neovim's float-close focus machinery, not snacks: closing a
float that is current computes the alternative window with
`win_float_find_altwin`, which returns `prevwin` and falls back to the first
*tiled* window when `prevwin` is invalid or already destroyed. Snacks'
layout teardown destroys its input/list/preview floats in arbitrary order
(`pairs`), so `prevwin` is normally a sibling picker float that has just been
freed — the fallback fires, and the focus lands on `firstwin`, the editor
window behind the float. With a tiled Terminal in the `full` layout the same
fallback coincidentally lands on the terminal (the dedicated tab holds one
window, so `firstwin` is it), which is why the defect was invisible before the
float layout: closing the picker never restored *the terminal the pick was
invoked from*, it restored the default first window.

## Decision

The snacks implementation's own close names the window the pick was invoked
from as the pick's main window (`lua/vantage/frontend/picker/snacks.lua`). At
pick start, when the current window is the Vantage Terminal, it captures
`vim.api.nvim_get_current_win()` — at that moment the current window *is* the
Terminal window, since filetype detection means the pick runs inside it — and
its deferred `confirm` sets `picker.main` to that window before
`picker:close()`. Snacks' own close focuses `main`, so the focus comes back
from the engine's own mechanism instead of a Vantage `nvim_set_current_win`;
`Picker:close()` consumes `main` in the same pass and only moves focus when the
current window is one of the picker's, so the naming is a no-op for a close
that already landed on the terminal. Naming the main window is unconditional
and layout-free, so split and `full` layouts get the same guarantee (with
`full` they were covered only by the coincidental first-window fallback), and
a cancel is covered by snacks' own cancel, which names the invoking window as
its main.

Terminal mode follows the focused window: it is the Terminal's own
window-entry rule
([the Terminal-owns-its-mode note](2026-09-25-the-terminal-owns-its-mode.md)),
and the plain select path issues its `startinsert` from snacks' post-close
callback before running the choice handler.

The compensation stays inside the picker implementation: like the terminal-mode
restore, it corrects the engine's own close semantics, and the
[picker-pure-renderers boundary](../architecture/2026-09-05-picker-pure-renderers.md)
is kept — the implementation still requires nothing but its engine
(`nvim_get_current_win()` is core API, and the invoked-from window is captured,
not looked up through a Vantage module).

## Alternatives considered

### Why not re-assert the Terminal window in the command layer?

`retarget` does not know it was reached through a picker close, and focusing
from there would change focus as a side effect of re-pointing. The
compensation belongs to the engine that loses it, the same reasoning as
[the Terminal-owns-its-mode note](2026-09-25-the-terminal-owns-its-mode.md).

### Why not fix the teardown (close picker floats in reverse-open order)?

The close order is snacks' layout `pairs` iteration, and Neovim's
`win_float_find_altwin` fallback would still land on `firstwin` once the
`prevwin` chain is exhausted for any close order where the last destroyed
window is current. Telling the engine which window the close should land on is
deterministic and does not fork snacks' internals.

### Why not re-focus only when the Terminal is a float?

The tiled paths are already restored by the same fallback only in the `full`
layout; split layouts have the identical defect (the terminal is not
`firstwin` then). Naming the pick's main window is unconditional and covers
both without layout-specific branches.

## Consequences

- Every snacks pick invoked from the vantage terminal returns the focus — and,
  through the Terminal's window-entry rule, terminal mode — to the terminal
  window, float or tiled; Esc-cancel paths are covered by snacks' own cancel.
- fzf-lua is untouched: it restores the window it was invoked from on its own
  (`set_current_win(self.src_winid)` in its exit path), so the defect was
  snacks (and the builtin `vim.ui.select`, which uses a cmdline `inputlist`,
  with no window to lose).
- `docs/gotchas.md` and
  [the Terminal-owns-its-mode note](2026-09-25-the-terminal-owns-its-mode.md)
  describe the close that names the invoked-from window. No config or
  user-visible API change; the float layout note is unaffected (it is another
  consequence of the same layout, not a re-decision).

## Verification

Headless reproduction on nvim 0.12.3 with plain floats (the mechanics are
Neovim's, snacks' teardown is only the close): editor + terminal float +
two picker floats, destroy picker floats in either order — focus lands on the
tiled editor window (`curwin` = editor), while the picker's own close, with the
terminal named as its main window, puts it back on the terminal float
(`curwin` = terminal). The `full`-layout path was left as the control: the
single-window tab's `firstwin` is the terminal, no compensation needed.
