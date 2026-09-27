# Agent Note: A note holds the why; current facts live in their own home

Status: implemented

## Problem

The active corpus grows by one note per non-trivial change, and the only ways to
shrink it are archiving (freeze the note) and consolidation (fold it into its
owner and delete it). Both assume a note can leave the active tree without
stranding authority. But a note's `## Decision` is often the *only* written home
of a current fact — the exact surface a change shipped, a default, a contract —
so archiving it would drop a fact that is still true, and the note stays active
instead. The repo already splits *what* from *why* for user-facing docs (root
`AGENTS.md`: "User-facing docs say what, not why") and for glossary terms ("one
home per domain term"), but the note side was unstated: nothing said a note must
not be the sole home of a current fact, which is exactly what lets a note be
archived later.

## Decision

`.agents/notes/README.md` gains a § What a note owns: an Agent Note holds the
*why* — the motivation a decision answered, the alternatives it beat, the
trade-offs it accepted. The *what* a decision shipped — current behavior,
defaults, contracts, vocabulary, commands — lives in its own home: shipped code,
[`docs/architecture.md`](../../../docs/architecture.md), the
[glossary](../../../docs/glossary.md), or the user-facing docs. A note may
restate a current fact and is kept current with it, but it must not be the only
home of one; a fact that survives nowhere else pins the note in the active tree.
When a fact lives only in a note, it moves to its home first.

The boundary is stated from the developer-docs side in `docs/architecture.md`, is
a standing order in root `AGENTS.md`, and the
[`archive-agent-notes`](../../../skills/archive-agent-notes/SKILL.md) skill now
treats a note that is the sole home of a still-current fact as not archivable
until the fact is rehomed.

## Alternatives considered

### Why not let the note be the authoritative record of shipped behavior?

Rejected because a note that is the only home of a current fact can never be
archived without losing authority, so it pins itself in the active corpus — the
growth this rule exists to stop. deepseek-harness reaches the same place with a
documentation tier table: architecture, subsystems, and package READMEs own the
*what*, and the note keeps the *why*.

### Why not a gate that rejects a note-only fact?

No mechanical test can tell whether a fact also lives elsewhere in prose; it is
a judgment the writer makes against the code and docs. The rule states the
standard, and the archive skill applies it during classification.

### Why not leave the split implicit?

Rejected because it was already implied for user-facing docs and glossary terms
but missing for notes, so agents kept recording current behavior only in the note
and archival rarely fired.

## Consequences

- Notes become archivable more often, because a current fact no longer depends
  on the note staying active.
- A note that becomes the only home of a fact is a signal to move the fact to its
  home, not to expand the note.
- The rule is judgment-based; no gate catches a note-only fact, so it depends on
  the writer and on the archive skill's classification pass.
- The bootstrap note's "implemented notes are kept current with what actually
  shipped" still holds; this rule adds that the note is not the *only* home of
  that reality.
