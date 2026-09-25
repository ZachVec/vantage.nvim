# Agent Note: The snacks adapter keeps a pick's stream in one object

Status: implemented

## Problem

`frontend/picker/snacks.lua`'s `pick_fancy` had grown into one ~168-line
function holding five concerns at once: starting and cancelling the flow's item
stream, bridging it into snacks' coroutine finder, taking the confirmed choice
and closing around it, binding the flow's commands, and wiring the preview pane.
The run's facts — the entries seen so far, the batch queue, whether the source
had ended, its cancel function, the draining task, and the generation stamp
saying which run owned them — were six loose locals shared by nested closures.
`task` was the worst of them: the emit and done callbacks read it while the
drain closure assigned it, so the two halves formed a cycle a reader had to hold
the entire function to follow. The generation guard the
[abort-scoping note](../bug-fix/2026-09-19-snacks-abort-is-scoped-to-its-run.md)
records was implicit in that tangle, `committed` was buried inside a table
literal, and `pick_opts.win` was assembled in three separate places.

## Decision

`frontend/picker/snacks.lua` keeps its external interface — `vantage.PickerImpl`
is unchanged — and moves the internal complexity behind named private parts:

- A `vantage.SnacksStream` class owns the pick's item stream. `start` begins a
  run and resets the fields that run owns (`items`, `queue`, `finished`,
  `cancel`, and the `generation` stamp), `emit` and `finish` receive the flow's
  callbacks, `finder` is snacks' finder entry point, and `drain` hands batches
  to snacks from inside its own task and answers abort. The generation check
  and the drain loop now read `self` fields instead of shared locals.
- `confirm_handler(spec, opts, terminal_win)` returns the confirm function and
  owns `committed` in its own closure; the close-ordering comment travels with
  the code it explains.
- `command_bindings(commands, stream)` maps the flow's commands to snacks
  actions plus input- and list-pane keymaps, reading the current run's entries
  from the stream.
- `preview_pane(preview)` renders the highlighted entry, and `pick_fancy`
  composes the parts in order: terminal-mode release, stream, `pick_opts`,
  engine call.

[The abort-scoping decision](../bug-fix/2026-09-19-snacks-abort-is-scoped-to-its-run.md)
still holds: a run records its generation and a stale abort returns before
touching anything. One defensive detail rides along: `drain` clears `self.task`
only when the task it is exiting is still the current one, so a run that ends
after a newer run has taken the handle cannot strand the newer drain.

The list pane's keymap binds its action as a string
(`win.list.keys[lhs] = action_name`), which snacks resolves through the pick's
own `opts.actions` (`snacks/picker/core/actions.lua` `M.resolve` →
`snacks.picker.config.action`). That resolution was already in use but
unpinned; the adapter spec now asserts both panes' bindings.

## Alternatives considered

### Why not split the stream into its own module (`picker/snacks/stream.lua`)?

The file boundary would add a require edge and a second place to look without
adding leverage: one adapter drives the stream, its consumer is the same file's
`finder`, and the existing specs already reach it through the engine fake
(`package.loaded["snacks.picker"]`) at the adapter's interface. Extract it if a
second consumer ever appears; none does today.

### Why not one shared stream seam for `fzf-lua` and `snacks`?

Their finder contracts differ where it matters: fzf-lua writes prefixed lines
into a pipe and round-trips entries through the index prefix, while snacks
resumes its own coroutine task and scopes aborts to a run. A shared interface
would be shaped by whichever engine came first and would leak engine knowledge
into the facade, against
[picker implementations are pure renderers](../architecture/2026-09-05-picker-pure-renderers.md).
Two engines with different mechanics are two adapters, not one seam.

### Why not a per-run object with the pick holding the current one?

A `Run` per finder call would own the run's state cleanly, but the flow's
commands read *the current run's* entries, so the pick would need a second
object (or a getter) to hold "the current run" — reintroducing the owner the
generation stamp already is, at the cost of another layer. One stream with a
generation is the smaller shape.

### Why not leave the six locals and comment them better?

The reading cost is not missing explanation; it is that `task` is written by one
closure and read by another, so no comment can remove the need to read both
halves together. Naming the object and giving each fact one home is what makes
the abort and drain paths separately reviewable.

## Consequences

- `pick_fancy` composes four named parts instead of interleaving five concerns,
  and the run's facts are fields on one documented object.
- Behavior is unchanged: the same finder shapes, the same one-tick close, the
  same run-scoped abort.
- `tests/frontend/picker_snacks_spec.lua` pins the wiring — the list pane's
  string action binding, and that a command-less pick binds no actions and no
  pane keymaps.
- The private `vantage.SnacksStream` class is internal to the adapter, so the
  domain glossary does not carry it; `docs/architecture.md` and
  `docs/gotchas.md` need no change, since the picker contract, the finder
  shape, and the engine mechanics are untouched.

## Verification

`make check` (Agent Notes + stylua + architecture + lua-language-server) and
`make test` pass. The adapter spec covers the static list, the live drain, the
superseded run's abort, the command keymaps on both panes, the preview pane,
and the terminal-origin close; mode-level behavior is unchanged and stays
covered by the manual procedure in `docs/gotchas.md`.
