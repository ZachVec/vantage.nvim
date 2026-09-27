# Agent Note: A notification raised in a callback reaches the main loop

Status: implemented

## Problem

The `files` chain's failure warning is raised from `Util.run_lines`' exit
callback — a libuv callback, so a fast event context. `Util.warn` reached the
default `vim.notify` handler, whose `nvim_echo` may not be called there, and
raised `E5560: nvim_echo must not be called in a fast event context`. The raise
also unwound the callback, skipping the `done()` on the next line, so the source
never ended: with the default `native` picker the drain loop in `pick_fancy`
waited forever (Neovim froze), and `fzf-lua`/`snacks` never received end of
input. The same warning reached synchronously (no lister installed at all) was
fine, which is why the defect only appeared once the chain was exhausted and
its last installed lister failed.

## Decision

`Util.notify` is main-loop-only: outside a fast event context it calls
`vim.notify` as before, and inside one it hands the call to `vim.schedule`.
`Util.warn` and every other caller inherit that, so a notification raised from
a callback is delivered and — more importantly — the statement after the
`warn` still runs. Deferring is the documented contract for a fast context; the
message itself is preserved, not dropped.

## Alternatives considered

### Why not schedule at the gather call site?

The raise is a property of `vim.notify`, not of the file chain: any `Util.warn`
reached from a libuv callback — an attach or kill `vim.system` exit callback, a
driver read — has the same defect, and the gather warning is not the one that
needs the special case. Fixing the shared helper closes the class of bug once
and leaves the already-safe, synchronous callers untouched.

### Why not wrap or reimplement `vim.notify` in Vantage?

`vim.notify` is a user-replaceable global, often already wrapped by
nvim-notify or noice; a Vantage-side wrapper would sit between the user's
handler and Vantage's call and change what those plugins observe. Scheduling
keeps the user's handler in charge and only moves when it is called.

### Why not drop the warning in a fast context?

The message is the only signal that the chain ran every lister and all of them
failed; losing it would make that failure silent, which is worse than the
deferral.

## Consequences

- A lister that fails after the chain is exhausted ends the run with a warning
  instead of freezing the editor: `commands/gather.lua`'s `try` no longer
  depends on `warn` not raising to reach `done()`.
- `tests/util_spec.lua` pins the helper: a timer callback raises `Util.warn`,
  and the test asserts nothing is delivered while the callback is on the stack
  and the message arrives afterwards. `tests/commands/gather_spec.lua` pins the
  chain end-to-end with a `vim.notify` that raises E5560 in a fast context.
- `docs/gotchas.md` records the E5560 rule and that the raise unwinds the
  callback it was raised from.
