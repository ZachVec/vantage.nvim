# Agent Note: Cross-Group switch relocates the client's View

Status: implemented

## Problem

`:Vantage switch` re-pointed the terminal through `Backend.select_window(view,
target)` — a bare `tmux select-window -t <view>:<window>`. A tmux client can
only display the windows of its own session group: when the target Agent lived
in a different Group, tmux errored `can't find window: <id>` (exit 1, verified
on tmux 3.6a) and nothing moved. The driver ignored the exit code, so the
picker closed and the terminal stayed on the old Agent with no message — a
silent failure.

## Decision

`Backend.retarget(view, group, target)` replaces `select_window`. The target
Group is passed explicitly — the Backend never infers it. Re-pointing is then:

- **Same Group** — unchanged: a plain `select-window` on the Client's View. No
  View churn on everyday switching.
- **Cross Group** — the driver creates a fresh View in the target Group (the
  same `new-session -t <group session>` shape `attach` uses, marked
  `@vantage-view 1`), points it at the target window, moves the Client into it
  with `switch-client -c <client> -t <view>`, and then destroys the old View —
  its client left it, and Views never accumulate. The client is identified by
  `list-clients` filtered on the current View session: a View belongs to
  exactly one client, so the match is exact.

Failures warn (`Util.warn`) instead of passing silently: a stale target window,
no client attached to the View, or a failed move. The move is ordered so a bad
target aborts cleanly — the fresh View is destroyed, the Client stays in place.

`Client.retarget` and the attached branch of `Client.focus` both go through the
new method and adopt the returned View name; in-group calls return the same
View.

## Alternatives considered

### Why not keep `select-window` and target the destination Group's session?

`select-window` changes the current window of the window's session group; a
window outside the Client's session group errors (`can't find window`) and the
display never moves — the command's exit code was the bug's telltale, ignored.

### Why not `switch-client -t <session>` without `-c`?

An external `switch-client` without `-c` targets tmux's ambient "current
client": `no current client` when none exists, and ambiguous when several do
(another editor's Vantage client, transient command clients). Resolving the
client by its attached View is deterministic by construction.

### Why not attach the Client to the target Group's Anchor instead of a fresh View?

The Anchor is the Group's own persistent session, never a client's display. A
client attached to it would have no View, breaking the one-View-per-client
invariant that keeps per-client active windows independent, and blurring the
Anchor's "keeps the Group alive unattached" role.

### Why not reuse an existing View in the target Group?

A View is a client's display; a live View in another Group already belongs to
another editor's client. tmux cannot re-parent a grouped session, so a fresh
View — exactly what `attach` does for a new client — is the only per-client
option.

## Consequences

- Cross-Group `:Vantage switch` (and the re-point branch of `Client.focus`)
  relocate the Client: a fresh View in the destination Group, the old View
  destroyed, Agents untouched.
- A View now ends when its client detaches **or** re-targets into another
  Group; the driver destroys the abandoned View explicitly (`client-detached`
  covers only detach). Glossary, `docs/architecture.md`, and
  `doc/vantage.nvim.txt` describe the extended lifecycle.
- The [Backend surface note](../architecture/2026-08-31-backend-driver-seam.md)
  and the [re-point primitive note](../architecture/2026-09-05-toggle-switch-command-boundary.md)
  were updated to the shipped `retarget`; the
  [Group/Anchor/Agent/View note](../architecture/2026-08-31-group-anchor-agent-view.md)
  now records the extra View end condition.
- Same-Group switching is behavior-identical to before; only the failure path
  changed from silent to warned.
