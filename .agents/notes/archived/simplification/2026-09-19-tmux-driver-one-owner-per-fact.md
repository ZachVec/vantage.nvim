# Agent Note: One owner per tmux Driver fact

Status: implemented

Archived: 2026-09-27

## Problem

`backend/tmux.lua`'s private layer had grown several places where one
fact was spelled twice, so every change had two spots to keep in step:

- `run()`, `exec()`, and `exec_result()` were three runners for one tmux
  invocation: `run()` fused the `tmux -L <socket>` argv with the synchronous
  call (and `M.attach()` rebuilt the same prefix by hand), while `exec()` and
  `exec_result()` differed only in whether the caller got the result table or
  its code.
- A creation failure rolled back through `rollback_create()` and then joined
  the two messages inline at four call sites.
- The Agent record literal — `id`, `seq`, `group`, `cmd`, `cwd`, `tool`,
  `state`, with an empty State meaning nil — was written in `create()`,
  `agents()`, and `focus()`.
- `fail_message` was forward-declared as a local and then defined with a
  global-looking `function` statement.
- `missing_server()` accepted `table|string` only because one caller passed the
  result table while two passed a message string.
- `apply_global_config()` built its settings list as four literals plus five
  appends.

## Decision

Each fact has exactly one owner:

- `tmux_argv(...)` is the only spelling of the argv prefix — the tmux binary,
  the `-L` socket, the command — and both the synchronous path and `M.attach`
  use it.
- `exec(...)` is the only runner: it returns `{ code, stdout, stderr }` from
  `Util.run(tmux_argv(...))`, and a call site that wants only the exit code
  reads `.code`. The deleted `run()` and `exec_result()` names restated its
  invocation and its return shape, and `run()`'s `---@return` annotations
  duplicated `Util.run`'s.
- `agent_record(...)` is the only place an Agent record is spelled from raw
  multiplexer fields; `create()`, `agents()`, and `focus()` go through it, and
  the "empty State means nil" rule lives there.
- `create_error(primary, created_session, group, id)` rolls the partial Agent
  back — Anchor or window — and appends the rollback failure, replacing
  `rollback_create()` and the four inline joins.
- `fail_message` is defined as a local before `exec_lines` reads it.
- `missing_server(text)` takes a string: a stderr, or an error message that
  embeds one.
- `apply_global_config()` builds one settings table literal, with the
  `counts.sh` resource lookup hoisted above it.

## Alternatives considered

**Keep `run()`.** It had a single caller, and its body added nothing to
`Util.run` beyond the argv, which `tmux_argv` now owns; keeping it would leave
one more name whose only job is to pass through. Its annotations also
duplicated `Util.run`'s three `---@return` lines.

**Inline `socket()`, `window_seq()`, and `move_client_to_view()` too.**
`socket()` names the private-socket invariant at six call sites,
`window_seq()` is the only place tmux's `@N` format is interpreted, and
`move_client_to_view()` is a named composition (create the View, move the
client, roll the View back on failure) that keeps `retarget()` readable.
Inlining each would move its fact into every call site.

**Give the code-only path its own function (the old `exec` / `exec_result`
split).** Those six call sites — two that branch on the code and four
best-effort `kill-session` cleanups that discard it — read slightly shorter
with one word than with `.code`. But that name only restates "ignore
stdout/stderr": written as a wrapper over the runner it is a pass-through, and
written directly it re-spells the invocation. A field access at the call site
needs no extra owner.

**Keep the name `exec_result`.** It described the return value, which the
runner's single job already implies; `exec` names the action and `.code` names
the field.

**Fold `exec_lines()` into its five callers.** It owns the line splitting and
the `tmux command failed` mapping; every caller would re-spell them.

**Collapse `session_group()` and the View check into one `display` query.**
Rejected here: it changes how many multiplexer processes `retarget()` starts,
which is behavior a reviewer should weigh on its own; the internal reshaping in
this note is behavior-neutral.

## Consequences

- The same tmux commands run in the same order with the same error strings;
  `tests/backend/tmux_spec.lua` crosses only the `vantage.Driver` interface
  and the Attachment it returns, so the private reshaping is invisible to it.
- The View checks and the switch verb were later reshaped by
  [backend-one-layer-and-view-keyed-attachment](2026-09-20-backend-one-layer-and-view-keyed-attachment.md);
  this note's one-owner decisions stand.
- `tmux.lua` loses `run()` and `rollback_create()`; the substrate reads
  top-down: `socket`, `tmux_argv`, `fail_message`, `exec`, `exec_lines`,
  `missing_server`, with code-only sites reading `exec(...).code`.
- `M.health()` now prints the version from `exec("-V")`, so every tmux
  invocation goes through the shared argv; `M.status()` returns an explicit
  `nil` error instead of a variable that was nil by then.
