# Agent Note: Agent picker ordering, focused-Agent pin, and Tool-entry creation

Status: implemented

## Problem

The Agent picker (the `switch` terminal key, and the `:Vantage toggle`
fallback that shares its builder) listed Agents in tmux window-id order and hid creation
behind a single `+ new agent` sentinel that re-entered the whole Tool → Group
wizard. Invoking switch from inside the vantage terminal offered the Agent
you were already looking at as a first-class choice, with nothing marking it
as "current". Entry order carried no meaning, so a stable, predictable list —
and a visible sense of where the picker's terminal already is — required an
explicit ordering and a pinned, inert current-Agent entry.

## Decision

`commands/attach.lua` builds the entries and is the single ordering point
every engine renders as given (engines only reorder by fuzzy relevance while
a query is typed):

- **Focused-Agent pin.** When the Terminal has an Attachment (`switch`, which
  is terminal-only), the Agent that terminal shows (`attachment:focus()`) is
  pinned first,
  exempt from the ordering.
  Its entry text gains a ` (focused)` suffix. Confirming it does nothing:
  `commands/attach.lua` filters on the item's `focused` field and
  returns. The snacks engine restores terminal mode on the client terminal
  after any picker close back onto it — Esc cancels and the no-op confirm
  alike — because snacks pickers close into Normal (see
  [gotchas](../../../../docs/gotchas.md)); fzf-lua and native leave the
  terminal in terminal mode and need nothing. The creation path's plain step is
  gone — the Group name is a cmdline prompt answered after the picker closed —
  and `pick_naive`'s wrapper still queues its re-entry before the choice
  handler, which is now shared with `:Vantage prompt`
  ([the Terminal-owns-its-mode note](../bug-fix/2026-09-25-the-terminal-owns-its-mode.md)).
  No engine-specific disabled-entry machinery is used (see Alternatives).
  Declared not-from-terminal (`show`'s open-path fallback), there is no
  focused Agent and no pin.
- **Agent ordering.** Remaining Agent entries sort ascending by group, absolute
  cwd, and tool name (`agent.tool`, the `cli.tools` key the entry text shows);
  exact ties break by driver-neutral `seq` (creation order). Sorting compares
  stored fields, never the display string, so `~` folding never leaks into
  order.
- **Tool entries replace the sentinel.** The `+ new agent` sentinel is gone.
  The list ends with one entry per configured `cli.tools` key, `table.sort`ed.
  Agent entries lead with `nf-fa-toggle_on` (`\uf205`, Nerd Fonts) — a running
  Agent is "on"; Tool entries lead with `nf-fa-toggle_off` (`\uf204`). Confirming
  a Tool entry asks only for a Group (or a new Group's name) through
  `commands/attach.lua`'s `ask_group`, then creates the Agent in Neovim's
  global cwd and runs the caller's tail action. Tools are never
  deduplicated against running Agents — parallel Agents of one Tool stay
  possible.
- **Empty is the flow's problem.** The item stream emits the list (possibly
  empty) and does not warn; an empty pick opens and stays open until the user
  cancels it. Zero Agents with Tools configured opens the picker listing only
  Tool entries.
- **Scope.** The kill list keeps its own order — Agent entries in creation
  order, Group entries by name — and its plain entries (no glyphs, no
  `(focused)` marker). Its Groups are sorted by the flow because the Backend
  derives them in the Agents' order, which is what the Group prompt wants.
  What a chosen entry means is the entry's own `kind` — `focused` / `agent` /
  `tool` in the Agent list — read by
  `commands/attach.lua`
  ([picker entries are data](../architecture/2026-09-13-picker-entries-are-data.md)).

The Agent entry text is the shared
Agent text, updated in this change from the bracketed `[group] tool · cwd`
layout to `tool · group · cwd` — unbracketed group moved between the tool name
and the `~`-folded cwd, a single ` · ` between the three segments.
The Agent list's entries prefix that string with the Agent glyph and a
two-space gap, and suffix ` (focused)` only on the pinned entry; kill entries
carry the same plain string.

## Alternatives considered

### Why not engine-native disabled entries (fzf-lua `--header-lines`, snacks dimming)?

fzf-lua's own buffers picker pins the current buffer by emitting it first
and setting fzf's `--header-lines 1`, making the entry unselectable and immune
to fuzzy matching; snacks picker has no header-lines/disabled-item
equivalent (verified in source), and native `vim.ui.select` has neither. A
per-engine mechanism would give three different looks and behaviors for the
same entry (true disabled in one engine, visible-but-selectable in another).
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

Engines render plain text entries; only the shared `text` string is guaranteed
portable. Parenthesized suffix matches the entry grammar (`… · ~/cwd
(focused)`) and cannot collide with group brackets.

### Why keep the builder list-shaped rather than `nil` + internal warning?

The builder no longer owns the distinction between "no Agents" and "no
Agents and no Tools" — with Tool entries, zero Agents is a legitimate,
openable list. An empty pick opens and waits for a cancel, so the builder stays
a pure projection of state.

### Why break ties by window id and not by name?

Name-based ties would fall back on tmux's automatic window names, which can
collide and say nothing about the user's intent; `@N` is monotonic with
creation, unique, and already the storage key.

## Consequences

- The `switch` picker now reads as: pinned `(focused)` Agent (when invoked
  from the terminal), Agents sorted by group → cwd → tool, then one
  toggle-off entry per configured Tool.
- `+ new agent` disappears from every picker; creation from the Agent list
  is one confirm (Tool entry) + one Group prompt instead of the two-step
  wizard.
- README and `doc/vantage.nvim.txt` describe the new list layout and creation
  channels; the entry-format note's consequences are corrected in place for
  the glyph-prefixed Agent entries (the kill list keeps the plain shared
  string).
- `Picker.pick_fancy` callbacks receive the flow's entry objects; `attach`
  handles Tool entries and the focused no-op entry.
- Empty picks later stopped closing themselves: the pick opens empty and stays
  open until cancel — see
  [picker-two-interfaces](../architecture/2026-09-18-picker-two-interfaces.md).
- The presence/target command boundary later split the two: `show` opens the
  terminal (picking when there is none) and `hide` closes it, while switch only
  re-points an existing one and warns with none — see the [show/switch boundary
  note](../architecture/2026-09-05-toggle-switch-command-boundary.md).
