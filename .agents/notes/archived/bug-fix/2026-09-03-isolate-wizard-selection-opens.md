# Agent Note: Isolate wizard selection opens from the closing selection UI

Status: implemented

Archived: 2026-09-03

> Record of a development-time attempt. The wait-based fix below was
> implemented and validated in a working tree, then superseded before this
> repository ever contained it — the Agent-creation wizard and `:Vantage
> prompt` now route every selection through the Picker's own engine, so there
> is nothing to wait for (see the
> [picker-owns-plain-selections note](../../implemented/architecture/2026-09-03-picker-owns-plain-selections.md)).
> The note is kept for the isolation mechanism it documents.

## Problem

Agent creation chains selection UIs back to back: `create_wizard` calls
`Select.pick_tool`, and the Tool choice's callback opens `Select.pick_group`.
Under a global `vim.ui.select` override that renders floating windows
(fzf-lua's `register_ui_select`, reached through the LazyVim fzf extra), the
second consecutive float — the Group choice — opened frozen: the picker was in
normal mode with a roaming cursor and keystrokes did not reach it (pressing
`i` restored it). Once the Group choice was fixed, the agent terminal that
opens after creation landed in normal mode too — the user had to press `i`
before typing to the new Agent. Both failures happened only when the wizard
ran over a terminal window, and only when the preceding selection float had
been opened from a normal-mode context.

Headless reproductions (no snacks or Vantage involved) pinned the mechanism:
a terminal window in normal mode opens fzf float #1 (mode `t`, fine); when
float #1 closes, Neovim's terminal-mode stickiness (the quirk fzf-lua tracks
in #2054/#2419) leaves the *terminal* in `t` mode while the renderer finishes
tearing down; anything terminal-related opened during that window — float #2's
terminal window, or a `startinsert` on the new Agent's terminal — fails to
enter terminal mode and stays in normal mode. The stuck `t` resolves by itself
once the renderer's teardown completes (~40–80 ms in the reproductions,
measured from 0 ms broken / ≥40 ms fixed). One event-loop tick is not enough —
the window is still open at tick time. When the wizard is triggered from a
plain buffer (no terminal), or when every float opens from an already-terminal
context, the failure does not occur.

Vantage owns no mode or keymap code on these UIs — the Tool and Group choice
was plain `vim.ui.select`, and the agent terminal is a plain terminal window —
so the plugin cannot force a third-party implementation into its input mode.
It can only avoid acting inside the renderer's teardown window.

## Decision

Two sites waited out the teardown window with `vim.defer_fn(…, 150)` before
touching terminal mode:

- `select_items` in `lua/vantage/select.lua` (the shared opener for the Tool
  and Group choices) deferred each `vim.ui.select` call, so a selection
  window never opened while the previous selection UI was still tearing down.
- `create_wizard` in `lua/vantage/commands.lua` deferred `do_create` (which
  ends in `Client.focus` → `startinsert` on the agent terminal) from the
  Group choice callback, so the agent terminal never opened inside the same
  teardown window.

150 ms was comfortably past the ~80 ms settle observed in reproduction, and
both constants were local and trivially raiseable if a renderer or machine
ever needed more. This extended the precedent `prompt_new_group` already set
in `select.lua` ("Scheduled so a picker window can finish closing before the
cmdline opens").

Selection semantics were unchanged: items, prompt, keys, callbacks, and the
created Agent were identical; only the opens were delayed past the previous
UI's teardown. The built-in cmdline `vim.ui.select` saw only an imperceptible
150 ms before its prompt and before the agent terminal appeared.

## Alternatives considered

### Why not a single `vim.schedule` tick?

Tried first; the reproductions show it does not help — the previous float's
teardown and the terminal's stuck `t` mode outlive one event-loop tick, so
the next float (or the agent terminal's `startinsert`) still lands inside the
racy window.

### Why not leave terminal mode explicitly before opening (feed `<C-\><C-N>`)?

Works, but only when the current window is a terminal in `t` mode, and it
pokes the user's terminal state with synthetic keys. Waiting for the teardown
to finish naturally covers the same ground without touching user state. (For
reference: `stopinsert` does not leave terminal mode; only the `<C-\><C-N>`
transition does.)

### Why not fix the renderer (fzf-lua) instead?

Out of Vantage's control, and a headless minimal reproduction (terminal
window + fzf-lua `ui_select` + two consecutive `vim.ui.select` calls, or a
terminal open within the teardown window) exists to hand upstream. Reporting
upstream stays an option.

## Consequences

- The Tool and Group choice opened ~150 ms after any preceding selection
  closed, and the agent terminal opened ~150 ms after the Group choice — so
  neither a consecutive wizard float nor the created agent's terminal ever
  overlapped its predecessor's teardown; both reliably entered terminal mode.
- No user-visible change for cmdline renderers; float renderers gained an
  imperceptible delay before each wizard selection and before the agent
  terminal appeared.
- Both delays were one local constant each; if the failure ever resurfaces
  under some renderer or machine, raising them stays a one-line change.
- The agent-list Picker (the `snacks` / `native` / `fzf-lua` pickers) was not
  covered: its choices lead to `Client.focus` for existing Agents. The
  `snacks` picker closes cleanly into normal mode and is unaffected; a
  `native`-mode user whose `vim.ui.select` is overridden by a float renderer
  could hit the same window when switching Agents — a latent instance of the
  same mechanism, to fix centrally if it is ever reported.

This refined the plain-`vim.ui.select` mechanism of the
[plain-selection note](../architecture/2026-09-02-plain-selection-via-ui-select.md).
Both are superseded: the Picker owns every selection today (see the
[picker-owns-plain-selections note](../../implemented/architecture/2026-09-03-picker-owns-plain-selections.md)),
and the residual boundary of a terminal-family renderer plus a Normal-mode
terminal trigger is documented in `docs/gotchas.md`.
