# Agent Note: The Review list is a display, not a send

Status: implemented

## Problem

`:Vantage review list` read the Focus's Cwd and Tool dialect so every row and
preview spelled its `{lines}` exactly as a `{reviews}` send would. That tied a
purely local list — reachable with no Terminal at all — to whichever Agent the
client happened to be showing, and it made the row's text change when the user
re-pointed the Terminal, for no reason the user asked for. The list answers
"which Review is this and where is it"; a send answers "how does this Agent
spell a location".

## Decision

The Review list spells every row and preview against Neovim's global cwd in
the default Tool dialect (`Config.tool_reference(nil, Util.cwd(), …)`). It
reads no Focus. A `{reviews}` send still spells through the focused Agent's Cwd
and Tool. `Config.tool_reference` remains the one spelling owner; the flow
passes the context it wants.

This deliberately drops the old "the list, the preview, and the send use the
same target format" guarantee: a display and a send are different questions,
and the user accepted a row that can differ from the send.

## Alternatives considered

### Why not keep reading the Focus for the list?

It makes the list's contents a function of the Terminal's current window, and
it needs a live Attachment to answer a question — where is this Review — that
has nothing to do with an Agent.

### Why not follow the Focus only when a Terminal exists?

Same coupling plus a new inconsistency: the same Review would spell one way
with a Terminal attached and another without, for a difference the user cannot
see a reason for.

### Why not spell the list in a third, "display-only" format?

The default dialect is already the honest display form — a path and its `:L`
suffix — and reusing it keeps one spelling owner instead of inventing a
display-only spelling nothing else uses.

## Consequences

- `commands/review.lua` drops its `Terminal`/`Backend` reads; `Entries.review`
  and `Review.render_item` keep taking a context, so the send path is
  unchanged.
- `tests/commands/review_spec.lua` asserts the list never calls the Attachment
  and spells against Neovim's cwd even when a Focus exists.
- The glossary (`Focus`, `Reference`), `docs/architecture.md`, README, and
  `doc/vantage.nvim.txt` say the list is a display and where each side spells
  from; the doc comments that promised "what you see is what gets sent" are
  corrected.
- [reference-spelling-has-one-owner](2026-09-13-reference-spelling-has-one-owner.md)
  and [reviews](../feature/2026-09-01-reviews.md) are updated to the new
  guarantee.
