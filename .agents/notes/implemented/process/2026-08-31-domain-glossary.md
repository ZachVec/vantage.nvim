# Agent Note: Domain glossary (docs/glossary.md) — one home per term, with _Avoid lists

Status: implemented

## Problem

The domain terms (Group, Anchor, Agent, View, Backend, Driver, Frontend, Client, Picker, Tool) carry precise meanings, and near-synonyms (workspace, session, status, terminal) keep creeping into prose and would blur the model.

## Decision

`docs/glossary.md` is the authoritative glossary: each term has one definition and an `_Avoid:` list naming the near-synonyms to reject. Code, docs, and Agent Notes use the terms exactly; adding or renaming a term happens only there. The system narrative (how the terms map onto tmux and relate) lives in `docs/architecture.md`.

## Alternatives considered

### Why not define terms inline where used?

Definitions would drift and duplicate; a single home makes the model checkable and cross-linkable.

### Why not a heavier doc (an ADR per term)?

Overkill for a small plugin; one glossary file is the right granularity.

## Consequences

- Reviewing prose for `_Avoid:` words becomes a mechanical check against docs/glossary.md.
- The glossary is documentation, not code: it can lag unless it is kept in sync in the same change that alters the model.

The vocabulary it defines is exercised by [the Group/Anchor/Agent/View note](../architecture/2026-08-31-group-anchor-agent-view.md).
