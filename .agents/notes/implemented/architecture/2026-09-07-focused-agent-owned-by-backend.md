# Agent Note: Focused Agent is Backend-owned state

Status: implemented

## Problem

The old Frontend Client stored `last_agent` and exposed `last_agent_alive()`.
That duplicated state tmux already owns: the attached client's active window.
The copy could drift after an external tmux change or a retarget.

## Decision

`Bridge.focus(pid)` returns the Agent currently shown by the client whose
terminal job has `pid`, or `nil` plus the reason. The Focus is derived on every
read from the client's live window and the live inventory; the Frontend stores
no domain focus state. The shape of that read is owned by
[focus-is-its-own-read](2026-09-13-focus-is-its-own-read.md).

`commands/attach.lua` reads `Bridge.inventory()` plus `Bridge.focus(pid)` for
the pinned Focus row and the group-scope command; `commands/prompt.lua`,
`commands/gather.lua`, and `commands/review.lua` resolve their target through
`Bridge.focus(pid)`.

## Alternatives considered

### Why not keep `last_agent` and refresh it after every operation?

That keeps a second source of truth that must be updated on every focus,
retarget, detach, and external change. Deriving from tmux has one source.

### Why not expose a separate Focus read?

The Focus is not a second source of truth; it is the same tmux fact answered
for one client. [Focus is its own read](2026-09-13-focus-is-its-own-read.md)
records why the read stopped sharing a return value with the inventory.

## Consequences

- `frontend/terminal.lua` stores only terminal job/buffer/window state, never
  the Focus.
- A stale Client-side focus copy is impossible; external tmux changes are
  reflected on the next read.
- Driver integration tests derive the Focus before and after
  retarget.
- The current Driver/Picker result contract is owned by
  [composition-root-and-neutral-seams](2026-09-10-composition-root-and-neutral-seams.md).
