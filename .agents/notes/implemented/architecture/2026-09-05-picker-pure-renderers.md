# Agent Note: Picker implementations as pure renderers over a selection spec

Status: implemented

## Problem

The three picker implementations (`native`, `fzf-lua`, `snacks`) each required
`vantage.picker.items` to build their own items, reached into the Backend
(`capture_pane`) and the Annotation domain (`render_item`) to produce previews,
triplicated the empty-list warning, and (snacks) reached into the Client to
decide terminal-mode restoration. Domain assembly lived inside renderers, so
the Picker seam mixed presentation with domain logic — the same coupling the
Backend seam exists to avoid — and the empty-list policy was repeated per
engine.

## Decision

The Picker implementations become **pure renderers** that depend on nothing but
their engine. A frontend orchestrator, `lua/vantage/select.lua`, builds the
items and assembles a `vantage.PickSpec` per flow; the picker only renders it.

The picker interface:

- `pick_agent(spec, on_choice)`, `pick_kill(spec, on_choice)`,
  `pick_annotation(spec, on_choice)` each return `boolean empty` — true when
  the list was empty and nothing was shown. `pick_plain` is unchanged.
- A `PickSpec` carries the picker's **inputs** only: `items_provider`
  (`fun(): table[]`), `preview` (`fun(item): string[]?`, nil = nothing to
  preview), `prompt`, `invoked_from_terminal` (an invoke-time fact), and
  `on_delete` (an in-flight action). The chosen value is delivered through the
  positional `on_choice` — the picker's single result channel — so the split is
  *result* (positional) versus *how to run the pick* (spec).

Consequences of that boundary:

- Item construction (`agent_items`, `kill_items`, `annotation_items`), the
  focused-Agent pin, ordering, `format_agent`, and `focused_cwd` moved out of
  `picker/` into `select.lua`; `picker/items.lua` is deleted.
- Preview **content** is computed by the orchestrator and injected as the
  `preview` thunk (`capture_pane` for panes, `render_item` for annotations).
  The "pane previews go through the Backend" invariant still holds — the call
  just moved from the picker into the orchestrator, both Frontend. Preview
  **presentation** (how fzf/snacks/native show it) stays in the picker.
- The empty-list policy is single-sourced: the picker detects empty (its
  synchronous `empty` return) and the caller warns with the flow-specific
  message. The builders normalized to "always return a list, never warn, never
  nil".
- `on_choice` and `on_delete` receive the **domain value** (target /
  annotation / choice), extracted by the picker, so each method's result is
  what its name promises rather than the raw rendered item.
- Deleting the last item auto-closes the picker: snacks calls `picker:close()`,
  fzf-lua calls `utils.fzf_exit()`, both after re-reading `items_provider`
  through a cached-items pattern (one re-read per delete, verified against each
  engine's source).
- The snacks terminal-mode restore applies to every snacks pick — the
  preview-capable picks via `on_close`, `pick_plain` via a wrapped `on_choice`
  (its `select` shim owns `on_close`) — keyed on `invoked_from_terminal`.

## Alternatives considered

### Why not keep the pickers self-building their items?

Keeping `picker/items.lua` and the per-engine `Items.*` calls is the
least-change option, but it keeps domain assembly inside the renderers and
triplicates the empty-list policy — the exact coupling this change removes.

### Why not pass the whole rendered item through `on_choice`?

Delivering the raw item would make the three methods identical and collapse
them into a generic `pick(spec, on_choice)`. Delivering the domain value keeps
the methods' result types distinct (`target` / `annotation` / `choice`) and
their names meaningful.

### Why not keep the empty warn in each engine?

That is the `agent-picker-order` note's "empty is the engines' problem"
decision, reversed here: a generic boolean return plus a caller-side warn is
single-sourced and deletes three copies of the same message.

### Why not a blocking "return the chosen item" interface?

All three engines are callback-only (`vim.ui.select`, `fzf_exec`, snacks
`confirm`); a synchronous return would require coroutine-blocking every call
site (resume-in-schedule, manual error re-raise) and an asymmetric delete
side-channel. The callback result channel keeps each engine's native async
shape.

## Consequences

- The picker implementations no longer `require` any Vantage module — only
  their engine (`vim.ui.select`, `fzf-lua`, `snacks`). `select.lua` is the new
  frontend orchestrator.
- This supersedes the "why not a generic `select(items, opts, on_choice)`
  primitive" rationale in the
  [pluggable-picker note](2026-08-31-pluggable-picker-frontend.md): the preview
  contract is now one engine-neutral `fun(item): string[]?` (fzf joins lines,
  snacks sets lines, native has none), so the "one preview contract across
  pickers" objection no longer holds.
- `docs/architecture.md` and the Picker glossary term now say the Picker
  *renders* every selection rather than *owning* its construction; the
  plain-select flows (`pick_plain`, wizard assembly in `commands.lua`) are
  unchanged.
