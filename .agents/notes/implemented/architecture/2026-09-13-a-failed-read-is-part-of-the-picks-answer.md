# Agent Note: A failed read is part of the pick's answer

Status: implemented

## Problem

`PickSpec.items_provider` could answer with a list and nothing else, so "the
Agent inventory could not be read" had nowhere to go. `commands/attach.lua`
and `commands/kill.lua` each threaded a mutable `state` table into their spec,
wrote `state.error = err` from inside the provider, and read it back after
`Picker.pick` returned. The trick worked only because the opening read is
synchronous — every implementation reads the list before it opens a picker —
so the write had already happened by the time the flow looked. Nothing in
`vantage.PickSpec` said the provider could fail, `attach`'s
`vantage.AgentPickerState` grew an `error` field to hold a fact that was not
state, and the next flow would have invented a third channel.

## Decision

`items_provider` answers `entries, err`: always a list — empty when the read
failed — with the reason as its second value. `Picker.pick` and
`Picker.pick_multi` answer `empty, err`: `empty` says that no pick opened (the
list held nothing, or the opening read failed) and `err` carries that read's
reason. The facade forwards both, `commands/attach.lua` and
`commands/kill.lua` warn the reason when there is one and keep their own
message — "no agents and no tools configured (cli.tools)", "nothing to kill" —
for a genuinely empty list.

Only the read that decides whether a pick opens carries its reason back. A
re-read triggered by a Picker command (`fzf-lua`'s `reload`, `snacks`'
`refresh`) keeps its current answer: an empty list, which closes the picker.
The reason travels as a plain return value because that read is synchronous in
all three implementations (`native.lua`, `fzf_lua.lua`, and `snacks.lua` each
read before opening); the choice itself stays asynchronous, and no callback
was added for it.

## Alternatives considered

### Why not have the facade wrap `items_provider` and capture the reason?

The wrapping version keeps `vantage.PickerImpl.pick`'s signature and puts the
handling in one place, but the reason is produced by the implementation's own
opening read. A wrapper then needs a "remember the first call and ignore the
rest" rule, which the implementations get for free: each has exactly one read
that decides whether to open, and its later reads already ignore a second
value. Forwarding what the read produced costs two lines per implementation
and no new rule to keep in sync.

### Why not report a re-read's failure to the user?

There is no synchronous way back to the flow: `Picker.pick` has already
returned, and the flow's one report happens then. A user-visible re-read
failure needs a close-time channel — the very `on_close` surface
[the pick-close note](../simplification/2026-09-13-pick-close-is-the-implementations.md)
removed for want of a user. An empty re-read closes the picker today and did
so before this change; if a flow ever needs to report that, adding the close
channel back is the move, and that note records the condition.

### Why not let the facade warn?

The Picker stays presentation-only: the facade carries facts and the flows
speak. The empty message is flow vocabulary ("nothing to kill" is not
something a Picker can know), so a facade warning would put user-facing text
in the seam.

### Why not a separate `on_error` callback?

It would fire at the same synchronous moment a return value is available, so
it adds a parameter every implementation and every spec must carry for a
fact the return already delivers.

## Consequences

- `commands/attach.lua` and `commands/kill.lua` no longer thread a `state`
  table for the read's reason; `vantage.AgentPickerState` has no `error`
  field, and `kill`'s spec takes no argument at all.
- A failed opening read now reaches the user as the Driver's own message
  ("no server running on …", and so on) instead of being swallowed into an
  empty list that was reported as "nothing to kill".
- Known gap, deliberately kept: a re-read that fails closes the picker with no
  message (see above).
- `docs/architecture.md` states the contract; `tests/frontend/picker_spec.lua`
  pins the facade forwarding `(empty, err)` on the single, multi, and degraded
  paths; `picker_native_spec.lua`, `picker_fzf_lua_spec.lua`, and
  `picker_snacks_spec.lua` each pin an engine answering `empty` with the read's
  reason; `tests/commands/attach_spec.lua` and `tests/commands/kill_spec.lua`
  pin the flows warning the reason instead of their empty-list message.

Superseded by [picker-two-interfaces](2026-09-18-picker-two-interfaces.md): a
pick no longer answers `empty, err`. It renders its stream and opens empty when
nothing arrives, and the flow reports a failed read from inside its own source.
The gap this note records — a read that fails after the picker opened has no
channel back to the flow — is unchanged, and so is the condition for adding a
close-time channel back.
