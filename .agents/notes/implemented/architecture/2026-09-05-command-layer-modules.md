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
- `commands/agent.lua` owns the Agent domain — `switch`, `kill`, and the
  create/pick flow (`find_agent`, `do_create`, `ask_new_group_name`,
  `create_with_tool`, `pick_or_new`). `pick_or_new` is exported because
  toggle's open path reuses it.
- `commands/prompt.lua` owns `:Vantage prompt` (`run` + `send_prompt`).
- `commands/annotation.lua` owns `:Vantage annotate` and its sub-actions
  (`run(action, line1, line2)` + `jump_to_annotation`, `note_style`,
  `annotate_list`, `annotate_add`, `annotate_clear`); the note editor itself
  lives in `ui/note.lua`.

Prompt and Annotation are **peers**, matching the domain modules `prompt.lua`
and `annotation.lua`: the `{annotations}` placeholder is a prompt that reads
annotation data (a "uses" dependency), not an "annotation is a kind of prompt"
subordination. Sub-dispatch stays in each module (`agent.switch` / `agent.kill`
own their arg-vs-interactive branch; `annotation.run` owns list/clear/add), so
`init.lua` never parses an argument.

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

- `lua/vantage/commands.lua` is deleted;
  `commands/{init,agent,prompt,annotation}.lua` take its place. `config.lua`
  still calls `run`/`complete` unchanged.
- The stale `commands.lua` paths in older Agent Notes and `AGENTS.md` are
  updated to their new module; the `prompt_wizard` name is gone (`prompt.run`).
- The dispatch is a flat name→function map; adding a subcommand is one branch
  in `init.lua` plus one module.
