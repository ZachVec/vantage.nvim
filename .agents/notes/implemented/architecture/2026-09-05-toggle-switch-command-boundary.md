# Agent Note: toggle owns presence, switch owns target

Status: implemented

## Problem

`toggle` and `switch` had overlapping jobs. `toggle` did
three things: hide the open terminal, show the hidden terminal, and — with no
live terminal — either re-open the last-focused Agent, run the Agent-creation
wizard (when no Agent ran), or open the Agent picker. That third behavior is
target work (choosing which Agent the terminal displays) smuggled into a
presence command. The two paths shared the same `pick_or_new` builder, and
the "creates if empty" wizard duplicated the Tool rows the Agent picker already
offered.

## Decision

The single Client has two independent concerns:

- `:Vantage toggle` owns **presence** — hide the open terminal, show the hidden
  terminal, or, with no live terminal, open the Agent picker and open the
  terminal on the chosen Agent. It no longer re-opens to the last-focused Agent
  and no longer runs a creation wizard: with no terminal it always picks.
- `switch` (the `cli.win.keys` terminal action) owns **target** — re-point the
  existing terminal to another Agent, never showing or hiding it. The terminal
  is live by construction when the key is pressed.

The tail action after a pick is the only difference, so it is injected as a
callback rather than forked:

- `commands/attach.lua` owns one shared pick flow and threads the
  caller's tail through after creation. Its `toggle` opens the Terminal on the
  chosen Agent; its `switch` calls `Bridge.retarget(pid, agent)` and never
  shows or hides it.
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
`after` callback (open Terminal vs retarget) removes the duplication; Tool-row
creation takes the same callback for the same reason.

## Consequences

- `:Vantage toggle` no longer "creates if empty" nor re-opens to the last
  Agent: with no terminal it opens the picker. The `switch` key never creates
  or shows a terminal — it only re-points.
- The `switch` key has no `@N` form: it always opens the picker. After a
  detach the terminal must be reopened with `:Vantage toggle` first.
- `create_wizard` and its Tool step are gone; the Tool rows are the single
  creation channel.
- README, `doc/vantage.nvim.txt`, and `docs/architecture.md` describe the
  presence/target split. The `(focused)` pin and its no-op confirm are
  unchanged — see the [Agent picker order
  note](../feature/2026-09-04-agent-picker-order.md).
- The command layer was later split into `commands/` modules with a thin
  `init.lua` dispatch — see the [command-layer modules
  note](2026-09-05-command-layer-modules.md).
