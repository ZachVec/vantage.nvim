# Agent Note: Picker implementations as pure renderers over a selection spec

Status: implemented

## Problem

The three picker implementations (`native`, `fzf-lua`, `snacks`) each built
their own items, reached into the Backend to produce previews, duplicated the
empty-list policy, and (snacks) reached into the Terminal to decide terminal
mode restoration. Domain assembly lived inside renderers, so the Picker seam
mixed presentation with domain logic — the same coupling the Backend seam
exists to avoid.

## Decision

Picker implementations are pure renderers over a flow-owned `PickSpec`. The
command flow builds items and calls `Picker.pick(spec, opts)`; the
`vantage.frontend.picker` facade owns implementation resolution, capability
negotiation, and command validation. `Picker.get()` is internal.

A picker declares exactly three capabilities:

- `preview` — it can render an entry's `preview`.
- `command` — it can bind the flow's picker commands.
- `multi` — it can confirm several entries at once.

`PickSpec` carries only the picker's inputs: `prompt` and `items_provider`.
`PickOpts` carries `on_choice` and optional `commands`. A command is a
keymap-shaped descriptor `{ lhs, rhs, desc? }`; `rhs(ctx)` receives the
neutral `{ item, items }` context and returns `true` when the item list may
have changed. Commands are globally bound; a renderer without `command` drops
them, and the flow conformance spec enforces well-formed descriptors and
unique `lhs` values. Group scoping is an ordinary command owned by the flow,
not a Picker field.

The empty-list policy stays single-sourced: `Picker.pick` returns `boolean
empty`; the caller emits its flow-specific warning. Preview content is
computed by the entry's own `preview` (see
[picker entries are data](2026-09-13-picker-entries-are-data.md)), so
renderers never reach into the Backend.

## Alternatives considered

### Why not keep the pickers self-building their items?

That keeps domain assembly inside renderers and triplicates the empty-list
policy — the exact coupling this change removes.

### Why not keep semantic `pick_agent`/`pick_kill`/`pick_review` methods?

The current result channel already delivers the chosen entry through
`on_choice(item)`, so the methods had converged. Their only differences are
the `preview`/`command` capabilities and the flow-provided commands. One
facade removes the need to edit every renderer when a flow is added.

### Why not keep `spec.group` as a special Picker field?

Group scoping is a flow-owned filter toggled by a key. Treating it as a
Picker concept made the interface grow with flow semantics; it is now an
ordinary `commands` entry.

### Why not a blocking "return the chosen item" interface?

All three engines are callback-only (`vim.ui.select`, `fzf_exec`, snacks
`confirm`); a synchronous return would require coroutine-blocking every call
site. The callback result channel keeps each engine's native async shape.

## Consequences

- The picker implementations no longer `require` any Vantage module — only
  their engine. `commands/attach.lua`, `commands/kill.lua`, and
  `commands/review.lua` assemble their own entries and call `Picker.pick`.
- `frontend/entries.lua` owns the entry vocabulary (the Agent text and the
  pane preview included); `frontend/review.lua` owns Review rendering.
- The snacks terminal-mode handling applies to every snacks pick: the
  preview-capable path hands the terminal back from its own close, and
  `pick_naive` from its wrapped `on_choice`, preserving the terminal-window
  re-entry described in
  [snacks-new-group-terminal-mode](../bug-fix/2026-09-05-snacks-new-group-terminal-mode.md)
  and [the-terminal-owns-its-mode](../bug-fix/2026-09-25-the-terminal-owns-its-mode.md).
- The capability set above is this note's; the commands contract and the
  facade's failure semantics are current as of
  [composition-root-and-neutral-seams](2026-09-10-composition-root-and-neutral-seams.md).

The method, spec, and capability shapes above are superseded by
[picker-two-interfaces](2026-09-18-picker-two-interfaces.md): implementations
are still pure renderers over a flow-owned spec, but a pick now carries a
streaming item source plus the flow's `many` and `preview` requests, and the
only declared capability is `command`.
