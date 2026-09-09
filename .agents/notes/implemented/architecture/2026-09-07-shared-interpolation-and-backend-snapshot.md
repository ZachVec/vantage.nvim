# Agent Note: Shared interpolation and backend snapshot

Status: implemented

## Problem

Prompt and Review each had their own `{placeholder}` interpolation loop, the
tmux Driver discarded stderr on nonzero exits, and picker flows issued
separate inventory queries for agents and groups. The seams were correct, but
the duplicate mechanics made behavior drift easy.

## Decision

- `vantage.util.interpolate()` is the single placeholder implementation used
  by Prompt and Review. Each domain keeps its own vocabulary.
- The Driver returns structured errors through the result contract:
  mutating verbs return `true` or `false, err`, `create` returns `Agent` or
  `nil, err`, and queries return data or `nil, err`.
- `backend/driver/tmux.lua` reads the Agent inventory and focused Agent in one
  chained tmux process through `snapshot(pid)`.
- The Picker facade's `pick(spec, opts)` renders the neutral row protocol and
  owns command/capability negotiation; renderers share their own engine
  plumbing without knowing flow semantics.

## Alternatives considered

### Why not merge Prompt and Review vocabularies?

The shared piece is interpolation mechanics. The vocabularies are different
domain surfaces and stay with their owners.

### Why not keep separate `list()` and `groups()` reads?

The picker needs both from the same live inventory; two synchronous tmux
queries can also observe different states. One snapshot is both cheaper and
more coherent.

### Why not make the Driver seam implicit again?

The formal `vantage.Driver` contract and conformance test make result shapes
and required verbs explicit without promising a second driver implementation
before one exists.

## Consequences

- Template interpolation and nil-failure behavior cannot drift between Prompt
  and Review.
- tmux failures carry stderr to the caller; the Driver does not notify.
- The kill and Agent pickers use one inventory read per refresh.
- The current seam details are owned by
  [composition-root-and-neutral-seams](2026-09-10-composition-root-and-neutral-seams.md).
