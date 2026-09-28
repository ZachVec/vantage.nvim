# Agent Note: Restore per-client Views for independent Terminal targets

Status: implemented

## Problem

The layered refactor removed tmux session groups and the Anchor/View model on
the premise that two clients attached to one session can display different
windows. That premise is false on tmux 3.6a: clients attached to one session
share its current window. A `switch-client -c <client> -t <session>:<window>`
or `select-window` on that session changes the window for every attached
client, so two Neovim instances in the same Group drag each other between
Agents.

## Decision

Restore the tmux session-group model:

- **Group** is one session group; its persistent **Anchor** session owns the
  Agent windows and keeps them alive headless.
- Each Terminal client attaches to a transient **View** session grouped with
  the Anchor. The View is marked `@vantage-view 1`; its current window is
  independent from every other client's View.
- `Driver.attach(agent, launch)` creates a fresh View, selects the target Agent
  in it, and starts the client through `launch`; it hands back the Attachment
  handle the Terminal holds, and a client that cannot start takes the View back
  down with it. The current shape of that handle and its methods is owned by
  [backend-one-layer-and-view-keyed-attachment](2026-09-20-backend-one-layer-and-view-keyed-attachment.md).
- Same-Group `retarget(agent)` selects the Agent window in the client's own
  View. Cross-Group retarget creates a fresh View in the destination Group,
  moves the client into it, adopts the new View, and destroys the old one. The
  client is always on a View the plugin created, so no Anchor-migration branch
  remains.
- A global `client-detached` hook destroys a View when its client exits, so
  Views never accumulate. Killing a Group's last Agent closes the Anchor, and
  the Views die with their detaching clients.
- `Attachment:focus()` still derives the Focus from the client's current
  window; with Views that window is per-client, so the Frontend stores no
  focus state.

## Alternatives considered

### Why not keep one session per Group?

It cannot satisfy the core requirement: tmux clients sharing one session share
its current window. The observed two-editor collision is inherent to that
topology, not a bug in `switch-client`.

### Why not create one tmux session per client with duplicated windows?

Duplicated windows would duplicate Agent processes and lose the single shared
Agent per Group. Grouped sessions share windows while giving each client an
independent current window.

### Why not rely on tmux control mode or client-local window state?

tmux has no client-local current-window state outside session groups. Control
mode adds a protocol layer without changing the session/window model.

## Consequences

- [Group/Anchor/Agent/View](../../archived/architecture/2026-08-31-group-anchor-agent-view.md)
  is current again; the archived note's model is restored under the current
  Driver result contract.
- The Driver surface replaces `attach_command(agent)` with an `attach` that
  creates the View and starts the client.
- Views are cleaned up by the `client-detached` hook, by cross-Group retarget,
  and explicitly when Terminal startup fails; `tests/commands/attach_spec.lua`
  pins the failed-startup kill, including that the Terminal keymaps are left
  unapplied.
- Driver integration tests cover two clients in one Group switching to
  different Agents independently, plus cross-Group relocation.
- The “no View” premise in
  [layered-frontend-backend-refactor](2026-09-09-layered-frontend-backend-refactor.md)
  is superseded by this decision.
