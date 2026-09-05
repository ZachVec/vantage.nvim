# Agent Note: toggle owns presence, switch owns target

Status: implemented

## Problem

`:Vantage toggle` and `:Vantage switch` had overlapping jobs. `toggle` did
three things: hide the open terminal, show the hidden terminal, and — with no
live terminal — either re-open the last-focused Agent, run the Agent-creation
wizard (when no Agent ran), or open the Agent picker. That third behavior is
target work (choosing which Agent the terminal displays) smuggled into a
presence command. The two commands shared the same `pick_or_new` builder, and
the "creates if empty" wizard duplicated the Tool rows the Agent picker already
offered.

## Decision

The single Client has two independent concerns, owned by two commands:

- `:Vantage toggle` owns **presence** — hide the open terminal, show the hidden
  terminal, or, with no live terminal, open the Agent picker and open the
  terminal on the chosen Agent. It no longer re-opens to the last-focused Agent
  and no longer runs a creation wizard: with no terminal it always picks.
- `:Vantage switch` owns **target** — re-point the existing terminal to another
  Agent, never showing or hiding it. With no live terminal it warns
  (`no client — use :Vantage toggle to open one`) and does nothing.

The tail action after a pick is the only difference, so it is injected as a
callback rather than forked:

- `commands/agent.lua` has one `pick_or_new(after)` and one
  `create_with_tool(tool_name, after)`, each threading `after` through to
  `do_create`. `Client.focus` (materialize + show) is toggle's `after`;
  `Client.retarget` (re-point, no show) is switch's.
- `Client.retarget(agent)` is the new re-point-only primitive: with a live
  terminal it sets `last_agent`, `select-window`s, and re-titles; with none it
  returns false. `Client.focus` keeps its materialize-then-show behavior and is
  now used only by toggle's open path.
- The Agent-creation wizard (`create_wizard`) is deleted: creation lives only
  in the Tool rows of the Agent picker, whose post-create tail action is the
  same injected `after`.

## Alternatives considered

### Why not keep toggle's "re-open to last Agent" shortcut?

It mixed target selection into a presence command and hid an unasked focus.
Making toggle always pick when the terminal is gone keeps the command
predictable; the picker's pinned `(focused)` row still marks where the terminal
was when it exists.

### Why not let switch bootstrap when there is no terminal?

That would have switch creating a terminal, re-coupling the two axes. Warning
instead keeps switch pure re-point and makes `toggle` the single place a
terminal is materialized.

### Why not fork `pick_or_new` into two per-command copies?

The only difference is the tail action. One function parameterized by an
`after` callback (`Client.focus` vs `Client.retarget`) removes the duplication;
`create_with_tool` takes the same callback for the same reason.

## Consequences

- `:Vantage toggle` no longer "creates if empty" nor re-opens to the last
  Agent: with no terminal it opens the picker. `:Vantage switch` no longer
  creates or shows a terminal; it warns with none.
- `:Vantage switch @1` after a detach no longer works directly (no terminal) —
  `toggle` must reopen one first.
- `create_wizard` and its Tool step are gone; the Tool rows are the single
  creation channel.
- README, `doc/vantage.nvim.txt`, and `docs/architecture.md` describe the
  presence/target split. The `(focused)` pin and its no-op confirm are
  unchanged — see the [Agent picker order
  note](../feature/2026-09-04-agent-picker-order.md).
- The command layer was later split into `commands/` modules with a thin
  `init.lua` dispatch — see the [command-layer modules
  note](2026-09-05-command-layer-modules.md).
