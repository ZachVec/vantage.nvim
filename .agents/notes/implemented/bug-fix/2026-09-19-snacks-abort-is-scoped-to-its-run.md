# Agent Note: The snacks abort handler acts only for its own run

Status: implemented

## Problem

`snacks.pick_fancy` starts a fresh item run on every finder call — the opening
one, and one per command that reports the list may have changed — and registered
an abort handler on that run's async task which mutated the pick's shared
`cancel`, `finished`, and `queue`. Snacks aborts the previous task a tick after
the next run has already begun: `finder:run()` calls `self.task:abort()`, whose
abort event is delivered from snacks' async executor on a later tick, while
`start()` runs synchronously inside `self._find(...)`. The stale handler then
cancelled the *new* run's source and forced its drain loop to end. With the live
`files` source, any finder re-run — snacks' own `<a-h>`/`<a-i>`/`<a-f>`/`<a-r>`
toggles, or a Vantage command that reports the list changed — signalled the
refreshed lister, leaving the listing cut off where it had got to and the run
never finishing.

## Decision

Each `start` bumps a run generation, and the drain closure captures the
generation it belongs to. The abort handler returns without touching anything
when a newer run has started; only the current run's abort cancels the source
and ends the queue. The superseded run's source was already cancelled by the
next `start`, so a stale abort has nothing of its own left to stop.

## Alternatives considered

### Why not compare the cancel function instead of a generation?

The source's optional cancel may be nil — a static or already-finished source
returns none — so "the same run" cannot always be identified by the cancel's
identity; two runs of such a source are indistinguishable that way. The
generation names the run itself, whether or not it has anything to cancel.

### Why not unregister the abort handler when a run ends?

snacks' async surface exposes `on` but no `off`, and the handler fires from the
task's own abort emission — exactly the event a superseded run cannot
unsubscribe from.

### Why not ignore aborts entirely?

The current run's abort must stop its source: closing the pane has to kill the
lister. Only the *stale* handler can be skipped.

## Consequences

- A finder re-run of a live source no longer signals the fresh lister: the
  refreshed list keeps filling and ends normally.
- `tests/frontend/picker_snacks_spec.lua` pins it: run 1 is abandoned by a
  second finder call, run 1's abort fires afterwards, and the test asserts run
  2's source was not cancelled and its batches still reach `done`.
