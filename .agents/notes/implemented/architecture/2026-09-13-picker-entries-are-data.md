# Agent Note: Picker entries are data

Status: implemented

## Problem

Every flow that offered a pick built its own class of selectable entries.
`commands/attach.lua` and `commands/kill.lua` each declared metatable classes
carrying `format` / `preview` plus their own verb (`select`, `delete`),
`commands/gather.lua` declared `FileItem` and `BufferItem`, and
`commands/review.lua` returned a table of closures. The interface was as wide
as the implementation: the Picker only ever needed one line of text and, for
the highlighted entry, some preview lines, yet each flow had to know the whole
protocol — and the same Agent text plus pane capture existed twice, once in the
Agent list and once in the kill list.

The coupling ran both ways. `snacks` wrote `item.text` into the flow's own entry
to satisfy its matcher and would call any field named `resolve`, so one
implementation's internals decided what an entry's fields could be called — the
hazard [Picker implementations are pure renderers](2026-09-05-picker-pure-renderers.md)
recorded as a gotcha instead of a contract. `docs/architecture.md` already said
the entries were data, which was true of the flow's intent and false of its shape.

## Decision

One seam type, `vantage.picker.Entry`, declared in
`frontend/picker/init.lua` beside the rest of the Picker contract
([seam contract types live with their seam](2026-09-13-seam-types-live-with-their-seam.md)):

- `text` — the line the implementation renders. A value, computed when the
  entry is built, because every implementation renders and matches the whole
  list.
- `kind` — the flow's own name for the entry; the flow branches on it.
- `preview` — the lazily computed preview lines. An implementation calls it
  only for the highlighted entry, so a pane capture or a 200-line file read is
  never paid per entry.
- Whatever else the flow carries. Implementations read `text` and call
  `preview`; an implementation never writes to an entry.

`frontend/entries.lua` (formerly `frontend/display.lua`) is the one vocabulary
of entries: `Entries.agent` / `tool` / `group` / `file` / `buffer` / `review`,
each returning a per-kind class declared beside it for the type checker — an
entry is a plain table with no metatable at runtime. Each builder binds the
preview for its kind, next to the text and the fields that kind carries; those
preview functions are module-level, so an entry references one shared function
instead of allocating a closure. An Agent preview goes through the Backend,
which makes `entries.lua` the first Frontend module to import the Backend — the
direction the Frontend's own definition already describes.

The flows keep what only they know: which entries to offer, what a choice means
(`kind`), and their Picker commands. `select` / `delete` are gone; `on_choice`
and a command's `rhs` read `entry.kind` and the payload the flow put there.
`commands/review.lua`'s entry moved into the shared vocabulary with the rest,
so no flow implements a preview.

The implementations follow: `native` and `fzf-lua` render `entry.text`, and
`snacks` reads `entry.text` for matching instead of writing it.

## Alternatives considered

### Why not dispatch previews through one `kind`-keyed table?

The builders already know which kind they are building, so a table keyed by
`kind` is a second place to register the same fact — and the only thing it buys
is checking a name at call time instead of binding the function one line away
from the entry it belongs to. A per-entry closure is the other extreme: same
behaviour, one allocated function per entry. Binding the module-level function
in the builder keeps the protocol at two facts (`text`, `preview`) and no
per-entry allocation.

### Why not compute previews eagerly as `preview: string[]?`?

Listing a directory would read the first 200 lines of every file, and opening
the Agent list would run one `Backend.capture` — a tmux command — per Agent.
Both are currently paid once per highlight, and `entry.preview` is what keeps
that true.

### Why not put `preview` on `PickSpec` instead of on the entry?

It splits one entry's presentation across two places — `text` on the entry,
`preview` on the pick — and it does not remove a layer: a pick mixes kinds
(the Agent list offers Agent and Tool entries), so a spec-level preview needs
the per-`kind` dispatch the entries module would then own anyway. What it adds
is the freedom to preview one kind differently per pick, which nothing wants:
the Agent's pane preview is the same fact in the Agent list and in the kill
list, and keeping it one fact is what this change is about.

### Why not keep per-flow entry classes (`KillEntry`, `GatherItem`, …)?

The deletion test: the Agent's text and pane preview are the same fact for the
Agent list and the kill list, so deleting the pair re-creates it in both. What
differs between flows is which entries are offered and what choosing one does,
and that is what stayed in the flows.

### Why not rename the Picker's `item` parameter to `entry`?

`on_choice(item)` and `PickerCommandCtx.item` are the neutral surface an
implementation hands back — the name of a thing it received, not of a Vantage
concept. Renaming them would travel through three implementations and every
spec without adding knowledge. The glossary term is `Entry`; `item` stays the
neutral parameter name.

## Consequences

- One vocabulary for every entry kind, one preview entry point, and no
  metatables: `vantage.AgentPickerEntry`, `vantage.AgentPickerAgentEntry`,
  `vantage.AgentPickerToolEntry`, `vantage.AgentSelection`,
  `vantage.KillEntry`, `vantage.KillAgentEntry`, `vantage.KillGroupEntry`,
  `vantage.GatherItem`, `vantage.GatherFileItem`, `vantage.GatherBufferItem`,
  and `frontend/display.lua` are gone.
- An implementation can no longer write to an entry, so an entry's fields no
  longer depend on which Picker is configured. The `resolve` name hazard in
  `docs/gotchas.md` remains — `snacks` still calls such a field — but the entry
  shape is now fixed in one module instead of implied by every flow.
- `tests/frontend/entries_spec.lua` pins each kind's `text`, the shared preview
  function, the pane-capture failure line, and the nil cases; the flow specs
  read fields; `tests/frontend/picker_snacks_spec.lua` pins the read-only
  contract by asserting the implementation leaves the entry alone.
- The `Entry` term now lives in the [domain glossary](../../../../docs/glossary.md),
  with `row` retired as prose.
- The Agent entry's text is unchanged and still one builder; the Picker's
  neutrality contract is unchanged
  ([pluggable-picker-frontend](2026-08-31-pluggable-picker-frontend.md)).

The preview half of this decision is superseded by
[picker-two-interfaces](2026-09-18-picker-two-interfaces.md): an Entry carries no
preview of its own, the flow hands the pick the one standard `Entries.preview`
function, and a pick that hands none has no preview pane. Everything else — one
vocabulary, plain data, no metatable, no writes from an implementation — is
unchanged.
