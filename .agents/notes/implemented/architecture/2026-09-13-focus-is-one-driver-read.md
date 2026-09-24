# Agent Note: Focus is one Driver read

Status: implemented

## Problem

The Focus read cost two multiplexer queries. The Driver exposed
`client_window(pid)` (one `list-clients`) and `agents()` (one `list-windows
-a`), and the Backend matched the client's window id against the inventory
([focus-is-its-own-read](2026-09-13-focus-is-its-own-read.md)). The match is
driver-neutral, but the second query is not free: every `focus` read paid it,
and the attach flow, which also calls `inventory()`, paid the inventory query
twice. `client_window` had no other consumer — it existed only to feed the
Backend's composition — so the contract carried a verb no caller wanted.

## Decision

The shape below is superseded by
[backend-one-layer-and-view-keyed-attachment](2026-09-20-backend-one-layer-and-view-keyed-attachment.md):
the Focus read is now the Attachment's `focus()`, keyed by the View the client
sits on rather than by its process pid, and it needs no client at all. The
reasoning stands — one query per question, no optional-capability fallback, and
reasons as messages.

`vantage.Driver` exposes `focus(pid)` → `Agent?, string?` in place of
`client_window(pid)`; the verb count stays 12. The tmux Driver answers it in one
`list-clients -F`: the format reads the client's pid, its current window id, and
that window's `@agent-*` fields together, and tmux resolves those window options
through the client's current window. A row whose `@agent-group` is empty is a
client that is not on an Agent window — `Config.FOCUS_NO_FOCUS`; no row for the
pid is `Config.FOCUS_NO_CLIENT`; a missing server is `nil` plus the tmux reason,
as before.

`Backend.focus(pid?)` keeps only the "no Terminal at all" case
(`Config.FOCUS_NO_TERMINAL`) before forwarding to the Driver: that fact is the
Frontend's, not the multiplexer's. `Config.FOCUS_SERVER_DOWN` is deleted — it
was only the unreachable `or` fallback of a branch that no longer exists.

One read per question is unchanged: `inventory()` still never reads clients.

## Alternatives considered

### Why not an optional `focus` capability, with the old composition as fallback?

The Picker degrades optional capabilities an implementation lacks. Here the
fallback would have to re-create `client_window` and the window-id match, and no
Driver is expected to lack `focus`: any multiplexer that can say which window a
client shows can read that window's metadata. A capability nothing varies
across is a hypothetical seam, so `focus` is required like every other verb.

### Why not keep `client_window` as well?

Nothing else read it. `retarget` identifies its client through the Driver's own
client lookup, not `client_window`, so keeping it would have left a contract
verb with no consumer and a raw-window escape hatch the Frontend must not use.

### Why not have the Driver return a neutral cause instead of the config messages?

Same reasoning as the reasons themselves
([focus-is-its-own-read](2026-09-13-focus-is-its-own-read.md)): no caller
branches, so the reasons stay the messages callers report. Keeping
`FOCUS_NO_CLIENT` and `FOCUS_NO_FOCUS` in shared `config.lua` leaves one
spelling, and the Driver already requires `config` for the socket.

## Consequences

- A Focus read is one tmux process instead of two; the attach flow drops from
  three queries (inventory, client, inventory again) to two.
- The window-id match leaves the Backend: each Driver answers `focus` natively
  and returns the shared reason constants.
- `tests/backend/tmux_spec.lua` covers the answers — the focused
  Agent, no client for the pid, a client not on an Agent window, and a missing
  server — and `tests/backend/backend_spec.lua` covers the Backend's
  short-circuit and pass-through.
- This supersedes the `client_window`/composition half of
  [focus-is-its-own-read](2026-09-13-focus-is-its-own-read.md); its split into
  `inventory` and a separate Focus read, its reference-spelling decision, and
  its "Focus is a term" decision stand.
