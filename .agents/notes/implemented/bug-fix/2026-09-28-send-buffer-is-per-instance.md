# Agent Note: The tmux staging buffer is per Neovim instance

Status: implemented

## Problem

Every Neovim instance staged paste text into the one buffer name
`vantage-send` on the shared tmux server. Interleaved sends corrupt each
other: A stages, B overwrites with its own text, A pastes B's text and reports
success, and B then finds no buffer to paste. The fixed name also meant the
success path's explicit `delete-buffer` could fail because another instance
had already consumed or replaced the buffer, reporting a paste that succeeded
as a failure — and a user told their send failed will send it again.

## Decision

The staging buffer is named `vantage-send-<nvim-pid>`, where the pid is
`vim.fn.getpid()` — this Neovim process, not an Agent or tmux pid. The send
sequence is:

1. `set-buffer -b <name> -- <text>`; a failure returns a staging error and
   stops.
2. `paste-buffer -d -p -t <agent.id> -b <name>`; `-p` keeps bracketed paste, no
   Enter is sent.
3. A successful paste consumed the buffer via `-d`, so there is no separate
   success-path delete.
4. A failed paste runs `delete-buffer -b <name>` and then returns the original
   paste error, appending a cleanup failure when the delete also fails. Only
   this instance's buffer is touched.

The current chain is synchronous (`set-buffer` → `exec` → `paste-buffer`, each
`vim.system(...):wait()`), so no sequence number, queue, or lock is added; a
pid-scoped name is enough for two instances, and one instance's sends cannot
interleave.

## Alternatives considered

### Why not a monotonic sequence in the name?

A sequence guards a single instance against its own re-entry, and the send
chain has none: the call blocks until tmux returns. When the send path becomes
asynchronous, a sequence (or a queue) will be the question to revisit; today it
would be state that can never differ.

### Why not a per-send unique name with no cleanup?

That trades buffer reuse for garbage accumulation on the shared server, and
the buffer name would carry no meaning to a debugging user.

### Why not delete after the paste on success, as before?

`-d` already consumes it, and the extra delete is what turned a successful
paste into a reported failure when anything else had touched the buffer.

## Consequences

- The buffer name is private to the tmux Driver; no Backend parameter, Agent
  field, or user option carries it.
- A failed paste is still a reported failure, now with the paste's own error,
  and this instance's buffer is cleaned up so the next send stages fresh text.
- `docs/gotchas.md`'s bracketed-paste entry states the staging buffer is
  per-instance and that `-d` consumes it.

## Verification

Measured against a real tmux server on a throwaway socket: `paste-buffer -d`
consumes the buffer when the paste succeeds and leaves it in place when the
paste fails (a missing target). `tests/backend/tmux_spec.lua` pins the pid
name, that another instance's buffer survives a send, and that a failed paste
cleans up this instance's buffer.
