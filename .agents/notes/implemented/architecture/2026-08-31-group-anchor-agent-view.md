# Agent Note: Group/Anchor/Agent/View — session groups keep agents alive headless

Status: implemented

## Problem

Agents must outlive the client that created them (headless survival), each attached client needs its own independent view of the same agents, and views must not accumulate as clients come and go.

## Decision

The domain maps onto tmux session groups:

- **Group** = a tmux session group, derived from its agents.
- **Anchor** = the one persistent session that owns the agents; it is never marked and never auto-destroyed, so the group stays alive headless.
- **Agent** = a tmux window in the Anchor, marked with `@agent-cmd` / `@agent-cwd` / `@agent-name`.
- **View** = a transient session grouped with the Anchor, marked `@vantage-view 1`; a global `client-detached` hook kills a View when its client detaches, so Views never accumulate.

Creating the first agent uses `new-session` (which also starts the server and applies config); later agents use `new-window -t <view>` so they join the existing group. Attach creates a new grouped session and re-targets it at the chosen window.

## Alternatives considered

### Why not one session per client with duplicated windows?

Windows would diverge per client, and there would be no single owner keeping agents alive.

### Why not kill agents when the client detaches?

It loses the core headless property — agents should survive editor closes until killed explicitly.

### Why not a single shared session for all clients?

tmux shows one active window per client, so per-client "which agent am I looking at" would collide; grouped sessions give each client an independent active window over shared windows.

## Consequences

- `kill <group>` kills all of a group's sessions (Anchor + Views) and thus its agents; killing the last agent empties the group, which dies with it.
- The client-detached hook must run in a separate `run-shell` process (`tmux -S <socket> kill-session …`) because a direct kill from the hook's command context does not take effect — a subtlety now owned by the driver.
- A View also ends when its Client re-targets into another Group: the driver moves the client into a fresh View of the destination Group and destroys the old one, so Views still never accumulate — see the [cross-Group switch note](../bug-fix/2026-09-05-cross-group-switch-relocates-view.md).

The terms are defined once in [the domain glossary](../process/2026-08-31-domain-glossary.md).
