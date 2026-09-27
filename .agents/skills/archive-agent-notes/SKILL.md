---
name: archive-agent-notes
description: Archive, consolidate, reject, or delete Vantage Agent Notes whose rationale has stopped guiding future work. Use when a new Agent Note supersedes an implemented note, when asked to archive or consolidate the .agents/notes/ tree, or when auditing the tree for archive candidates.
---

# Archive Agent Notes (Vantage)

Reduce the active decision corpus without erasing history that can still guide work. This skill is the operational counterpart to the rules in `.agents/notes/README.md`; the machine gate is `make notes` (`scripts/verify-agent-notes.lua`).

## Read the contracts first

Before touching any note, read:

- `.agents/notes/README.md` — the authoritative rules: layout, lifecycle, classification, § Archiving and deletion, the consolidation rule under § When to write one, and the in-file format.
- `.agents/notes/AGENTS.md` — the supersession rule.
- `.agents/notes/implemented/AGENTS.md` and `.agents/notes/archived/AGENTS.md` — what is allowed in each tree.

Judge whether a note's rationale still owns anything from current code, docs, and inbound links. Word count and age are discovery aids, never archive criteria.

## When this fires

- **Writing a new Agent Note** triggers the supersession check (`.agents/notes/AGENTS.md`): search the active tree for older notes covering the same decision, mechanism, or rejected alternative, and archive or consolidate every qualifying implemented note in the same change. Do not defer a known match to a later audit.
- **A human asks** you to archive a specific note, or to review the whole active tree for archive candidates.

## Classify each note by future value

Inspect every note in scope, and do not archive toward a quota. Apply one principle to analogous groups and use best judgment for close cases.

- **implemented — keep active:** its rationale, alternatives, ownership boundary, negative guarantee, durable semantics, or reintroduction condition is likely to guide a future change. Length does not matter.
- **implemented — archive:** the shipped decision is complete and its body is unlikely to guide future work — one-off UI chrome, a narrow adapter, a minor closed bug, or superseded implementation detail.
- **implemented — consolidate and delete:** the note is *fully* superseded and a current owner already exists; see [Consolidate a fully superseded note](#consolidate-a-fully-superseded-note).
- **proposed — never archive:** keep a live proposal active; reject it if it is no longer worth pursuing.
- **rejected — keep only as a guardrail:** retain a rejection only while the losing proposal remains a tempting, meaningful mistake and the note explains why it loses.
- **rejected — delete:** delete the whole note when the rejected idea is obsolete, superseded, or no longer plausible.

A note that is the sole home of a still-current fact is not archivable until that fact lives in its own home — code, `docs/architecture.md`, the glossary, or the user-facing docs (see `.agents/notes/README.md` § What a note owns). A note-only fact is a signal to move the fact, not to keep the note active forever.

### Calibrated examples

These set the bar; the word counts show size is not the test.

Archive an implemented note such as:

- `2026-09-04-snacks-picker-preview-no-linenr` — a minor closed styling bug, 568 words;
- `2026-09-04-note-float-follows-user-window-options` — a one-off window-option follow-through, 723 words.

Keep an implemented note such as:

- `2026-08-31-backend-driver-seam` — foundational seam authority, 276 words;
- `2026-08-31-tmux-as-state-store` — a durable ownership boundary, 363 words.

Consolidation applies to a note deep in a supersession chain whose every unique proposition has already moved to the current owner. Confirm the owner carries the surviving rationale before deleting, and leave *partial* supersessions active and cross-linked.

## Archive one implemented note

For each qualifying implemented note, do exactly these steps and nothing else:

1. Move `implemented/{class}/yyyy-mm-dd-topic-title.md` to `archived/{class}/yyyy-mm-dd-topic-title.md` (`implemented` is deliberately absent from the archive path).
2. Insert one line `Archived: YYYY-MM-DD` (today's date) immediately below `Status: implemented`. Make no other body edits — do not translate, reformat, update facts, or repair links inside the note.
3. Repair inbound links. Search active prose for relative markdown links into the note, and for each choose one of:
   - **redirect** it to current authority (the note that now owns the decision);
   - **retarget** it to the archived path (only when the historical snapshot is intentionally cited);
   - **delete** it.
   Never verify or repair links out of the archived note: they are frozen
   as-sealed against the path the note had while active, so links into
   `implemented/` stop resolving once the note is archived. That rot is
   accepted (see `.agents/notes/archived/AGENTS.md`).
4. Run `make notes` and confirm it passes; it enforces the archive metadata (`Status: implemented` + `Archived: YYYY-MM-DD`).

## Consolidate a fully superseded note

When a note is *fully* superseded and a current owner exists, fold it into that owner and delete it — the consolidation rule in `.agents/notes/README.md` § When to write one. Deletion is the one path that removes an implemented note from the corpus entirely, so the rule is strict:

1. Identify the current owner from shipped code, config, docs, and newer notes; dates and titles are discovery hints, not proof.
2. Confirm the supersession is **full**: every unique rationale, alternative, consequence, required verification, and named coverage gap already lives in the owner. Any surviving behavior, current contract, on-disk format, or compatibility obligation makes it partial — keep the note active and cross-linked instead.
3. Move every unique proposition into the owner. An inventory that only describes deleted implementation mechanics is not one of those decision facts.
4. Repair every inbound link to point at the owner, then delete the note.
5. Search exact filenames, symbols, config keys, and command names afterward to be sure nothing still cites the deleted note.

A feature-addition note may be consolidated into its removal note only when the feature is absent from production code, config, on-disk formats, migration, and compatibility behavior; no current doc presents it as available; and no test exercises it as supported. Removal rationale and tests that verify absence may remain; the removal owner preserves the original motivation, why it no longer justified the feature, alternatives to removal, the capability given up, reintroduction conditions, and verification of absence. Removing one transport, default, implementation, or presentation is partial supersession.

## Audit the whole active tree

When a human asks you to reduce the tree rather than to archive one note:

1. List the active corpus by lifecycle and class.
2. Read each note and classify it by future value (keep / archive / consolidate-and-delete / reject / delete for rejected).
3. Apply the calibration above, using word count only to order the reading, never as the test.
4. Group supersession chains and confirm each full supersession against its owner before deleting; keep partial supersessions active and cross-linked.
5. Carry out the qualifying changes, then run `make check`.

## Reject a proposed note

Move `proposed/{class}/yyyy-mm-dd-topic-title.md` to `rejected/{class}/yyyy-mm-dd-topic-title.md`, set line 3 to `Status: rejected — <why, in one line>`, and freeze the proposal-time sections. The verdict lives on the Status line.

## Delete a rejected note

Delete a rejected note when it no longer prevents a plausible mistake.

## Validate and report

Run `make check`. Report what you archived, what you consolidated and deleted, what you rejected, what you deleted, and what you kept and why; name every genuinely borderline case with its word count and chosen outcome.
