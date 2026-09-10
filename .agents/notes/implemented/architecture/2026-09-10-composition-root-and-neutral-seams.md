# Agent Note: Composition root, fail-fast seams, and neutral picker commands

Status: implemented

## Problem

The layered refactor left several boundaries softer than the architecture
claimed. `config.lua` still applied configuration, installed Prompt/Review
state, and registered `:Vantage`; `health.lua` loaded the command layer for
Prompt vocabulary and both `backend/driver/init.lua` and `picker/init.lua`
re-resolved their implementation on every call, warning and falling back on bad
configuration. The shared `vantage.Agent` record exposed tmux's `@N` target and
`Util.agent_window_index()` parsed it in the frontend, while each new Picker
flow added a semantic method to every renderer. Driver failures were
inconsistent: some verbs notified inside the Driver, others silently ignored
nonzero exits, and `create` could leave a partially-marked window behind.

## Decision

**Composition and failure.** `init.lua` is the composition root. `setup()`
calls `Config.apply(opts)`, resolves Driver and Picker once, then installs
Prompt/Review hooks and `:Vantage`. `config.lua` keeps defaults, shared types,
`Config.options`, `Config.PROMPT_PLACEHOLDERS`, and `sanitize_tools`; runtime
lifecycle does not. Prompt's `WinEnter` tracking lives in `Prompt.setup()`.
Unknown or unavailable backend/picker implementations, and missing picker
dependencies, fail fast before any command/autocmd side effect. `Driver.get()`
and Picker `get()` are programming errors before setup; `health.lua` catches
them with `pcall` and reports the failure. `Config.options` remains the global
configuration singleton.

**Neutral Driver records.** `vantage.Agent` carries an opaque `id` and a
driver-neutral `seq`; tmux's `@N` is parsed only in `backend/driver/tmux.lua`.
`attach(agent)` returns the per-client attachment record; the View restoration
is owned by
[restore-per-client-views](2026-09-10-restore-per-client-views.md). The formal
`vantage.Driver` type names every verb, and a conformance test checks the surface.

**Driver results.** Mutating verbs return `true` or `false, err`; `create`
returns `Agent` or `nil, err`; queries return `data, nil` or `nil, err`. The Driver never
notifies. `create` rolls back a partially-created Agent when metadata/config
application fails and appends a rollback failure when cleanup also fails;
`send_keys` cleans its temporary buffer. `kill_agent`/`kill_group` report a
missing target as an error.

**Picker facade.** Commands call `Picker.pick(spec, opts)` or
`Picker.pick_plain(...)`; `get()` is internal. A renderer declares exactly two
capabilities: `preview` and `command`. `opts.commands` is a list of
keymap-shaped `{ lhs, rhs, desc? }` descriptors; `rhs(ctx)` receives
`{ item, items }` and returns `true` when the list may have changed. Commands
are globally bound, duplicate `lhs` values fail fast, and a renderer without
`command` drops them. `spec.group`, the `dynamic` option, and semantic
`pick_agent`/`pick_kill`/`pick_review` methods are gone; group scoping is a
flow-owned ordinary command.

**Command ownership.** `commands/attach.lua` owns `toggle`/`switch`
plus their shared Agent/Tool selection and Group creation;
`commands/actions.lua` maps terminal action tokens and installs
`cli.win.keys`.

## Alternatives considered

### Why not keep warning and falling back on bad backend/picker names?

Fallback made configuration errors hard to distinguish from a working setup,
especially once `get()` was cached. Fail-fast at `setup()` plus a health report
is clearer; the cost is that a typo stops plugin initialization instead of
silently running tmux/native.

### Why not keep `target` and add only `seq`?

That would leave a tmux-shaped field and its parser in shared/frontend code.
The opaque `id` keeps the Driver as the only place that understands the
multiplexer identity format.

### Why not keep semantic picker methods?

The renderer methods had converged on the same `on_choice(item)` result and
differed only in optional capabilities. Keeping three methods forced every new
flow to edit every renderer; one facade with explicit capabilities moves the
difference to data.

### Why not a Result table for every Driver verb?

Multi-return is idiomatic Lua and keeps query call sites unchanged. Only
mutating verbs need the `ok, err` shape; `create` naturally returns its value
or `nil, err`.

## Consequences

- `make check` now runs `scripts/verify-architecture.lua`, which rejects
  reverse module dependencies.
- `:checkhealth vantage` reports the configured picker's `preview`/`command`
  capabilities and reports an initialization failure instead of replaying
  setup.
- Invalid backend/picker configuration now raises during `setup()`; user docs
  state that there is no fallback.
- `frontend/review.lua` remains editor-local state in the Frontend; the
  Backend owns Agent lifecycle state, not every Vantage data structure.
- The stale file/API facts in older implemented notes are updated to point at
  this decision; the fallback decision in
  [backend-seam-registry](../../archived/architecture/2026-09-05-backend-seam-registry.md)
  is superseded.
