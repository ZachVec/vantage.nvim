---
name: archive-agent-notes
description: Archive, reject, or delete Vantage Agent Notes whose rationale has stopped guiding future work. Use when a new Agent Note supersedes an implemented note, or when asked to archive or consolidate the .agents/notes/ tree.
---

# Archive Agent Notes (Vantage)

Archive, reject, or delete Agent Notes whose rationale no longer guides future work. This skill is the operational counterpart to the rules in `.agents/notes/README.md`; the machine gate is `make notes` (`scripts/verify-agent-notes.lua`).

## Read the contracts first

Before touching any note, read:

- `.agents/notes/README.md` — the authoritative rules: layout, lifecycle, classification, § Archiving, the in-file format.
- `.agents/notes/AGENTS.md` — the supersession rule.
- `.agents/notes/implemented/AGENTS.md` and `.agents/notes/archived/AGENTS.md` — what is allowed in each tree.

Judge whether a note's rationale still owns anything from the code, docs, and inbound links — never from a note's age or length.

## When this fires

- Every new Agent Note triggers a supersession check (`.agents/notes/AGENTS.md`): search the active tree for older notes covering the same decision or mechanism, and archive or consolidate every qualifying implemented note in the same change.
- A human may ask you to archive a specific note, or to review the tree for archive candidates.

## Classify each note by future value

- **implemented** — keep if its alternatives, ownership boundary, negative guarantee, durable semantics, or reintroduction condition still guides future work; archive if the shipped decision is complete and low future value.
- **proposed** — never archive; an obsolete proposal is rejected.
- **rejected** — keep only while it prevents a plausible mistake; otherwise delete it.

## Archive one implemented note

For each qualifying implemented note, do exactly these steps and nothing else:

1. Move `implemented/{class}/yyyy-mm-dd-topic-title.md` to `archived/{class}/yyyy-mm-dd-topic-title.md` (`implemented` is deliberately absent from the archive path).
2. Insert one line `Archived: YYYY-MM-DD` (today's date) immediately below `Status: implemented`. Make no other body edits — do not translate, reformat, update facts, or repair links inside the note.
3. Repair inbound links. Search active prose for relative markdown links into the note, and for each choose one of:
   - **redirect** it to current authority (the note that now owns the decision);
   - **retarget** it to the archived path (only when the historical snapshot is intentionally cited);
   - **delete** it.
   Never verify or repair links out of the archived note.
4. Run `make notes` and confirm it passes; it enforces the archive metadata (`Status: implemented` + `Archived: YYYY-MM-DD`).

## Reject a proposed note

Move `proposed/{class}/yyyy-mm-dd-topic-title.md` to `rejected/{class}/yyyy-mm-dd-topic-title.md`, set line 3 to `Status: rejected — <why, in one line>`, and freeze the proposal-time sections. The verdict lives on the Status line.

## Delete a rejected note

Delete a rejected note when it no longer prevents a plausible mistake.

## Validate and report

Run `make check`. Report what you archived, rejected, or deleted, what you kept and why, and any borderline case you left unresolved.
