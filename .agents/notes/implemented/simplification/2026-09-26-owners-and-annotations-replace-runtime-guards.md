# Agent Note: Owners and annotations replace the remaining runtime guards

Status: implemented

## Problem

After [setup validation](2026-09-26-setup-validates-config-runtime-trusts-it.md)
moved user-config checks into `Config.apply`, the remaining in-repo guards
were:

- `frontend/terminal.lua` re-checked `nvim_win_is_valid` / `nvim_buf_is_valid`
  in `is_open`, `show`, `destroy`, the `WinEnter` rule, and the `TermClose`
  teardown. The window check stood in for a missing owner: a user closing the
  Terminal window with `:q` left `M.window` stale.
- `backend/init.lua` `create` looked up `opts.tool` and returned
  `unknown tool` when it missed. Its only production caller builds the name
  from the sanitized `cli.tools` table, so the branch is unreachable;
  `backend_spec` pinned it as behavior.
- `frontend/picker/init.lua` validated every flow's command descriptors on
  each pick — non-empty string `lhs`, function `rhs`, unique `lhs` — plus
  `on_choices`' type. All but uniqueness restate annotations; uniqueness is
  the one invariant no single-entry type can express, and a collision silently
  shadows one command in the renderers.

Principle 4 also forced a boundary call. `gather` filters unnamed, unlisted,
and off-disk buffers out of its candidate list, and Prompt/Review answer "no
reference" for an unnamed buffer. Are those undefined behavior to stop
backstopping?

## Decision

**The Terminal's window close gets an owner.** `Terminal.setup` installs a
`WinClosed` rule (augroup `vantage_terminal`) that clears `M.window` when that
window closes, whoever closed it. `is_open` is then `M.window ~= nil`, and
`show`, `destroy`, the `WinEnter` rule, and `TermClose`'s scheduled delete drop
their validity re-checks. The job and buffer lifecycle stays with `TermClose`,
so closing the window keeps the hidden buffer and its client alive and
`:Vantage show` reopens it. Closing the window is `hide`, not `detach`.

**`Backend.create` trusts its caller's Tool key.** `opts.tool` is a
`cli.tools` key; `Config.apply` has already dropped invalid entries, so the
lookup cannot miss. The `unknown tool` branch and the spec that pinned it are
gone, and the function's annotation states the contract.

**The Picker facade validates nothing; a flow conformance spec does.** The
facade passes `opts.commands` through, dropping them for a renderer without
the `command` capability. `tests/commands/picker_commands_spec.lua` drives
every command-bearing flow and asserts each descriptor has a non-empty string
`lhs` and a function `rhs`, and that `lhs` values are unique within one pick.
A flow that gains commands is added there.

**No-reference is domain semantics, not a stale handle.** `gather`'s buffer
filter is the candidate-list rule (an unnamed or off-disk buffer has nothing
to reference), and a Prompt's `{file}` on an unnamed buffer producing "no
reference" is the glossary's own contract. They stay. Principle 4 covers using
a handle after the object behind it has been made invalid, not a candidate
that was never referable.

## Alternatives considered

**Keep the validity checks and no owner.** The checks made `:q` harmless, but
every use site had to restate a fact the module could own once, and a new use
site would have to remember the check. The owner makes the invariant
structural: `M.window` is either nil or live.

**Have the `WinClosed` rule stop the job and destroy the buffer too.** That
makes closing the window equivalent to `:Vantage detach`, killing the
attachment the user only hid. The Terminal's contract is that its window and
its client are separable; `hide` already proved that split.

**Keep the `Backend.create` guard as a Backend-seam validation.** The Backend
is a seam between the Frontend and a Driver, not between it and the command
layer's Tool names. Its caller is in-repo and the Tool set is validated once,
so the guard only restated an annotation, the same class the
[trust note](2026-09-06-trust-non-nil-annotations.md) removed.

**Keep only the duplicate-`lhs` check in the facade.** That was the first
recommendation: uniqueness is the one invariant no annotation expresses, and
a collision silently shadows a command in both renderers. It lost because
the check is still in-repo validation at every pick; the conformance spec
gives the same guarantee in CI, where flow changes are already tested,
without a runtime branch.

**Treat unnamed / off-disk buffers as undefined behavior and delete the
filters.** That would list buffers the flow cannot spell a reference for, and
delete tested behavior (`gather` specs cover the filter) to remove a check
that is not guarding a handle.

## Consequences

- A user `:q` on the Terminal window clears the handle from the `WinClosed`
  owner; `:Vantage show` reopens the hidden buffer exactly as it did when the
  validity check noticed.
- `is_open`, `show`, `destroy`, the `WinEnter` rule, and the `TermClose`
  teardown no longer call `nvim_win_is_valid` / `nvim_buf_is_valid`;
  `TermClose` keeps its best-effort `pcall` delete and superseded-callback
  check.
- `Backend.create` with a Tool name that was never in `cli.tools` now fails
  with a nil index instead of an error string; that is a caller bug, and the
  annotation is the contract.
- A flow's duplicate `lhs` no longer fails the pick at runtime; it fails
  `make test` through the conformance spec. The facade's two descriptor/type
  specs moved there as one shape assertion.
- The principle-4 boundary is recorded: absent referents stay in the domain,
  stale handles lose their guards.
