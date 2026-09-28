# Agent Note: gather reads the Focus when it sends

Status: implemented

## Problem

`files`/`buffers` read the Terminal's Focus before opening the picker and kept
that Agent for the whole pick. The Focus is live state; a confirm is later than
the open, and the text is spelled against whichever Agent the flow captured —
so a Focus that changed while the picker was up produced references for the
old Agent. The same pre-read also refused to open the picker at all with no
Focus, even though whether there is an Agent is only a question at the send.

## Decision

`run` opens the picker with no Focus read. `on_choices` reads the Terminal's
Attachment at that moment, warns `no focused agent` (or the Driver's own
reason) and sends nothing when it answers none, and otherwise spells every
chosen reference against that Agent's Cwd through its Tool's `format`.

## Alternatives considered

### Why not keep the pre-read and use it?

It is the bug: the value is captured before the user has finished choosing, and
the send is the point that has to be right.

### Why not read at both points (fail early, send with the later read)?

The early read cannot establish the send-time value, so it only decides
whether to bother opening the picker — and a Focus that appears or disappears
between the two reads is exactly the case the second read exists for. One read,
at the send, is the whole policy.

### Why not capture the Agent and compare against the Focus at the send?

That is a read plus a comparison, and no caller has a different behavior for
"changed": the send uses the live Focus either way.

## Consequences

- `tests/commands/gather_spec.lua` pins the live read: moving the Focus between
  the open and the confirm changes both the Agent the text is sent to and the
  base its references are spelled against.
- The old pre-pick warning became a post-choice warning; with no Agent the
  picker opens, the choice is made, and nothing is sent.
- No Review behavior changes: gather never touched Reviews.
