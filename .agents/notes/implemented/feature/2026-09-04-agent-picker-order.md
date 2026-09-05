# Agent Note: Agent picker ordering, focused-Agent pin, and Tool-row creation

Status: implemented

## Problem

The Agent picker (`:Vantage switch`, and the `:Vantage toggle` fallback that
shares its builder) listed Agents in tmux window-id order and hid creation
behind a single `+ new agent` sentinel that re-entered the whole Tool → Group
wizard. Invoking switch from inside the vantage terminal offered the Agent
you were already looking at as a first-class choice, with nothing marking it
as "current". Row order carried no meaning, so a stable, predictable list —
and a visible sense of where the picker's terminal already is — required an
explicit ordering and a pinned, inert current-Agent row.

## Decision

`agent_items()` in `lua/vantage/select.lua` (assembled by `agent_spec()`) builds
the rows and is the single ordering point every engine renders as given
(engines only reorder by fuzzy relevance while a query is typed):

- **Focused-Agent pin.** When the picker is invoked from the vantage
  terminal window — the terminal is open and is the current window, i.e. the
  window the cursor was last in — the Agent that terminal shows
  (`Client.last_agent_alive()`) is pinned first, exempt from the ordering.
  Its row text gains a ` (focused)` suffix. Confirming it does nothing:
  `commands/agent.lua`'s `pick_or_new` filters on the item's `focused` field and
  returns. The snacks engine restores terminal mode on the client terminal
  after any picker close back onto it — Esc cancels and the no-op confirm
  alike — because snacks pickers close into Normal (see
  [gotchas](../../../docs/gotchas.md)); fzf-lua and native leave the
  terminal in terminal mode and need nothing. No engine-specific
  disabled-row machinery is used (see Alternatives). Invoked from any other
  window, there is no focused Agent and no pin.
- **Agent ordering.** Remaining Agent rows sort ascending by group, absolute
  cwd, and tool name (`agent.tool`, the `cli.tools` key; `agent.cmd` as the
  nil fallback — the same key the row text shows); exact ties break by
  numeric window id (`@N`, creation order). Sorting compares stored fields,
  never the display string, so `~` folding never leaks into order.
- **Tool rows replace the sentinel.** The `+ new agent` sentinel is gone.
  The list ends with one row per configured `cli.tools` key, `table.sort`ed.
  Agent rows lead with `nf-fa-toggle_on` (`\uf205`, Nerd Fonts) — a running
  Agent is "on"; Tool rows lead with `nf-fa-toggle_off` (`\uf204`). Confirming
  a Tool row calls `commands/agent.lua`'s extracted
  `create_with_tool`, which asks only for a Group (or a new Group's name), then
  creates the Agent in the current buffer's cwd and runs the caller's tail
  action. Tools are never
  deduplicated against running Agents — parallel Agents of one Tool stay
  possible.
- **Empty is the engines' problem.** `agent_items()` always returns the list
  (possibly empty) and no longer warns; each picker's `pick_agent` warns
  `no agents and no tools configured (cli.tools)` and returns when the list
  is empty (no Agents running and no Tools configured). Zero Agents with
  Tools configured opens the picker listing only Tool rows.
- **Scope.** The kill list keeps its order and its plain rows (no glyphs,
  no `(focused)` marker). The shared choice type widens from
  `{ kind: "agent"|"new" }` to `{ kind: "agent"|"tool", agent?, tool?,
  focused? }` across `config.lua`, the three picker implementations, and
  `select.lua`.

The Agent row string itself is the
[entry-format note](2026-09-04-agent-picker-entry-format.md)'s shared
`format_agent`, updated in this change from the bracketed `[group] tool ·
cwd` layout to `tool · group · cwd` — unbracketed group moved between the
tool name and the `~`-folded cwd, a single ` · ` between the three segments.
The Agent list's rows prefix that string with the Agent glyph and a
two-space gap, and suffix ` (focused)` only on the pinned row; kill rows
carry the same plain string.

## Alternatives considered

### Why not engine-native disabled rows (fzf-lua `--header-lines`, snacks dimming)?

fzf-lua's own buffers picker pins the current buffer by emitting it first
and setting fzf's `--header-lines 1`, making the row unselectable and immune
to fuzzy matching; snacks picker has no header-lines/disabled-item
equivalent (verified in source), and native `vim.ui.select` has neither. A
per-engine mechanism would give three different looks and behaviors for the
same row (true disabled in one engine, visible-but-selectable in another).
The uniform contract — pin first, mark `(focused)`, make confirming it a
no-op at the command layer — keeps one code path per engine and reads the
same everywhere.

### Why sort in the builder, not in each engine?

One comparator serves all three engines, and engines receive the list in
final order when no query is typed. Sorting in each engine would triplicate
the same key logic in renderer-owned code, which the
[Pluggable Picker](../architecture/2026-08-31-pluggable-picker-frontend.md)
boundary keeps free of domain logic.

### Why `(focused)` as a text suffix, not a separate marker column?

Engines render plain text rows; only the shared `text` string is guaranteed
portable. Parenthesized suffix matches the row grammar (`… · ~/cwd
(focused)`) and cannot collide with group brackets.

### Why keep `agent_items()` empty (list-shaped) rather than `nil` + internal warning?

The builder no longer owns the distinction between "no Agents" and "no
Agents and no Tools" — with Tool rows, zero Agents is a legitimate,
openable list. The caller-facing warning moves to where the empty case is
handled (`pick_agent` in each engine), keeping the builder a pure projection
of state.

### Why break ties by window id and not by name?

`agent.name` is a timestamped default (`agent-<time>`) that can collide
within one second and says nothing about the user's intent; `@N` is
monotonic with creation, unique, and already the storage key.

## Consequences

- The `:Vantage switch` picker now reads as: pinned `(focused)` Agent (when
  invoked from the terminal), Agents sorted by group → cwd → tool, then one
  toggle-off row per configured Tool.
- `+ new agent` disappears from every picker; creation from the Agent list
  is one confirm (Tool row) + one Group choice instead of the two-step
  wizard.
- README and `doc/vantage.nvim.txt` describe the new list layout and creation
  channels; the entry-format note's consequences are corrected in place for
  the glyph-prefixed Agent rows (the kill list keeps the plain shared
  string).
- `pick_agent` callbacks now receive `kind = "tool"` rows and
  `focused = true` rows; anything else consuming agent items (none today)
  must route both new shapes.
- The empty-list handling later moved out of the engines into the caller,
  keyed on the picker's boolean `empty` return — see [the
  picker-pure-renderers note](../architecture/2026-09-05-picker-pure-renderers.md).
- The toggle/switch command boundary later split presence from target: toggle
  opens/hides the terminal (picking when there is none), switch only re-points
  an existing one and warns with none — see the [toggle/switch boundary
  note](../architecture/2026-09-05-toggle-switch-command-boundary.md).
