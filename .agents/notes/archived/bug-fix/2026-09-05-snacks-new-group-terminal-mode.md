# Agent Note: The new-Group cmdline swallows snacks' terminal-mode re-entry

Status: implemented

Archived: 2026-09-28

## Problem

The `switch` key from the vantage terminal, choosing a Tool entry and then
`+ new group` in the Group pick (with existing Groups; no-Groups skips the
pick), left the client terminal in terminal-normal mode (`nt`) after the
Agent was created — typing did nothing until the user pressed `i`. Switch's
tail is the Attachment's `retarget(agent)`, which only re-points the existing
terminal and never touches the mode, so the flow depends entirely on the snacks picker's
terminal-mode re-entry after its pickers close. The same creation through
`:Vantage show` was unaffected (`Terminal.show` ends in
`startinsert`).

For the plain select path the re-entry lives in the wrapper `pick_naive` puts
around its choice callback, because that call hands the implementation no close
hook of its own. The wrapper originally ran the choice handler **before**
queueing the re-entry check. The new-Group handler (`ask_group` in
`commands/attach.lua`) schedules the Group name prompt — a `vim.fn.input()`
cmdline — from inside that handler, so the check ran while the cmdline was
open: the scheduler keeps running across the cmdline, the check saw mode `c`
(cmdline), skipped `startinsert`, and once the prompt closed the terminal was
back in `nt` with nothing pending. The existing-Group path was fine (its
handler completes synchronously, so the check ran later with the terminal
still in `nt`); the no-Groups path was fine too (the Agent picker's close had
already entered the terminal). Reproduced and verified on nvim 0.12.3 with a
real-UI simulation of the exact queue order.

## Decision

`pick_naive`'s wrapped `on_choice` in `lua/vantage/frontend/picker/snacks.lua`
issues `vim.cmd("startinsert")` **before** running the choice handler. The
wrapper runs inside snacks' own post-close callback — the plain select path's
one deferral point — so the picker has already closed and returned focus by the
time it runs, and the insert is pending while the handler runs; that pending
insert survives the open cmdline and lands when it closes, so the terminal
ends in terminal mode (`t`) for the new-Group path. The ordering matches the
Terminal's window-entry rule on the preview-capable path
([the Terminal-owns-its-mode note](2026-09-25-the-terminal-owns-its-mode.md)),
and the no-Groups path, which has relied on the same
pending-insert-across-cmdline semantics since the picker re-entry landed.

The insert is issued only when the pick opened from the Terminal, and there is
no mode check left in it: the Terminal owns its mode, so there is nothing an
open cmdline can swallow. Scope is confined to snacks' plain wrapper — fzf-lua
and `native` are untouched (only the snacks backend shows the defect; the other
engines leave the terminal in terminal mode across their own closes), and
`:Vantage prompt`'s plain pick issues the same pending insert (its handler
sends keys to tmux and is mode-neutral).

## Alternatives considered

### Why not restore after the cmdline at the command layer?

`ask_new_group_name`'s callback could re-enter terminal mode once the prompt
closes (detected terminal window + `startinsert` when `nt`). Deterministic,
but the re-entry is the snacks backend's compensation for its own close
semantics; putting a copy in `commands/attach.lua` would cross the Picker seam
for one engine's defect, and the shared helper it would need is exactly the
kind of engine knowledge the seam exists to keep out of the command layer.

### Why not re-check while the cmdline is open (poll)?

A scheduled check could reschedule itself while the mode is `c` and retry on
the next tick. It fixes the same paths, but a per-tick reschedule is hot while
the prompt is open (the unthrottled form ran on the order of 5·10⁵ checks
across a ~2.5 s prompt in the simulation) and puts a polling pattern in place
for a one-tick transient; the insert issued first needs no re-check at all.

### Why not change the prompt itself (no `input()` cmdline)?

Replacing the cmdline name prompt with another mechanism (a buffer, a
ui.input-driven flow) for the same net semantics is a larger change to the
shared creation flow and would not make the restore ordering any simpler;
the cmdline path is what works everywhere else.

## Consequences

- `pick_naive`'s wrapper issues the re-entry before its choice handler; the
  comment in `frontend/picker/snacks.lua` and the snacks section of
  `docs/gotchas.md` document the cmdline-scheduling fact (the scheduler runs
  across `input()`'s cmdline, whose `c` mode would swallow an insert issued
  after the handler) and the pending-insert semantics.
- The [Agent-picker order note](../feature/2026-09-04-agent-picker-order.md)
  and the [picker-pure-renderers note](../architecture/2026-09-05-picker-pure-renderers.md)
  were updated in place with the ordering fact; no API or user-visible
  behavior changed, and no other engine or command path was touched.
- A Tool-entry creation through the `switch` key with a new Group now ends
  with the terminal in terminal mode, matching the existing-Group and
  no-Groups paths.

## Verification

Real-UI simulation (nvim 0.12.3 under tmux: the suite itself runs
`nvim --headless -l`, which cannot enter `t` — a headless run driven with `-c`
can, see the
[Terminal-owns-its-mode note](2026-09-25-the-terminal-owns-its-mode.md)): the
wrapper's order was the only variable. Handler-first order: the new-Group path
ended `nt` (defect); insert-first order: new-Group, existing-Group, no-Groups,
Esc-cancel, and the prompt-flow variants all ended `t`, including the
intermediate `input returned … mode=nt` plus the pending `startinsert` landing
on close.
