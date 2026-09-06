# Agent Note: Shared interpolation, backend snapshot, and snacks renderer

Status: implemented

## Problem

Three adjacent parts of the codebase repeated the same low-level logic:

- `prompt.lua` and `annotation.lua` each implemented their own `{placeholder}`
  interpolation loop, including the "unknown placeholder stays literal" and
  "resolver returned nil" rules.
- `backend/tmux.lua` discarded stderr on every nonzero tmux exit, so callers
  could not distinguish failure causes.
- `select.lua` called `Backend.list()` and then `Backend.groups()`, which
  called `list()` a second time; the kill picker therefore paid for two
  inventories.
- `picker/snacks.lua` duplicated the dynamic-list, scope, refresh, terminal
  restore, and action-key wiring across `pick_agent`, `pick_kill`, and
  `pick_annotation`.

The existing seams stayed correct, but these duplicates made small changes to
template semantics or picker behavior easy to apply in only one path.

## Decision

Add shared abstractions without changing public command, Backend, or Picker
contracts:

- `vantage.util` owns `interpolate(template, allowed, resolve)`, the single
  implementation used by both Prompt and Annotation. Prompt and Annotation
  keep their own vocabularies (`PLACEHOLDERS`, `FIELDS`), preserving the
  existing ownership decision.
- `vantage.util` also owns `agent_window_index(target)`, the one place that
  parses `@N` window ids. The Backend's `list()` sort and the Frontend's
  `agent_order` tie-break both use it.
- `backend/tmux.lua` gains an internal `exec_result()` structured result
  (`code`, `stdout`, `stderr`) under the existing `exec`/`exec_out`/
  `exec_lines` helpers, and a public `snapshot()` that returns `agents` and
  derived `groups` from one `list()` read. `groups()` is implemented on top of
  the same `groups_from_agents()` helper.
- `select.kill_items()` consumes `Backend.snapshot()` instead of issuing
  `list()` + `groups()`.
- `picker/snacks.lua` gets an internal `render(spec, opts)` helper. The three
  public methods remain `pick_agent`, `pick_kill`, and `pick_annotation`, each
  now a small wrapper that supplies its result extractor, delete action, and
  optional scope action.

The public `PickSpec`, `on_choice` result channels, and empty-list boolean
return are unchanged. This is presentation-only refactoring inside the
existing Picker seam.

## Alternatives considered

### Why not merge Prompt and Annotation vocabularies into one module?

That would reverse the existing `prompt.lua` ownership decision. The shared
piece is only the interpolation mechanism; the vocabularies are different
domain surfaces and stay in their owners.

### Why not collapse the three picker methods into one public `pick(spec, on_choice)`?

The `picker-pure-renderers` note rejected that because the methods return
distinct domain values (`target`, `annotation`, `choice`). The snacks
refactor keeps those methods and only shares engine plumbing.

### Why not add a backend `snapshot()` to the future-driver seam as a formal requirement?

The Backend seam is still implicit, so `snapshot()` is a tmux-driver method
for now. Formalizing the Backend interface is a separate, larger change and
should not be smuggled into this deduplication.

## Consequences

- Template interpolation semantics have one implementation; unknown
  placeholders and nil-failure behavior cannot drift between Prompt and
  Annotation.
- tmux failures now have a structured result available internally, so a later
  error-reporting change can include stderr without reworking call sites.
- The kill picker performs one tmux inventory read instead of two.
- The snacks picker's three flows share refresh/scope/delete/key-wiring logic,
  while its public interface and `PickSpec` remain the same.
- `@N` parsing and malformed-target degradation are single-sourced.
