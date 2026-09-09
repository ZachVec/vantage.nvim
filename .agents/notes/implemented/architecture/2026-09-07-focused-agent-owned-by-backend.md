# Agent Note: Focused Agent is Backend-owned state

Status: implemented

## Problem

The old Frontend Client stored `last_agent` and exposed `last_agent_alive()`.
That duplicated state tmux already owns: the attached client's active window.
The copy could drift after an external tmux change or a retarget.

## Decision

`Bridge.agents(pid)` returns one live snapshot: the Agent inventory plus the
Agent currently shown by the client whose terminal job has `pid`. The focused
Agent is derived on every read from `list-clients` and the live inventory; the
Frontend stores no domain focus state.

`commands/attach.lua` uses `Bridge.agents(pid)` for the pinned focused
row and the group-scope command; `commands/prompt.lua` uses the same snapshot
to resolve its target. No separate `focused_agent()` verb exists.

## Alternatives considered

### Why not keep `last_agent` and refresh it after every operation?

That keeps a second source of truth that must be updated on every focus,
retarget, detach, and external change. Deriving from tmux has one source.

### Why not expose a separate `focused_agent()` verb?

The picker and prompt flows need the inventory and focused Agent together.
Returning both from one `snapshot(pid)` avoids a second synchronous tmux
inventory read and keeps the query contract small.

## Consequences

- `frontend/terminal.lua` stores only terminal job/buffer/window state, never
  the focused Agent.
- A stale Client-side focus copy is impossible; external tmux changes are
  reflected on the next snapshot.
- Driver integration tests derive the focused Agent before and after
  retarget.
- The current Driver/Picker result contract is owned by
  [composition-root-and-neutral-seams](2026-09-10-composition-root-and-neutral-seams.md).
