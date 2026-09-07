# Agent Note: Focused Agent is Backend-owned state

Status: implemented

## Problem

`client.lua` stored `last_agent` and exposed `last_agent_alive()`. The Client
is a frontend object; remembering which Agent its View is showing duplicates
state that tmux already owns as the View's active window. Keeping that copy
made Client responsible for domain truth and could drift after external tmux
changes or a View relocation.

## Decision

The Backend now exposes `focused_agent(view)`, which derives the displayed
Agent from the View's active tmux window and the live Agent inventory.
`client.lua` no longer stores `last_agent`; `Client.focused_agent()` delegates
to `Backend.focused_agent(M.view)` and returns nil when there is no View.

`Backend.snapshot(view?)` now also returns the focused Agent when a View is
provided, so the Agent picker can read the inventory and focused Agent in one
`list()` call instead of `list()` followed by `focused_agent()`.

Callers (`select.lua`, `commands/prompt.lua`) ask
`Client.focused_agent()` instead of `Client.last_agent_alive()`.

## Alternatives considered

### Why not keep `last_agent` and refresh it after every Backend call?

That keeps a second source of truth that must be updated in every focus,
retarget, attach, detach, and external-change path. Deriving from the View
has one source of truth: tmux.

### Why not have callers reach `Backend.focused_agent()` directly?

Callers would then need to know the Client's current View name. The Client
already owns that identifier, so a thin `Client.focused_agent()` delegation
keeps the boundary clear.

## Consequences

- Client state shrinks by one field and one inventory scan.
- Focused Agent is computed live from the View, so external tmux state and
  cross-Group View relocations cannot leave a stale Client-side copy.
- `Backend.focused_agent` is part of the Backend seam and available to future
  drivers.
- The Agent picker uses `Backend.snapshot(Client.view)` for its inventory and
  focused pin, reducing duplicate synchronous inventory reads.
- Backend tests cover deriving the focused Agent before and after retarget.
