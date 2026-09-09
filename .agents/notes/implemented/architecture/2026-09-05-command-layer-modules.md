# Agent Note: command layer split into commands/ dispatch + per-concern modules

Status: implemented

## Problem

`lua/vantage/commands.lua` held every subcommand's logic in one ~470-line file:
Agent lifecycle (create, switch, kill), Prompt, Annotation, and the dispatch
itself. The concerns were unrelated except that all hung off the single
`:Vantage` user command, so the file grew past any one concern and made each
flow harder to find.

## Decision

The command layer is a directory mirroring the repo's existing
`init.lua`-plus-per-concern pattern (`picker/`, `backend/`):

- `commands/init.lua` is the dispatch only: `run` maps a subcommand name to one
  function call, `complete` answers completion, and the few one-line commands
  (`toggle`, `detach`, `status`) live here as thin local functions. No complex
  logic sits in `run`.
- `commands/attach.lua` owns `toggle`/`switch` and their shared
  Agent/Tool selection, Group choice, and creation handoff;
  `commands/kill.lua` owns the kill flow.
- `commands/prompt.lua` owns the `prompt` terminal action (`run` +
  `send_prompt`).
- `commands/review.lua` owns `:Vantage review` and its sub-actions
  (`run(action, line1, line2)` + list/clear/add); the note editor itself lives
  in `frontend/note.lua`.
- `commands/actions.lua` owns terminal action tokens and
  `commands/terminal_keys.lua` installs `cli.win.keys`.

Prompt and Review are **peers**: the `{reviews}` placeholder is a prompt that
reads Review data (a "uses" dependency), not a "Review is a kind of Prompt"
subordination. `review.run` owns the remaining sub-dispatch (list/clear/add);
`switch` / `kill` take no arguments.

`config.lua` is unchanged: `require("vantage.commands")` now resolves
`commands/init.lua` instead of `commands.lua`.

## Alternatives considered

### Why not one file per subcommand?

Seven subcommands would produce several ~10-line files plus a shared creation
flow that both switch and toggle need, forcing a `create.lua` anyway. Three
domain modules match the domain's own seams and the repo's directory pattern.

### Why not nest annotation under prompt (`commands/prompt/annotation.lua`)?

The domain glossary already defines Prompt and Annotation as independent terms;
the dependency is `prompt → annotation` (via `{annotations}`), a "uses"
relationship, not subordination. Nesting would encode a domain change in the
file tree and require re-terming the glossary. If `:Vantage prompt` ever gains
sub-actions, `prompt.lua` can be promoted to `prompt/init.lua` then — the same
move as this one.

### Why a thin if-chain over a handler table?

Each branch is already a single function call; a table needs wrapper closures
for `annotate` (which needs `line1`/`line2`) and the no-arg commands, adding
noise for no readability gain.

## Consequences

- `lua/vantage/commands.lua` is deleted; `commands/` now holds dispatch,
  `attach`, `actions`, `terminal_keys`, `prompt`, `review`, and
  `kill`. The composition root registers `run`/`complete`.
- The stale `commands.lua` paths in older Agent Notes and `AGENTS.md` are
  updated to their new module; the `prompt_wizard` name is gone (`prompt.run`).
- The dispatch is a flat name→function map; adding a subcommand is one branch
  in `init.lua` plus one module.
