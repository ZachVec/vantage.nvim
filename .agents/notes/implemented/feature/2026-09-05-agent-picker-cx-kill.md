# Agent Note: Agent picker `<c-x>` kill — the generic on_delete in-flight action

Status: implemented

## Problem

The Agent picker behind `:Vantage switch` (and `:Vantage toggle`'s open path)
was choice-only: picking an Agent row re-pointed the client, but killing one
meant leaving the flow for `:Vantage kill` and its separate `pick_kill` list —
a round trip for the common "drop this Agent before switching" edit. The
annotation picker already had an in-place `<c-x>` delete through
`spec.on_delete`, but pick_agent had no removal action to participate: the
contract existed only as the annotation flow's private convention, and
`agent_spec` captured `focused` once at spec-build time, so a live list
refresh could not drop a killed pinned row.

## Decision

The Agent picker supports an in-place `<c-x>` kill on fzf-lua and snacks;
native (`vim.ui.select`) has no keymaps and stays selection-only.

- The in-flight removal contract is the one generic `PickSpec.on_delete`
  field (`fun(value: any)`, already part of the type) and is now documented
  as the picker's generic `<c-x>` action: the picker calls it with the
  current row's domain value, then re-reads `items_provider`, refreshes in
  place, and closes when nothing remains. Each flow specializes what "remove
  this row" means: `annotation_spec` deletes the Annotation, `agent_spec`
  kills the Agent (`Backend.kill(agent.target)`). There is no per-flow
  removal field; a future `<c-x>`-bearing pick reuses the one slot.
- `select.agent_spec` wires `on_delete = Backend.kill(agent.target)` and
  resolves `focused` inside `items_provider` (per read, via
  `Client.last_agent_alive()`) rather than at spec-build time, so after a
  kill the refresh drops the killed Agent's row and the pin follows the live
  Agent.
- Row scope: Agent rows other than the pinned `(focused)` row, which ignores
  `<c-x>` like the Tool rows (its confirm is already a deliberate no-op).
  `:Vantage kill` remains the path for killing the focused Agent, with its
  pre-existing semantics. Tool rows (no Agent yet) also ignore `<c-x>`
  silently: there is no domain value to remove. There is no confirmation
  prompt — matching the existing kill flow and the annotation delete, and a
  mis-kill is recoverable by recreating the Agent.
- Implementation mirrors the annotation mechanics: snacks binds `<C-x>` (in
  the input pane, normal + insert, and in the list) to an `agent_kill`
  action that updates its cached `items` then `close()`s or `refresh()`es;
  fzf-lua generalizes its `pick_static` helper with an optional `alt` (c-x)
  action over mutable cached items — function contents plus `reload = true`
  plus the numeric-prefix round-trip, per the fzf-lua gotchas — and all
  three fzf-lua flows (`pick_agent`, `pick_kill`, `pick_annotation`) route
  through that one helper. The pickers still depend on nothing but their
  engine: the specialization lives in `select.lua`.

## Alternatives considered

### Why not a dedicated `on_kill` field?

The picker-side c-x contract is identical for every flow — remove the row's
domain value, refresh in place, close when empty — so a per-feature field
(`on_kill`, then `on_archive`, …) would multiply the spec for no new
mechanism. One generic removal slot plus per-flow specialization keeps the
Picker seam thin and future picks free to reuse it. The cost is that the
field's name does not name the Agent semantics (kill); the flow's
specialization does, in `select.lua`.

### Why not allow killing the pinned `(focused)` row?

The first implementation allowed it, mirroring `:Vantage kill` (whose list
shows every Agent, the focused one included) — but killing the focused Agent
from the picker surfaced two problems. Killing the last Agent of the Group
destroys the Group, and with it the Anchor and every View, so the client's
terminal exits ("exit 0"): the glossary states this — "When all of a Group's
Agents die, the Anchor and every View die with it" — so it is designed, not
a defect. And `Client.last_agent` is a pointer that goes stale the moment
its Agent dies, so prompts and `focused_cwd` silently lose the focused Agent
even when tmux auto-moves the View's window onto the next Agent. The
staleness is a pre-existing domain bug, equally reachable through
`:Vantage kill`, and fixing it (adopt the View's current window after a
kill) belongs in its own change; exempting the navigation row removes the
one-keystroke path to the worst outcome without solving that bug.

### Why not direct the user at pick_kill instead?

The kill list is a separate flow with its own intent (Enter kills, and it
also lists Groups); the Agent picker is a navigation flow, and the c-x keeps
the destructive edit inline where the correction belongs. `pick_kill` itself
gains no c-x — Enter is already its kill confirm.

### Why not close the picker after each kill?

Batch edits: several Agents can be killed in one open session, and
close-on-empty mirrors the annotation delete instead of forcing a modal per
kill. The risk is a run of mis-hits; accepted, matching the no-confirm
stance above.

## Consequences

- The Agent picker — `:Vantage switch` and `:Vantage toggle`'s open path
  both flow through `pick_or_new` — is now a killing surface for the
  non-focused rows. README.md and doc/vantage.nvim.txt document the `<c-x>`
  behavior (fzf-lua/snacks only; the pinned `(focused)` row and the Tool
  rows ignore it).
- The focused Agent can no longer be killed from the picker; `:Vantage kill`
  still lists it and can, with the pre-existing consequences: the Group dies
  with its last Agent (glossary), and `Client.last_agent` goes stale until
  the user re-points. A focus-sync follow-up — after any kill that kills the
  focused Agent, adopt the View's current window as the new focused Agent —
  remains open as its own change.
- The [picker-pure-renderers note](../architecture/2026-09-05-picker-pure-renderers.md)
  stays current: `on_delete` is still the single in-flight action field, now
  with explicit c-x semantics; the
  [annotations note](2026-09-01-annotations.md)'s "in-place `<c-x>` delete"
  remains accurate for the annotation picker.
- fzf-lua's `pick_kill` internals changed with the shared helper (function
  contents instead of a static entries array) — observable behavior
  unchanged, one re-read of `items_provider` per refresh cycle.
- No glossary change: `kill` / Agent terms are unchanged.
