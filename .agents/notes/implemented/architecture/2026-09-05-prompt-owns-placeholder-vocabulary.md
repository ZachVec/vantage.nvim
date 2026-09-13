# Agent Note: prompt.lua owns the placeholder vocabulary

Status: implemented

## Problem

The known placeholder names were duplicated: `prompt.lua` held `PLACEHOLDERS`
and `health.lua`'s `check_prompts` kept an identical `known` table to validate
user templates. Adding a placeholder meant editing both, and the two copies
could drift apart.

## Decision

`commands/prompt.lua` owns the vocabulary because it owns the resolvers: the
Prompt domain defines and consumes the placeholder names. The vocabulary is the
resolvers' own keys, and the check on user templates runs in `Prompt.setup()`
([the resolver-keys note](2026-09-13-placeholder-vocabulary-is-the-resolvers-keys.md));
`health.lua` validated against a copy while the health layer could not import
the command layer.

## Alternatives considered

### Why not a shared placeholders module?

A three-element vocabulary table does not warrant its own module; `prompt.lua`
is the natural owner because it already defines and consumes the placeholders.

## Consequences

- Adding or renaming a placeholder is a one-line change in
  `commands/prompt.lua`.
- The vocabulary cannot drift from the runtime resolvers: it *is* their keys.
