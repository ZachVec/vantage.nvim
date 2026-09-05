# Agent Note: The Picker owns every Vantage selection, rendered same-source

Status: implemented

## Problem

Vantage's Agent-creation wizard and `:Vantage prompt` picked through plain
`vim.ui.select`, whose implementation is decided by whatever global override
the user's environment installs (fzf-lua's `register_ui_select`, wired by the
LazyVim fzf extra, renders a terminal window). A flow then mixed renderer
families — a snacks picker closed the Agent list into clean Normal mode, and a
terminal-style float opened from that context left Neovim's term-to-term mode
transfer unsettled for its whole teardown (~40–80 ms); any terminal UI opened
in that window (the next wizard step, or the new Agent's terminal) failed to
enter terminal mode. A development-time attempt with time-based waits
(~150 ms) at two call sites appeared to patch the boundaries but kept the
renderer lottery: the defect still depended on which `vim.ui.select` override
the user ran. That attempt never entered a commit — the isolation note
records it — and this change is the design that replaced it.

## Decision

Vantage stops calling `vim.ui.select` for its own selections. Every list
choice goes through the Picker seam, and each Picker implementation renders
plain choices on its own engine — "same source" by construction, so one flow
never mixes renderer families:

- `PickerImpl` gains one generic `pick_plain(items, { prompt, format_item },
  on_choice)` mirroring the `vim.ui.select` contract (cancel calls back with
  nil). It backs the Agent-creation wizard's Tool and Group steps and
  `:Vantage prompt`.
- **snacks** implements `pick_plain` with snacks' own select (its compact
  select layout: preview hidden, non-terminal).
- **fzf-lua** implements `pick_plain` with fzf-lua's own ui_select shim.
- **native** implements `pick_plain` with the live global `vim.ui.select` —
  native is defined as "follow the environment's renderer", so its flow is
  homogeneous with that renderer by construction. The residual boundary (a
  terminal-style override plus a Normal-mode terminal trigger) is documented
  in `docs/gotchas.md`, not patched in code.
- Light two-choice confirmations (delete-annotation, clear-all) leave the
  selection path entirely and use Neovim's built-in `confirm()` dialog.
- `lua/vantage/select.lua` is deleted: the Agent-creation Group-step assembly
  and the new-Group cmdline name prompt live in `commands/agent.lua`, which
  also keeps the zero-Group behavior (no Group exists → the Group step is
  skipped and the name is prompted directly).

## Alternatives considered

### Why not keep the teardown waits (the superseded attempt)?

The waits were time-based guesses tried at two call sites during development;
they left the renderer-lottery defect alive for every future transition.
Owning the rendering removes the second renderer family from any flow, so
there is nothing left to wait for.

### Why not an internal "chosen ui.select" resolver instead of Picker methods?

A resolver still leaves ui.select-shaped calls scattered through the code and
keeps the abstraction half-global; routing through Picker methods confines
"how selections render" inside each backend, which is the isolation boundary
the resolver lacked.

### Why not keep the wizard's list steps on `vim.ui.select` (pre-#9 reversal)?

`vim.ui.select` is a renderer lottery controlled outside Vantage; the
two-step wizard is exactly where consecutive terminal windows bite. The Picker
seam already owns the other selections and each backend can render the
compact select form with its own engine.

### Why not a self-built mini picker for plain choices?

A dependency-free in-house component remains the fallback if a picker backend
ever fails to render plain choices acceptably; the Picker seam and the stock
select implementations cover every current configuration with far less code.

## Consequences

- The Agent-creation flow and `:Vantage prompt` render on the configured
  Picker's own engine: under `snacks` the whole flow is non-terminal and
  race-free in any lane; under `fzf-lua` it is homogeneous fzf; under
  `native` it is homogeneous with the environment's `vim.ui.select`.
- `vim.ui.select` remains only inside the native backend, as that engine's
  definition. Free-text prompts (new-Group name) still use `input()`.
- Confirmations use `vim.fn.confirm()` and no longer open a selection UI.
- `lua/vantage/select.lua` is gone; the Agent-creation Group-step assembly lives in `commands/agent.lua`.
- Wording across README, help, glossary, and architecture now describes the
  Picker as owning every selection.

This supersedes the
[plain-selection note](../archived/architecture/2026-09-02-plain-selection-via-ui-select.md)
(for the Tool/Group and prompt flows) and the
[isolation note](../archived/bug-fix/2026-09-03-isolate-wizard-selection-opens.md)
(which records the superseded development-time wait attempt; its analysis of
the teardown window remains the reference for the residual boundary), both
archived; the Picker seam itself is [the
pluggable-picker note](2026-08-31-pluggable-picker-frontend.md).
