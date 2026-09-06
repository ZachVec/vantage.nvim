# Agent Note: Surface tmux stderr on backend failures

Status: implemented

## Problem

The tmux backend's `exec_out` and `exec_lines` helpers returned `""` or `{}` on
any nonzero exit, discarding stderr. Failure paths in `create`, `retarget`, and
`attach` therefore warned about the operation without saying why tmux refused
it, making invalid session names, missing windows, and command failures hard to
diagnose.

## Decision

`backend/tmux.lua` keeps the existing `exec`, `exec_out`, and `exec_lines`
helpers but routes them through a new internal `exec_result()` that returns
`{ code, stdout, stderr }`. A local `fail_message(prefix, result)` appends
trimmed stderr to the existing user-facing message when tmux provided one.

The three user-facing failure paths that most benefit are updated:

- `create` reports why `new-window`, `new-session`, or `display` failed;
- `retarget` reports why `select-window`, `new-session`, or `switch-client`
  failed;
- `attach` reports why its `new-session` failed.

Read-only probes that legitimately fail in normal control flow, such as
`ensure_server`'s `list-sessions`, keep using the exit-code-only path and do not
warn.

## Alternatives considered

### Why not warn on every tmux failure?

That would make expected failures noisy. The backend deliberately keeps
control-flow probes separate from user-visible operations.

### Why not return structured results from every public Backend method?

That would change the Backend seam for every caller. The goal here is only to
improve failure messages, not to make all internal tmux output public.

### Why not write tmux stderr to a log file?

It is already available in the `exec_result` value. Logging would hide the
reason from the user and add another path to explain.

## Consequences

- `create`, `retarget`, and `attach` now show tmux's reason when the operation
  fails; success paths and expected no-server probes are unchanged.
- `exec_result` remains private to the tmux driver, so the Backend seam does not
  grow.
