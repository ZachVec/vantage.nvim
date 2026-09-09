# Agent Note: Surface tmux stderr on Driver failures

Status: implemented

## Problem

The tmux Driver's helpers returned `""` or `{}` on any nonzero exit, discarding
stderr. Callers could not tell an invalid session name, a missing window, or a
command failure from a successful empty result.

## Decision

`backend/driver/tmux.lua` routes commands through an internal
`exec_result()` returning `{ code, stdout, stderr }`. `fail_message(prefix,
result)` appends trimmed stderr when tmux supplied it.

The Driver exposes that detail through the explicit result contract:
mutating verbs return `true` or `false, err`; `create` returns `Agent` or
`nil, err`; queries return data or `nil, err`. The Driver itself never
notifies; command flows decide whether to show the error.

## Alternatives considered

### Why not warn inside the Driver?

The Backend would then own UI policy and duplicate notifications across call
sites. Returning the error keeps the Driver pure and lets each flow choose its
message and continuation.

### Why not expose only exit codes?

Exit codes alone cannot distinguish tmux's reasons. Stderr is already captured
by `exec_result`; including it in the returned error costs no extra process.

## Consequences

- `create`, `retarget`, `send_keys`, `capture_pane`, `kill_agent`,
  `kill_group`, and `status` report the tmux reason through their result.
- Expected no-server reads are treated as empty state, not failures.
- Error rendering is single-sourced in command flows.
