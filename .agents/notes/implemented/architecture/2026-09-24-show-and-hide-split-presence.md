# Agent Note: show and hide split the Terminal's presence command

Status: implemented

## Problem

One name, `toggle`, covered three different states — window open, window closed
with the client alive, and no client at all — and it was reachable from two
places that could never mean the same thing. A key in `cli.win.keys` is
installed on the Terminal's own buffer, where a Terminal necessarily exists, so
that key could only ever hide. `:Vantage toggle` runs from any window, so it
also had to show a hidden Terminal and, with none, run the Agent picker and
attach. Two trigger contexts shared one verb, and the verb promised a symmetry
neither context had.

The ambiguity also cost the Frontend its boundary. Deciding between "re-open
what is hidden" and "there is nothing to show, create one" is a decision about
which Agent the Terminal should display, and only the command layer can make it
— it alone owns the Picker and the attach flow. Parking that decision behind
`Terminal.toggle` put command-layer judgment inside the display module, where
the dependency direction forbids it from reaching the pieces it would need.

## Decision

Presence splits into two verbs with two answers, and each entry point gets the
one it can honor:

- `hide` closes the Terminal's window and keeps its buffer, job and Attachment
  alive. It is `:Vantage hide` and the `hide` Terminal action token. With no
  window open it does nothing, silently — there is no expectation to
  disappoint.
- `show` focuses the Terminal when it is up, re-opens the same buffer when it
  is hidden, and with no live client picks an Agent (Tool entries create one)
  and attaches and shows. It is `:Vantage show` only, with no Terminal action
  token: a token is installed on the Terminal buffer, where the window is open
  by construction, so `show` there could only ever be a no-op.
- `Terminal.toggle` is deleted. The Frontend keeps `hide` and the answer half
  of `show` — `Terminal.show()` returns false when there is no live client —
  and the command layer turns that false into a pick. The Terminal never
  chooses which Agent to display (`commands/attach.lua`'s `show` owns that).
- There is no compatibility shim. `toggle` is gone as a subcommand and as a
  token; `:Vantage toggle` warns and prints usage, and an `rhs` of `"toggle"`
  is bound verbatim like any other unrecognized string, which means the
  literal key sequence `t-o-g-g-l-e`.
- `detach` is unchanged: it destroys the Terminal, and Agents keep running.

Two consequences of the split land outside the verbs themselves:

- The `:Vantage` subcommands are one table in `commands/init.lua`. Dispatch,
  the usage text and completion all derive from it, so a subcommand — and its
  own words, like `review list` — is named once.
- The Terminal's public surface narrows to what a caller acts through:
  `open` (start a fresh client), `hold`, `show`, `hide`, `destroy`, and the
  `attachment` field. `is_open`, `open_win` and `reset` became module-local,
  and the layout specs drive them through `open`.

The vocabulary in [`docs/glossary.md`](../../../docs/glossary.md) records the
split: `open` creates a client, `show` reveals one that exists, `hide` closes
its window. No single name carries two of those jobs.

## Alternatives considered

### Why not keep `toggle` as an alias?

An alias cannot be honest in either home. Pointing the token at `hide` is
behaviorally right inside the Terminal but keeps a name that reads as a
symmetry; pointing the subcommand at `show` makes a second invocation focus an
already-focused Terminal instead of hiding it, which is a silent behavior
change dressed as compatibility. No compatibility was asked for, so the name
is gone and both failure modes are plain: an unknown subcommand warns and
prints usage, and an unrecognized `rhs` binds literally, exactly as it does for
every other string this plugin does not know.

### Why not let the Terminal decide whether to create one?

`Terminal.show()` would have to reach the Picker, the Backend and the attach
flow to answer "there is no client — show which Agent?". The Frontend may not
import the command layer (`scripts/verify-architecture.lua` enforces the
direction), and attaching a client is a command-layer act even where it were
allowed. Returning `false` keeps the Terminal's job to "display what you were
given" and puts the choice where the Picker already is.

### Why not make `show` a token too?

A token exists to answer a key pressed inside the Terminal. In that window the
Terminal is open, so `show` would resolve to a no-op and its presence in the
token map would advertise a state the key can never be in. The token set stays
`hide`, `switch`, `prompt`, `files`, `buffers`.

### Why not rename `Terminal.open`, now that `show` exists?

`open` creates the client and takes its buffer (the attach flow calls it);
`show` reveals a buffer that is already there. They are different operations
with different owners, and the collision is in the ear, not the interface —
`docs/glossary.md` calls the difference out instead of renaming a primitive
that only `commands/attach.lua` uses.

### Why not have the plugin detect whether a Terminal exists and pick the verb?

That is the `toggle` decision again with more code. The trigger context already
knows which verb it means: a key on the Terminal's buffer means `hide` and a
normal-window mapping means `show`. Making the plugin re-derive that from live
state would put a runtime probe where the user's own two keymaps are the
answer.

## Consequences

- `:Vantage toggle` no longer exists; `README.md` and `doc/vantage.nvim.txt`
  list `show` and `hide`, and the `cli.win.keys` sample binds `hide` on the
  Terminal buffer with a normal-window `:Vantage show` mapping beside it.
- The only presence key in `cli.win.keys` is the one that closes the window.
  Showing is a mapping in an ordinary window, so neither side has to ask
  whether a Terminal exists.
- `Terminal.show()` answers false when there is no client; `:Vantage show`
  treats that as its cue to pick an Agent, and `:Vantage hide` on no Terminal
  is a silent no-op.
- `commands/init.lua` derives dispatch, usage and completion from one
  subcommand table; `review list|clear` are that table's `args` rather than
  hand-written branches in `run` and `complete`.
- Terminal behavior is pinned by specs: `hide` keeps the buffer and job alive,
  `show` re-opens the same buffer focused, `show` answers false with no client,
  and a stray `hide` is harmless.
- Two implemented Agent Notes keep their decisions and were updated in place
  for the renamed symbols: the [presence/target boundary
  note](2026-09-05-toggle-switch-command-boundary.md) (the presence command is
  `show`) and the [converge-command-surface
  note](../simplification/2026-09-06-converge-command-surface-to-terminal-actions.md)
  (the one name that was both a command and a token is gone).
