# Agent Note: Consolidate a fully superseded note into its owner

Status: implemented

## Problem

The active corpus grows by one note per non-trivial change, and the
[archive-agent-notes skill](2026-08-31-archive-agent-notes-skill.md) could only
*move* a low-value implemented note into the frozen archive. That boundary keeps
the corpus tidy but never removes a note: when a later note fully replaces an
earlier one, both stay active, each carrying "superseded by" links, and every
reader pays for the dead one. The [Agent Note rules](../../README.md) named a
"fully consolidated" outcome and `implemented/AGENTS.md` pointed at "the
consolidation rule", but no such rule existed, so the reference dangled and full
supersession had no delete path.

## Decision

Adopt deepseek-harness's consolidation rule, adapted to Vantage, in
`.agents/notes/README.md` § When to write one: an implemented note that is
**fully** superseded may be folded into the current owner and deleted. Before
deletion the owner must carry every unique rationale, alternative, consequence,
required verification, and named coverage gap; every inbound link is repaired;
and the deletion happens in the same change. Partial supersession does not
qualify — keep both notes active and cross-linked, because a surviving behavior,
contract, or durable fact is still current authority. A feature-addition note
may be consolidated into its later removal note only when the feature is absent
from production code, configuration, on-disk formats, migration, and
compatibility behavior, no current documentation presents it as available, and
no test exercises it as supported; removing one transport, default,
implementation, or presentation stays partial.

The [`archive-agent-notes`](../../../skills/archive-agent-notes/SKILL.md) skill
now operationalizes it: a consolidate-and-delete classification, the strict
full-supersession procedure, a whole-tree audit mode, and the calibrated
keep/archive examples with the explicit "no quota — word count is triage" rule
taken from dsh. The dangling reference in `implemented/AGENTS.md` now points at
the rule.

## Alternatives considered

### Why not keep every superseded note and rely on archiving?

Rejected because archiving preserves history but leaves the superseded note in
the active corpus until someone separately judges it low-value; a chain of
"superseded by" notes then accumulates as authority no reader should follow.
Consolidation gives full supersession a definite delete path, which is what
deepseek-harness gained.

### Why not delete any superseded note, full or partial?

Rejected because partial supersession means a surviving behavior, contract, or
durable fact still lives only in the old note; deleting it would drop current
authority. The rule keeps partial supersessions active and deletes only when the
owner carries every unique proposition.

### Why not a mechanical script that folds and deletes?

Rejected because the decision hinges on judgment — whether the supersession is
full and whether the owner already carries each unique proposition — which a
script cannot make. `make notes` re-verifies the mechanical result, so a script
would add an executor without removing the judgment.

## Consequences

- Fully superseded implemented notes can now leave the corpus entirely, so the
  active tree can shrink rather than only relocate.
- The dangling "consolidation rule" reference in `implemented/AGENTS.md`
  resolves to the rule.
- The archive skill gains a delete path and a whole-tree audit procedure,
  calibrated with Vantage's own notes and explicitly not quota-driven.
- Deletion drops the old note's copy of rationale outside git, so the rule's
  preservation step is mandatory and partial supersessions stay undeleted.
