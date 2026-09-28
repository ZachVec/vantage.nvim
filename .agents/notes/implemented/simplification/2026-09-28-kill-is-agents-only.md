# Agent Note: kill is Agents only

Status: implemented

## Problem

`:Vantage kill` listed Agent entries followed by Group entries, and
`vantage.Driver` carried a `kill_group` verb that destroyed a Group's Anchor
and Views. A Group is a container derived from its Agents — the list's Group
entries had no behavior a user could not reach by marking the same Group's
Agent entries — and the verb was a second bulk path through the same Driver
surface for one derived object. `Entries.group`/`GroupEntry` existed only for
that list.

## Decision

The kill list shows Agent entries only, in creation order. Marking several
kills each one through `Backend.kill_agent`. `kill_group` is gone from the
Backend surface, the `vantage.Driver` contract, the tmux driver, and the
Entries vocabulary. Killing a whole Group means marking its members; a Group
whose last Agent is killed ends with its Anchor, as it always did. The picker
still lists Agents for every Group, so the Group name in each entry is what the
user filters by.

## Alternatives considered

### Why not keep `kill_group`?

It is a bulk form of `kill_agent` over a container the plugin derives rather
than stores. Keeping it means a second Driver verb, a second tmux
implementation, and a list entry kind — three surfaces for one derived
operation.

### Why not add a confirmation or "kill all" command?

Kill already acts directly on the selection, and the multi-select engine can
already pick a Group's members. A confirmation step would be new policy for
one path, and a picker command would need a selection concept the list does
not have.

### Why not enumerate until the Group is empty?

Other clients can create Agents between the list read and the kills; the
operation's object is the selected Agents, so it kills them and leaves
whatever else exists. Re-reading until empty would report success for a
condition it cannot guarantee.

## Consequences

- `kill.lua` maps entries straight to `kill_agent`; invalid entries (the
  pinned Focus, Tool entries) are not in this list.
- The Backend surface, the Driver contract and its conformance list, the tmux
  `kill_group` implementation and the `group_sessions` helper it used, and
  `Entries.group`/`GroupEntry` are deleted; `tests/commands/kill_spec.lua`,
  `tests/backend/backend_spec.lua`, and `tests/backend/tmux_spec.lua` no
  longer reference the verb.
- The usage text, README, and `doc/vantage.nvim.txt` say the list kills
  Agents (mark several to kill them together).
