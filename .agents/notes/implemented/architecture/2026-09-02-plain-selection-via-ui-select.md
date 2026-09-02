# Agent Note: Plain selection via vim.ui.select — Tool and Group choice leaves the Picker

Status: implemented

## Problem

Agent creation (the `create_wizard`) chose the Tool and then the Group through
the pluggable Picker (`pick_tool` / `pick_group`). Both selections show only a
bare name — nothing to preview — yet the `snacks` implementation rendered a
broken default preview: `snacks.picker` falls back to its file previewer when
no `preview` is supplied, and the Tool/Group items carry no `file` field, so
the preview window showed "Item has no `file`". `fzf-lua` rendered no preview
for the same two flows, so the pickers behaved inconsistently.

## Decision

The Picker is reserved for selections with a pane preview — the Agent list
(`pick_agent`), the kill list (`pick_kill`), and the files/buffers Actions
(`pick_files` / `pick_buffers`, fzf-lua/snacks only — see the [files/buffers
note](../feature/2026-09-02-prompt-files-buffers-actions.md)). Selections with
nothing to preview — the Tool and Group choice during Agent creation, and the
`:Vantage prompt` name list — use `vim.ui.select` directly. A new
`lua/vantage/select.lua` owns the creation wizard's Tool and Group selection:
sorted `cli.tools` names, existing Groups plus a `+ new group` sentinel, and a
free-text `input()` prompt for a new Group name. The prompt glyph moves to
`Util.picker_prompt` so the Picker and `select.lua` share one source.

`picker/items.lua` sheds `tool_items` / `group_items` / `prompt_new_group`;
`PickerImpl` shrinks from four pickers to two, and the `native` / `fzf-lua` /
`snacks` implementations drop `pick_tool` / `pick_group`. This extends the
precedent `:Vantage prompt` already set (see the prompts note).

## Alternatives considered

### Why not just disable snacks' default preview and keep creation on the Picker?

It is the smallest fix, but it preserves an indirection with no payoff:
Tool/Group selection has nothing to preview, so routing it through a
preview-capable abstraction buys only a picker UI that already differs across
`native` / `fzf-lua` / `snacks`. It also leaves the "no preview → vim.ui.select"
rule expressed in one place (`:Vantage prompt`) instead of across the frontend.

### Why not a generic `select(items, opts, on_choice)` primitive inside the Picker seam?

Same rejection as the pluggable-picker note: one preview contract across
pickers with very different preview mechanisms. Here there is no preview at
all, so a plain `vim.ui.select` helper is the whole vocabulary.

## Consequences

- `PickerImpl` now exposes `pick_agent` and `pick_kill` for the preview-capable
  flows (plus `pick_files` / `pick_buffers` on fzf-lua/snacks); a new picker
  implementation adds no Tool/Group code.
- The `snacks` default-preview defect is deleted, not patched — the offending
  code path (Picker Tool/Group selection) no longer exists.
- `fzf-lua` / `snacks` users lose the fuzzy picker for the Tool/Group choice and
  get `vim.ui.select` (respecting any global `vim.ui.select` override).
- The prompt glyph moves to `Util.picker_prompt`, shared by the Picker and
  `select.lua`.

The Picker seam it narrows is [the pluggable-picker note](2026-08-31-pluggable-picker-frontend.md); the precedent it extends is [the prompts note](../feature/2026-08-31-prompts.md).
