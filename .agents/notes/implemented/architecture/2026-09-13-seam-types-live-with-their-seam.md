# Agent Note: Seam types live with their seam

Status: implemented

## Problem

Every `vantage.*` LuaLS type lived in `config.lua`, including contracts whose
implementation lived elsewhere. `vantage.Driver`'s verb list sat in a different
file from the `REQUIRED` list that validates it (`backend/init.lua`), and
the eight picker types — `PickSpec`, `PickerImpl`, `PickerCapabilities`,
`PickOpts`, `PickMultiOpts`, `PlainSelectOpts`, `PickerCommand`, and
`PickerCommandCtx` — sat away from the facade that enforces them. Reading one
seam's contract meant opening two files, and `AGENTS.md` stated a one-tier rule:
"shared types live in `config.lua`".

## Decision

A seam's contract types live with the seam, and `AGENTS.md` now says so:

- `vantage.Driver`, `vantage.Attachment`, and `vantage.Agent` live in
  `backend/init.lua`, next to the registry and the `REQUIRED` list: the
  Driver emits those records, so its file carries their shape.
- The picker contract — `vantage.PickSpec`, `vantage.PickerCommand`,
  `vantage.PickerCommandCtx`, `vantage.PickOpts`, `vantage.PickMultiOpts`,
  `vantage.PlainSelectOpts`, `vantage.PickerCapabilities`, `vantage.PickerImpl`
  — lives in `frontend/picker/init.lua`, the facade that validates capabilities
  and commands.
- `config.lua` keeps the option types (`vantage.Config`, `vantage.Tool`,
  `vantage.Win`, `vantage.ReviewConfig`, `vantage.ReviewFloatConfig`,
  `vantage.GatherConfig`) and `vantage.ReferenceFormat`.

`---@class` needs no `require` — LuaLS resolves the annotation across the
workspace — so no module gained a runtime dependency, and
`scripts/verify-architecture.lua` needed no change: it files an unclassified
path under `shared`.

## Alternatives considered

### Why not a dedicated types module?

A types-only file is a new kind of file here — nothing requires it — and the
dependency verifier would file it under `shared` by default. It would also have
to own contracts with no single layer: `vantage.Agent` is read by the Backend,
the tmux Driver, `frontend/entries.lua`, and three flows. The file would be a
drawer, not a home.

### Why not keep everything in `config.lua`?

That reads well only until a seam's contract is split, which it already was: the
Driver's type was 40 lines from the list that must agree with it. Co-locating
the pair makes the duplication visible in one file instead of two.

### Why not move the domain types out too?

`vantage.Agent` has no single owning layer, and `vantage.ReferenceFormat` types
`vantage.Tool.format`, a config field. Scattering both turns "where is this type
defined" into a search.

### Why not make one generated source for the Driver verb list?

That is the contract-duplication candidate from the 2026-09-13 architecture
review, and a different decision: this change removes the two-file read of a
contract, not the copies of the verb list.

## Consequences

- `backend/init.lua` and `frontend/picker/init.lua` read as complete
  contracts: the shape, and the thing that enforces it.
- `config.lua` holds the option table, its validation, and the reference
  spelling.
- The Driver's verb list still appears in `backend/init.lua` (the type, the
  `REQUIRED` list, and the surface's forwards) and the conformance test — but
  the pair that must agree now sits in one file.
