# Agent Note: The Terminal action vocabulary lives with the dispatch

Status: implemented

## Problem

`commands/` has a shape: `init.lua` is the command layer's own module — the
`:Vantage` dispatch and its one-line commands — and every other file is a flow
hanging off it. `commands/actions.lua` was neither. It held the token table for
`cli.win.keys` plus `resolve`: a 40-line vocabulary with one consumer, sitting
in a directory whose shape said "dispatch plus flows".
[command-layer-modules](2026-09-05-command-layer-modules.md) split the layer
that way and carried the tokens along as a module of their own; the split's
reason was unrelated flows crowding one 470-line file, which a table of tokens
is not.

## Decision

`commands/init.lua` owns the Terminal action tokens (`hide`, `switch`,
`prompt`, `files`, `buffers`) and `resolve(rhs)` alongside the subcommand
dispatch, so `commands/` is `init.lua` plus flows. `commands/actions.lua` is
deleted, and the composition root requires `vantage.commands`, installing
`Commands.resolve` into the Terminal at setup
([terminal-installs-its-keymaps](2026-09-20-terminal-installs-its-keymaps.md)
owns how the Terminal uses it).

The tokens keep loading on use what nothing else needs: `prompt` and gather are
required inside their table entries, while `hide` and `switch` call the
Terminal and attach modules the dispatch already requires.

## Alternatives considered

### Why not keep `commands/actions.lua` as its own module?

Then `commands/` holds three kinds of file, not two, and the odd one out exists
only to hold a table with a single consumer. A module boundary is for a seam;
nothing varies across this one, and the composition root is its only caller.

### Why not move the vocabulary into the Terminal?

A token names a command — `switch` runs the attach flow, `prompt` runs the
prompt flow — and the Frontend may not import the command layer. The
architecture gate rejects it, and the Terminal would have to be handed the
meanings anyway.

### Why not keep the vocabulary in the composition root that installs `resolve`?

The root is where the two layers are wired, not where either layer's vocabulary
lives. `cli.win.keys` tokens are command-layer knowledge, so the root hands
`resolve` to the Terminal rather than owning it.

## Consequences

- `commands/` is `init.lua` plus flows; `commands/init.lua` exports `run`,
  `complete`, and `resolve`.
- `tests/commands/actions_spec.lua` becomes
  `tests/commands/init_spec.lua`, pinning `resolve` through `vantage.commands`.
- The dispatch and its flows (attach, kill, review) load with
  `require("vantage")` rather than on the first `:Vantage`, because the
  composition root needs `resolve` at setup.
- Facts updated in place:
  [command-layer-modules](2026-09-05-command-layer-modules.md),
  [converge-command-surface-to-terminal-actions](../simplification/2026-09-06-converge-command-surface-to-terminal-actions.md),
  [composition-root-and-neutral-seams](2026-09-10-composition-root-and-neutral-seams.md),
  and
  [terminal-installs-its-keymaps](2026-09-20-terminal-installs-its-keymaps.md).
