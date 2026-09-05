# Agent Note: The new-Group cmdline swallows snacks' terminal-mode re-entry

Status: implemented

## Problem

`:Vantage switch` from the vantage terminal, choosing a Tool row and then
`+ new group` in the Group pick (with existing Groups; no-Groups skips the
pick), left the client terminal in terminal-normal mode (`nt`) after the
Agent was created — typing did nothing until the user pressed `i`. Switch's
tail is `Client.retarget`, which only re-points the existing terminal and
never touches the mode, so the flow depends entirely on the snacks picker's
terminal-mode re-entry after its pickers close. The same creation through
`:Vantage toggle` was unaffected (`Client.focus` ends in `show`'s
`startinsert`).

The re-entry is a single tick check (`restore_terminal_mode`: scheduled for
the tick after the picker closes, `startinsert` when the mode is `nt`).
`pick_plain` (the Group step) wraps its `on_choice` for the re-entry; the
wrapper ran the choice handler **before** queueing the check. The new-Group
handler (`ask_new_group_name` in `commands/agent.lua`) schedules the Group
name prompt — a `vim.fn.input()` cmdline — from inside that handler, so the
check ran while the cmdline was open: the scheduler keeps running across the
cmdline, the check saw mode `c` (cmdline), skipped `startinsert`, and once
the prompt closed the terminal was back in `nt` with nothing pending. The
existing-Group path was fine (its handler completes synchronously, so the
check runs later with the terminal still in `nt`); the no-Groups path was
fine too (the Agent picker's `on_close` re-entry is queued at close, before
the prompt is even scheduled). Reproduced and verified on nvim 0.12.3 with a
real-UI simulation of the exact queue order.

## Decision

`pick_plain`'s wrapped `on_choice` in `lua/vantage/picker/snacks.lua` queues
`restore_terminal_mode()` **before** running the choice handler. The check
then runs while the terminal is still in `nt` — the picker's `close()` has
already returned focus synchronously — and issues `startinsert`; that pending
insert survives the open cmdline and lands when it closes, so the terminal
ends in terminal mode (`t`) for the new-Group path. The ordering now matches
the preview-capable picks' `on_close` re-entry, which has always been queued
before any choice-handler work, and the no-Groups path, which has relied on
the same pending-insert-across-cmdline semantics since the picker re-entry
landed.

Scope is confined to snacks' plain wrapper: `pick_agent`/`pick_kill`/
`pick_annotation` keep their `on_close` handler, fzf-lua and native are
untouched (only the snacks backend shows the defect — the other engines leave
the terminal in terminal mode across their own closes), and `:Vantage
prompt`'s plain pick changes ordering only (its handler sends keys to tmux
and is mode-neutral).

## Alternatives considered

### Why not restore after the cmdline at the command layer?

`ask_new_group_name`'s callback could re-enter terminal mode once the prompt
closes (`invoked_from_terminal` + `startinsert` when `nt`). Deterministic,
but the re-entry is the snacks backend's compensation for its own close
semantics; putting a copy in `commands/agent.lua` would cross the Picker seam
for one engine's defect, and the shared helper it would need is exactly the
kind of engine knowledge the seam exists to keep out of the command layer.

### Why not re-check while the cmdline is open (poll)?

`restore_terminal_mode` could reschedule itself while the mode is `c` and
retry on the next tick. It fixes the same paths, but a per-tick reschedule is
hot while the prompt is open (the unthrottled form ran on the order of 5·10⁵
checks across a ~2.5 s prompt in the simulation) and puts a polling pattern
in place for a one-tick transient; the queued-first `startinsert` needs no
re-check at all.

### Why not change the prompt itself (no `input()` cmdline)?

Replacing the cmdline name prompt with another mechanism (a buffer, a
ui.input-driven flow) for the same net semantics is a larger change to the
shared creation flow and would not make the restore ordering any simpler;
the cmdline path is what works everywhere else.

## Consequences

- `pick_plain`'s wrapper queues the re-entry before its choice handler; the
  comment in `picker/snacks.lua` and the snacks section of `docs/gotchas.md`
  document the cmdline-scheduling fact (the scheduler runs across `input()`'s
  cmdline, whose `c` mode would swallow a queued-after check) and the
  queued-first `startinsert` semantics.
- The [Agent-picker order note](../feature/2026-09-04-agent-picker-order.md)
  and the [picker-pure-renderers note](../architecture/2026-09-05-picker-pure-renderers.md)
  were updated in place with the ordering fact; no API or user-visible
  behavior changed, and no other engine or command path was touched.
- A Tool-row creation through `:Vantage switch` with a new Group now ends
  with the terminal in terminal mode, matching the existing-Group and
  no-Groups paths.

## Verification

Real-UI simulation (nvim 0.12.3 under tmux, driveable because terminal-mode
entry needs a UI — headless cannot enter `t`): the wrapper's queue order was
the only variable. Current order: the new-Group path ended `nt` (defect);
queued-first order: new-Group, existing-Group, no-Groups, Esc-cancel, and the
prompt-flow variants all ended `t`, including the intermediate
`input returned … mode=nt` plus deferred `startinsert` landing on close.
