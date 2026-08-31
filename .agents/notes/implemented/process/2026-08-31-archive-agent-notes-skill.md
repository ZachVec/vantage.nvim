# Agent Note: archive-agent-notes skill

Status: implemented

## Problem

The archive/reject/delete procedure existed only as prose — `.agents/notes/README.md` § Archiving and the supersession rule in `.agents/notes/AGENTS.md` — with no reusable instruction an agent could load to actually carry out an archival change. deepseek-harness ships a `dsh-archive-agent-notes` skill for exactly this job; Vantage had the rules but not the operational skill, so archiving depended on an agent re-deriving the steps from scattered prose each time.

## Decision

Add a `.agents/skills/archive-agent-notes/SKILL.md` skill mirroring deepseek-harness's `dsh-archive-agent-notes`, adapted to Vantage's single-language, no-manifest, pure-Lua reality. The skill encodes: read the contracts, the supersession check, classify by future value (keep / archive / reject / delete), the exact archive steps (move → insert `Archived: YYYY-MM-DD` → repair inbound links by redirect / retarget / delete), and validation via `make notes` / `make check`. The supersession rule in `.agents/notes/AGENTS.md` now names the skill; the trigger is unchanged — every new Agent Note archives or consolidates superseded implemented notes in the same change. No gate change: `scripts/verify-agent-notes.lua` already enforces the archive metadata the skill produces.

## Alternatives considered

### Why not a deterministic script (e.g. `scripts/archive-note.lua` + `make archive`)?

The mechanical parts — move, metadata insert, relative-link repoint — are scriptable, but the two judgment calls the whole change hinges on (which note is superseded; whether an inbound link redirects, retargets, or deletes) are not. A script would still need an agent to make those decisions, and `make notes` already re-verifies the mechanical result, so the script would add a second executor without removing the judgment.

### Why not copy deepseek-harness verbatim (SHA-256 manifest + TypeScript verifier)?

The [bootstrap Agent Note](2026-08-31-agent-notes.md) deliberately dropped the cryptographic archive manifest and the TypeScript toolchain: Vantage is single-language and pure-Lua, and at this scale a hash-sealed manifest "buys little". Copying it verbatim would reverse two recorded decisions and introduce a JS build dependency for no current benefit. This skill borrows only the procedure, which is the part that transfers.

## Consequences

- Agents now have a single loadable procedure for archive / reject / delete, instead of re-deriving steps from scattered prose.
- The supersession rule names the skill, so the "same change" archival step is discoverable and consistently applied.
- No gate or build change: `make notes` continues to enforce archive metadata; `make check` still passes.
- The bootstrap note's three deviations (single-language, no manifest, pure-Lua verification) remain intact; this note layers a skill on top of them rather than reversing them.
