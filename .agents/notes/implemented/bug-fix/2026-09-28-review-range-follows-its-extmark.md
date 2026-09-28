# Agent Note: A Review's range is its extmark, and deleting the code hides it

Status: implemented

## Problem

The registry stored the Reviewed range as `start_row`/`end_row` beside the
extmark. The extmark moved with the buffer; the fields did not. After an edit,
the list printed the creation-time line numbers, and opening the editor read
the wrong lines — or nil rows near the end of the buffer. Toggling the active
tint re-set the mark with only a start position, so an open/close of the note
float silently turned a range into a point mark and changed how later edits
moved it. A range whose code was deleted left a record that could not be
rendered or edited.

## Decision

The extmark owns the range. A Review record is `{ buf, id, note }`; every
reader gets the live range from `Review.range` (a `details = true` read that
returns nil for a missing or invalidated mark) and there is no second copy to
keep in sync.

The mark is a whole-line half-open range — `(first-1, 0)` to `(last, 0)`,
`right_gravity = true`, `end_right_gravity = false` — with `invalidate = true`
and `undo_restore = true`. Deleting the covered code leaves the mark in place
with `invalid = true`: the Review leaves the list, the preview, and the send,
but a code undo restores the mark's position and validity, and a redo
invalidates it again. No custom undo stack, snapshot, or restore command.

`set_active` re-sets the same id with the full range and the mark's own
options, so toggling the tint cannot reshape it; an invalidated mark is left
alone. `Review.count()` counts records including hidden ones, and
`:Vantage review clear` uses it so a registry holding only invalidated Reviews
is still clearable; `Review.clear` reaches all of them, and a later undo cannot
revive a cleared Review (as with an explicit delete or a buffer unload).

The `reviews.item` vocabulary is the `FIELDS` resolver table's keys, so the
supported placeholder names and their dispatch cannot drift.

## Alternatives considered

### Why not keep the fields and update them on every edit?

That is the bug: a second owner of the range that has to be synchronised on
every change, with a window where it disagrees. The mark already moved; reading
it is the fix.

### Why not delete the mark when its range is gone?

Then the code undo cannot bring the Review back — the mark no longer exists,
and `undo_restore` has nothing to restore. Invalidating keeps the identity
until an explicit delete.

### Why not build our own undo history or a "restore" command?

Neovim's extmark `undo_restore` already couples the mark to the buffer's own
undo history, which is the history the user is editing with. A second stack
would have to reimplement it and explain why `u` in the buffer and a Review
restore could disagree.

### Why not clear only the Reviews that were sent?

A retracted option: once a send clears, it clears the registry, invalidated
entries included. Tracking a sent set would be state with no user-visible
benefit and a new way for the list and the send to disagree.

## Consequences

- `frontend/review.lua` gains `Review.range` and `Review.count`, and every
  reader (collect's sort, `render_item`'s location fields, the editing float's
  jump and code read) goes through the live range.
- `tests/frontend/review_spec.lua` covers a range that moves and shrinks with
  edits, full deletion → invalid → undo → restore → redo, a clear that reaches
  hidden records (and survives an undo), and a tint toggle that preserves the
  range; `tests/commands/review_spec.lua` covers the clear entry point.
- README and `doc/vantage.nvim.txt` state the visible behavior: deleting a
  Review's code hides it until the deletion is undone, and deleting the Review
  or clearing ends it for good.
- [reviews](../feature/2026-09-01-reviews.md) is updated to the registry's new
  shape.
