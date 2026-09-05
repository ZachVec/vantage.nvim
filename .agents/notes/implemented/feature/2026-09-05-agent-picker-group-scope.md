# Agent Note: Agent picker group scope — default-on, `<C-g>`-toggled

Status: implemented

## Problem

The Agent picker lists every Agent across every Group, and the common flow —
act within the Group the client is currently in — is drowned in other Groups'
rows. The plugin already knows the focused Agent (`Client.last_agent`) and the
pickers already refresh in place (`<c-x>` delete), but nothing scoped the list,
so even a handful of foreign Agents stood between the user and its own.

## Decision

The Agent list opens scoped to the focused Agent's Group by default on
fzf-lua and snacks, and `<C-g>` toggles the scope in place (snacks binds it in
the input and list panes, normal + insert; fzf-lua binds ctrl-g with
`reload = true`) — the picker stays open in both cases.

- Mechanism: `PickSpec` gains one optional field, `scope? fun(items):
  table[]` — a live transform the picker applies to freshly read items while
  its scope toggle is on (the default whenever `scope` exists). The picker
  keeps per-pick toggle state; every re-read — the initial open, a `<c-x>`
  delete, the toggle itself — routes the raw items through the transform.
  No `scope` means no toggle key and no filtering, so `pick_kill`,
  `pick_annotation`, and `native` are untouched.
- `select.agent_spec` wires `scope = agent_scope`, which re-reads
  `Client.last_agent_alive()` on every invocation: the focused Group's Agent
  rows stay, Tool rows always stay (they are creation actions, not Group
  members), and with no focused Agent — including one that dies while the
  picker is open — the whole list shows. No stale scope.
- The anchor is the live focused Agent, not the pinned row: the pin only
  appears when the picker is invoked from the terminal window, while the
  scope applies whenever a focused Agent exists — the literal reading of
  "the current focused Agent's Group".
- `native` (`vim.ui.select`) has no keymaps: it keeps showing the whole list,
  exactly as before; `:Vantage kill` and `:Vantage switch @N` continue to
  cover the cross-Group paths for every engine.
- No config option and no additional indicator: the default is on, the list
  content is the state (only the focused Group's rows plus Tool rows), and
  the behavior is documented.

## Alternatives considered

### Why not derive the scope Group from the pinned `(focused)` row?

The pin is UI data gated on `invoked_from_terminal`; the scope is a domain
fact (`last_agent_alive`). Anchoring on the domain fact keeps the scope when
the picker is opened from a plain window with a live client, and makes the
"focused Agent died" degradation automatic rather than a second special case
on the pin.

### Why not a config option for the default (or remember the toggle)?

The requested behavior is default-on; the per-pick toggle already gives the
user the one thing a knob would (show everything when wanted), and remembering
state across opens adds an implicit setting with no user-visible benefit. A
config surface is cheap to add later, and none is needed to read the current
behavior.

### Why not filter in `select.lua` (swap providers or re-open the picker)?

`items_provider` is stateless and the toggle needs mutable per-pick state; the
`<c-x>` delete already keeps mutable cached items in the renderer
(picker-pure-renderers note), so the scope continues that pattern as a
view-state transform over the same items. The alternative would either
duplicate providers or re-open the picker on every flip — flicker, lost query,
lost position.

### Why not scope `native` too?

`vim.ui.select` cannot bind a toggle, so defaulting native to scoped would
permanently hide other Groups' Agents for that engine with no way back. The
scope feature deliberately keys on engine support: `agent_spec` always ships
the transform, and only the pickers that can toggle apply it.

## Consequences

- In the Agent picker only, snacks' default `<c-g>` keys — `toggle_live` in
  the input pane, `print_path` in the list — are shadowed by our scope toggle
  (user keys win under snacks' merge); neither action is meaningful for
  Vantage's pick. fzf-lua binds ctrl-g in the Agent list only; the kill and
  annotation lists get neither key.
- `PickSpec` gained a field; the
  [picker-pure-renderers note](../architecture/2026-09-05-picker-pure-renderers.md)
  now enumerates it. `on_choice`, the `<c-x>` kill contract, and the row
  exclusions of the
  [agent-picker-cx-kill note](2026-09-05-agent-picker-cx-kill.md) are
  unchanged — the scope only hides rows, and a kill re-reads through it.
- README.md, doc/vantage.nvim.txt, and docs/architecture.md document the
  scope behavior and the `<C-g>` toggle.
- Empty-list semantics are unchanged: with scope on, the scoped list can be
  empty only when `items_provider` itself returned none; the initial
  empty-warn and the close-on-empty after a kill behave as before.
- No glossary change: `Group` and `Agent` terms are already canonical.
