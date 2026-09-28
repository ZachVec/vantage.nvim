# Agent Note: The placeholder vocabulary is the resolver keys

Status: implemented

## Problem

`config.lua` held `PROMPT_PLACEHOLDERS`, a hand-kept list of the names a Prompt
template may use, because `health.lua` validates user templates against it and
the health layer may not import the command layer. Nothing tied that list to the
resolvers in `commands/prompt.lua`: a new resolver would have left the
vocabulary short, so its token rendered as a literal, and a removed resolver
would have left a name that resolves to nothing. `commands/prompt.lua` also
exported a copy (`M.PLACEHOLDERS`) that no module read.

## Decision

The prompt flow's `resolvers` table is the vocabulary: one resolver per
placeholder, and the known-name set `Util.interpolate` filters against is
derived from its keys. `Prompt.setup()` scans the applied `Config.options.prompts`
and warns about a template naming a token with no resolver.
`Config.PROMPT_PLACEHOLDERS` and `M.PLACEHOLDERS` are gone, and `health.lua` no
longer reports prompt placeholders.

## Alternatives considered

### Why not keep the vocabulary in `config.lua`?

It was a second record of one fact, kept there only so `health.lua` could read
it. Adding a placeholder meant editing two files, and nothing failed when they
disagreed — the resolver set, not the list, is what a template actually has to
match.

### Why not move the resolvers to the Frontend so `:checkhealth` keeps the check?

That keeps the diagnostic in `:checkhealth` at the cost of moving placeholder
resolution out of the flow that owns it — a larger structural change than this
problem needs. The check runs at `require("vantage").setup()`, on the same
applied config, one step earlier than `:checkhealth` would.

### Why not validate lazily, at send time?

An unknown token is a configuration mistake, knowable without a Focus or a
buffer. Setup is the earliest moment the applied config exists.

## Consequences

- Adding or removing a placeholder is one edit: the resolver. The vocabulary
  cannot name a token nothing resolves.
- Unknown placeholders are warned about once, at setup, instead of being
  reported by `:checkhealth vantage`; `Util.interpolate` still leaves them
  literal.
- `:checkhealth vantage` reports Driver health, the configured picker name, and
  dropped `cli.tools` entries only.
