# Agent Note: prompt.lua owns the placeholder vocabulary

Status: implemented

## Problem

The known placeholder names were duplicated: `prompt.lua` held `PLACEHOLDERS`
and `health.lua`'s `check_prompts` kept an identical `known` table to validate
user templates. Adding a placeholder meant editing both, and the two copies
could drift apart.

## Decision

`prompt.lua` exports the vocabulary as `M.PLACEHOLDERS` — the Prompt domain owns
its placeholders, and `render_line` already consulted the same table.
`health.lua` validates against `require("vantage.prompt").PLACEHOLDERS`, the
single source of truth.

## Alternatives considered

### Why not a shared placeholders module?

A five-element vocabulary table does not warrant its own module; `prompt.lua` is
the natural owner because it already defines and consumes the placeholders.

## Consequences

- Adding or renaming a placeholder is a one-line change in `prompt.lua`.
- `health.lua` can no longer drift from the runtime vocabulary.
