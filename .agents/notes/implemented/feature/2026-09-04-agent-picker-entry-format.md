# Agent Note: Agent picker entries as `[group] tool · cwd`

Status: implemented

## Problem

Agent-list rows were formatted `cmd  ~cwd  [group]` — the launch command
first, two spaces between segments, the Group hidden at the tail in square
brackets. The user-visible identity users actually pick is the Tool (the
`cli.tools` key chosen in the creation wizard) and its Group, so rows led with
the least distinctive segment, and the middle position (cwd) duplicated what
the trailing bracket already implied. The desired shape is
`[group] tool_name · agent.cwd`: Group first, Tool second, working directory
last — `[web] claude · ~/vantage`.

## Decision

`M.format_agent` in `lua/vantage/picker/items.lua` now renders every Agent row
as

```lua
("[%s] %s · %s"):format(agent.group, agent.tool or agent.cmd, Util.tilde(agent.cwd))
```

single-space separated, `[group]` leading, `·` before the cwd, `~`-folded cwd
trailing. The middle segment is `agent.tool` — the `cli.tools` key the Agent
was created with (`@agent-tool`, set only through the Tool wizard); `cmd`
serves only as a nil-safe fallback that never fires for wizard-created Agents.
`~` folding stays display-only, reusing `Util.tilde` (folds only a literal
`$HOME` prefix; an already-`~` value passes through unchanged), so creation
and the tmux driver keep storing the absolute cwd. `format_agent` is the one
shared row builder behind the Agent list and the kill list's Agent rows, so a
single change covers all three engines (native / fzf-lua / snacks); engine
code is untouched. The `+ new agent` sentinel and the kill list's `group <n>`
rows keep their own texts.

## Alternatives considered

### Why not fold `~` at creation/storage time?

Folding in `commands.lua`/`Util.cwd()` and letting the backend store
`~/…` breaks launch correctness: tmux does not expand a literal `~` in `-c`
(verified empirically — `new-session -c '~/vantage'` resolves the literal
path relative to the client cwd, silently falling back to `$HOME` on
failure), and the driver passes the cwd straight into `-c`
(`backend/tmux.lua` new-window/new-session). Keeping launch correct would
force `create()` to split an absolute launch-cwd from a folded stored-cwd —
the fold would live in the backend storage layer, and every later consumer
of `@agent-cwd` would see whichever form was stored. Stored state instead
keeps its invariant ("cwd is absolute"); a `~` value is meaningful only to
readers sharing the writer's `$HOME`. Absolute values persist regardless
(pre-change windows; any cwd outside `$HOME` can never fold), so display
code must handle absolute cwds anyway: folding at creation buys nothing at
display and adds a second tolerated form to one field. Display-only folding
(`Util.tilde`) already yields the same rendered string with zero storage
risk.

### Why not keep showing `cmd`?

`cmd` is the launch string, not the identity the user chose: the same binary
can back several Tools, and `cmd` carries nothing about the Group. The row's
middle segment is the Tool name the user picked in the wizard, so it shows
`agent.tool`; `cmd` survives only as the nil fallback so a stray window can
never crash `format_agent` (string formatting of `nil` errors).

### Why not keep the kill list on the old format?

The kill list shares `format_agent` deliberately; splitting a private legacy
formatter for it would reintroduce two row identities for the same Agent.
Kill rows inherit the new text, and their action context (kill) is
unambiguous either way.

## Consequences

- Agent rows in the Agent list and the kill list now read
  `[group] tool · ~cwd` under every engine; no picker implementation changed.
- cwd stays absolute in tmux window options and in `vantage.Agent.cwd`; only
  the row text folds `$HOME` through `Util.tilde`, exactly as before.
- No doc or README describes the row text, so nothing user-facing there
  went stale.
- The terminal buffer title (`retitle`, `lua/vantage/client.lua`) still
  shows the raw absolute cwd — pre-existing, outside this change's scope;
  a later one-line `Util.tilde` there would make it consistent.
- Rows build on the shared same-source item model of the
  [Pluggable Picker frontend](../architecture/2026-08-31-pluggable-picker-frontend.md)
  and [Picker-owns-every-selection](../architecture/2026-09-03-picker-owns-plain-selections.md)
  decisions; neither pinned the row string, so nothing is superseded.
