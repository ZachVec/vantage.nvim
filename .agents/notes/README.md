# Agent Notes

One kind of design doc lives here. An **Agent Note** records a decision or proposal that affects this codebase — the *why* and *what we gave up*, the parts code and docs can't carry. This file defines where Agent Notes live, when to write one, and [the in-file format](#the-file-format).

## Layout and naming

Every Agent Note has two axes, both encoded in its **path** — `{lifecycle}/{class}/yyyy-mm-dd-topic-title.md`:

- **Lifecycle** (the top-level folder) is the Agent Note's status, and an Agent Note moves between folders as that status changes:
  - **`proposed/`** — proposals reviewed before implementation; not yet built (or only partly).
  - **`implemented/`** — the decision shipped. The file records what was decided and what was rejected, and is **kept current with what actually shipped**: when the code later moves a file, renames a module, or changes a default, the Agent Note is updated in the same change to match (facts only — paths, names, structure — not the decision itself). See [implemented/AGENTS.md](implemented/AGENTS.md).
  - **`rejected/`** — the proposal was considered and declined. Keep it only while its rationale prevents a tempting, meaningful mistake; otherwise delete it.
- **Class** (the nested folder) is the *kind* of decision — see [Classification](#classification).

The date in the filename is when the topic was **first proposed** (per git history). Cross-references between Agent Notes use relative markdown links (`[topic](../../implemented/architecture/2026-…-….md)`) — never bare prose or numbers — so they are mechanically checkable and survive moves between folders.

The active lifecycle tree is the working inventory: browse its lifecycle/class folders or search the repository. Do not add a centralized `INDEX.md`.

## Classification

Each Agent Note belongs to one path-encoded class from the closed set in `scripts/verify-agent-notes.lua`; the gate rejects other folders. Adding a class requires updating the canonical set there and this section.

| Class | What it covers |
|---|---|
| `feature` | A new user- or model-facing capability. |
| `bug-fix` | Corrects a defect or closes a gap a postmortem surfaced. |
| `simplification` | Removes code, behavior, or surface area without adding a capability. |
| `architecture` | A structural decision about the **shipped source** — how modules relate, what the runtime vocabulary is. |
| `process` | Tooling, policy, or workflow **around** the code — gates, formatting, release — not runtime behavior. |
| `testing` | Test infrastructure and strategy. |

The `architecture` / `process` line: **architecture** is about the source we ship; **process** is the surrounding tooling and workflow. (`refactor` is deliberately absent — it overlaps `simplification`, whose discriminator, "does observable behavior change?", already covers it.)

## Archiving

Archive an implemented Agent Note when the shipped decision is complete and its rationale is unlikely to guide future work. Keep it active when its alternatives, ownership boundary, negative guarantee, durable semantics, or reintroduction condition remains useful. Never archive a proposed note: reject an obsolete proposal. Keep a rejected note only while it prevents a plausible mistake; otherwise delete it.

The archive is path-encoded as `archived/{class}/yyyy-mm-dd-topic-title.md`; `implemented` is deliberately absent because only implemented notes can enter it. An archival change moves the file, retains `Status: implemented`, inserts an `Archived: YYYY-MM-DD` line immediately below that status, and repairs or deletes inbound links. These are the only permitted content changes during archival.

Once archived, a note is permanently frozen: do not edit, translate, reformat, update, move, or delete it, and do not treat it as authority for current behavior. Active prose may still link into an archived note when it intentionally cites history. `make notes` enforces the archive metadata; this repo intentionally omits the cryptographic archive manifest — the [bootstrap Agent Note](implemented/process/2026-08-31-agent-notes.md) owns that choice.

## When to write one

Every non-trivial change MUST add or update at least one Agent Note in the same change. A change is non-trivial when it alters behavior, architecture, a contract shared across files, process or tooling, testing strategy, an on-disk or configuration format, or another decision a maintainer may reasonably revisit. A proposal for substantial future work starts in `proposed/`; a decision already made starts in `implemented/`. Pick the class folder that matches the decision.

Updating the Agent Note that already owns the decision satisfies the rule; do not create a duplicate. Only a purely mechanical or local edit with no change to behavior, contracts, structure, process, or rationale is exempt. An Agent Note is never edited into a *different decision*: supersede it with a new one, and keep both notes cross-linked unless the old note is later fully consolidated. Editing an `implemented/` Agent Note to track where its existing decision lives is required, not forbidden; see [implemented/AGENTS.md](implemented/AGENTS.md).

## The file format

Every active Agent Note follows one in-file format, enforced by `make notes` (`scripts/verify-agent-notes.lua`).

### The header block

The first four lines of every Agent Note are exactly:

```markdown
# Agent Note: <title>

Status: <status>

```

The `Status:` value is one of three forms, and must agree with the lifecycle folder the file sits in — the gate cross-checks them:

- `Status: proposed`
- `Status: implemented`
- `Status: rejected — <why, in one line>`

The status carries no dates and no parentheticals: the filename holds the first-proposed date, git holds everything else. The rejection reason is the one status with content, because a rejected Agent Note's verdict is the fact readers come for.

### The body skeleton

Every Agent Note opens its body with `## Problem` — the motivation, written to stand without the solution. What follows depends on the lifecycle; recurring sections use these canonical names and nothing else, while genuinely bespoke technical sections remain free-form between the required ones.

#### `proposed/`

```markdown
## Problem
## Proposal
…bespoke sections…
## Alternatives considered
## Acceptance criteria
## Risks
```

#### `implemented/`

```markdown
## Problem
## Decision
…bespoke sections…
## Alternatives considered
## Consequences
```

`## Decision` describes shipped reality in the present tense, and the whole file is kept current with it. Proposal-era headings (`## Proposal`, `## Plan`, `## Migration plan`, `## Acceptance criteria`) may not appear in an implemented Agent Note.

#### `rejected/`

A rejected Agent Note is the proposal, frozen: it keeps whatever proposal-time sections it had, and the verdict lives on the `Status:` line. Only the header block, the `## Problem` opener, a `## Proposal` section, and the alternatives mandate below apply.

### Alternatives considered — mandatory

Every Agent Note carries an `## Alternatives considered` section: each genuine alternative and why it lost, one bold-led paragraph per alternative or a `### Why not <X>?` subsection per contested one. A decision recorded without what it beat invites re-litigation.

### Moving between lifecycles

Moving a file between lifecycle folders means updating the `Status:` line and re-satisfying that folder's skeleton in the same change — the gate fails the move otherwise. `proposed/` → `implemented/` rewrites `## Proposal` into a present-tense `## Decision` and folds `## Acceptance criteria` and `## Risks` into `## Consequences` (or a present-tense `## Testing`/`## Verification` section for what now pins the behavior). `proposed/` → `rejected/` only adds the reason to the `Status:` line and freezes the file.
