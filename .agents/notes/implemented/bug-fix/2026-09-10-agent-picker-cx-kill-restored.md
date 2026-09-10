# Agent Note: Agent picker `<c-x>` kill restored under flow-owned commands

Status: implemented

## Problem

The Agent picker behind `:Vantage switch` and `:Vantage toggle` stopped
binding `<c-x>`. The layered refactor moved in-flight picker actions from
`PickSpec.on_delete` to flow-owned `opts.commands`, the attach flow registered
only `<c-g>`, and the pre-refactor kill decision was archived instead of being
carried forward. Its sibling, the
[group-scope note](../feature/2026-09-05-agent-picker-group-scope.md), stayed
active and was updated to the new contract, so only the kill lost its owner:
pressing `<c-x>` did nothing while the Review list's `<c-x>` still deleted.

## Decision

`commands/attach.lua` carries `<c-x>` as a flow-owned picker command beside
`<c-g>`: it kills the current row's Agent through `Bridge.kill_agent` and
returns true, so the picker re-reads `items_provider` in place and closes when
the list empties. Row scope is the archived decision's: the pinned
`(focused)` row — the Agent the Terminal is attached to — and Tool rows are
no-ops, and `:Vantage kill` remains the path that can kill the focused Agent.

This note owns that behavior in the active tree because the original
[kill note](../../archived/feature/2026-09-05-agent-picker-cx-kill.md) is
archived and frozen. Its mechanism moved with the refactor, but its row scope
and rationale (no focused-row kill, batch refresh, no confirmation) still
bind; the command stays a flow decision ("does the row carry an Agent, is it
the pinned one?") rather than a row method, matching the
[picker-pure-renderers boundary](../architecture/2026-09-05-picker-pure-renderers.md).

## Alternatives considered

### Why a new note instead of editing the archived one?

Archived notes are frozen by the Agent Note rules, so only an active note can
own current behavior. The archived note's negative guarantee — the pinned row
is not killable — was still load-bearing, which the regression demonstrated.

### Why not leave the kill in the refactor note's command-surface clause?

That note owns the picker-command mechanism; the kill's row scope is a
user-facing behavior with its own alternatives, and its `<c-g>` sibling has a
feature owner. A clause in the architecture note would not carry that scope.

### Why not restore `PickSpec.on_delete` or give the row a `delete()`?

`opts.commands` is the refactor's single in-flight-action contract and already
carries `<c-g>`; a second contract or a row method would split one picker
surface across two mechanisms.

## Consequences

- `fzf-lua` and `snacks` kill the selected non-focused Agent in place with
  `<c-x>`; `native` has no command surface and stays selection-only.
- `README.md` and `doc/vantage.nvim.txt` document the key;
  `docs/architecture.md` and the
  [refactor note](../architecture/2026-09-09-layered-frontend-backend-refactor.md)
  name the command.
- The kill path is the same `Bridge.kill_agent` the kill flow uses; no
  backend, config, or Driver change.

## Verification

`tests/commands/attach_spec.lua` calls the registered `<c-x>` command on a
non-focused Agent row (kills it, returns true) and on the pinned focused row
and a Tool row (no kill, returns false). `make test` runs the suite and
`make check` gates the docs and this note.
