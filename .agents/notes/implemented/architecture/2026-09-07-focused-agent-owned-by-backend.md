# Agent Note: Focused Agent is Backend-owned state

Status: implemented

## Problem

The old Frontend stored a `last_agent` copy and exposed `last_agent_alive()`.
That duplicated state tmux already owns: the attached client's active window.
The copy could drift after an external tmux change or a retarget.

## Decision

The Terminal's Attachment answers the Focus: `focus()` returns the Agent its
client is currently showing, or `nil` plus the reason. The Focus is derived on
every read from the View's live window; the Frontend stores no domain focus
state (the Attachment it holds is identity, not a focus copy). The shape of
that read is owned by
[focus-is-its-own-read](2026-09-13-focus-is-its-own-read.md) and
[backend-one-layer-and-view-keyed-attachment](2026-09-20-backend-one-layer-and-view-keyed-attachment.md).

`commands/attach.lua` reads `Backend.inventory()` plus the Attachment's
`focus()` for the pinned Focus entry and the group-scope command;
`commands/prompt.lua`, `commands/gather.lua`, and `commands/review.lua` resolve
their target the same way.

## Alternatives considered

### Why not keep `last_agent` and refresh it after every operation?

That keeps a second source of truth that must be updated on every focus,
retarget, detach, and external change. Deriving from tmux has one source.

### Why not expose a separate Focus read?

The Focus is not a second source of truth; it is the same tmux fact answered
for one client. [Focus is its own read](2026-09-13-focus-is-its-own-read.md)
records why the read stopped sharing a return value with the inventory.

## Consequences

- `frontend/terminal.lua` stores only terminal job/buffer/window state plus the
  Attachment handle, never the Focus.
- A stale Frontend-side focus copy is impossible; external tmux changes are
  reflected on the next read.
- Driver integration tests derive the Focus before and after
  retarget.
- The current Driver/Picker result contract is owned by
  [composition-root-and-neutral-seams](2026-09-10-composition-root-and-neutral-seams.md).
