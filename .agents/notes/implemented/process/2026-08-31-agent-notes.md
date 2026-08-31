# Agent Note: Agent Notes — durable proposals and decision records

Status: implemented

## Problem

Vantage had no durable record of *why* the code is shaped the way it is. Rationale lived only in git history and PR discussion: a future maintainer could not tell why the Backend/Frontend/Driver split exists, why a default was chosen, or what alternatives a decision beat, and a settled trade-off could be re-litigated by accident.

## Decision

Adopt a lightweight Agent Note system modeled on deepseek-harness, adapted to this Lua/Neovim plugin. Each non-trivial change must add or update a note under `.agents/notes/{lifecycle}/{class}/yyyy-mm-dd-topic.md`, where lifecycle is `proposed` / `implemented` / `rejected` and class is one of the closed set in `scripts/verify-agent-notes.lua`. A machine-checked in-file format (header block, `## Problem` opener, lifecycle-specific sections, mandatory `## Alternatives considered`) is enforced by `make notes`, wired through `make check`.

The adaptation drops three deepseek-harness mechanics this repo does not need:

- **Single-language notes** — no `.zh.md` counterparts and no i18n sidecars; Vantage is English-only.
- **No cryptographic archive manifest** — the `archived/{class}/` tree is frozen by convention plus an `Archived: YYYY-MM-DD` metadata gate, not a hash-sealed manifest with an append-only write flow.
- **Pure-Lua verification** — the gate is `scripts/verify-agent-notes.lua`, run via `nvim --headless -u NONE -l` (Neovim is already a hard requirement), not a TypeScript/pnpm toolchain.

## Alternatives considered

### Why not copy deepseek-harness verbatim?

That system assumes a TypeScript/pnpm monorepo, bilingual documentation, and a hash-sealed frozen archive. Vantage is a single-language Lua plugin with no JS toolchain; importing the verbatim system would add a build dependency and a bilingual contract the repo does not want, while the sealing machinery buys little at this scale.

### Why not keep rationale in git history and PR discussion only?

History is append-only and not browsable by decision; it cannot be searched for "what did we give up here". Notes make the trade-off a first-class, mechanically checkable artifact.

### Why not a centralized `INDEX.md`?

The lifecycle/class tree is already browsable and searchable; an index adds a maintenance burden and inevitably drifts from the tree it indexes.

## Consequences

- Every non-trivial change now owes an Agent Note in the same change; `make check` fails a change whose note is malformed or missing its required sections.
- The active corpus stays small through archiving; archived notes are frozen and never treated as current authority.
- Two new repository artifacts: `scripts/verify-agent-notes.lua` and a `Makefile` entrypoint. This note is the first implemented record and doubles as the format exemplar.
