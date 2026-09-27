# Agent Note: Review owns its editing float

Status: implemented

## Problem

`frontend/note.lua` held a generic editable-float editor (`Note.open(opts)`)
with its own `vantage.NoteOpts` contract, extracted in
[note-editor-pure-ui](../../archived/architecture/2026-09-05-note-editor-pure-ui.md)
so any future caller could reuse "edit text, Esc to commit". Review is the only
caller — `commands/review.lua` opened the float for a new Review and for an
existing one — and no other Vantage feature edits text in a float. The generic
contract, its own test file, and the split of one editing interaction across
two modules were paying for a reuse that does not exist.

## Decision

`frontend/review.lua` owns the Review editing float, and `frontend/note.lua`
is gone:

- The float mechanics — centered scratch float, `<Esc>` commit, trailing-blank
  trim, the `BufWipeout` close hook, and `reviews.float.style` inheritance —
  are a private local helper in `frontend/review.lua`, not a contract.
  `vantage.NoteOpts` is deleted.
- The module exposes two Review-shaped verbs. `Review.edit(buf, id)` jumps to
  the Review, tints it active, edits its `note`, and deletes it after a
  confirmation when the commit is empty. `Review.create(buf, start_row, end_row)`
  asks for a new Review's text and adds it on commit.
- `Review.edit` is the interactive editor; the data mutation that replaces a
  Review's text is renamed `Review.set_note(buf, id, note)`.
- `commands/review.lua` keeps dispatch, the list, clear, and the add-range
  resolution; it opens no window, maps no key, and owns no empty-deletes
  policy.

## Alternatives considered

### Why not keep `frontend/note.lua`?

Its only reason to be separate was reuse, and that reuse is hypothetical: one
consumer, two call sites inside it. A single-consumer mechanism is an
implementation detail, and a deep module may hold internal seams — the float
helper is one — without exposing them on its interface.

### Why not merge the editor into `commands/review.lua`?

The command layer decides *when* UI appears; every buffer/window construction
in the repo lives in `frontend/` (`frontend/terminal.lua`, the picker
implementations, formerly `frontend/note.lua`). Moving the float into the
command layer would put raw `nvim_create_buf` / `nvim_open_win` / keymap code
there and make the Review flow the owner of a UI widget.

### Why not export `Review.open_editor(opts)`?

That is `Note.open` under another name: the same speculative contract, now
attached to the module the `{reviews}` prompt and the entry previews import.
The editor is Review-only, so its interface should be Review-shaped verbs, not
an options table every caller of the module must learn.

## Consequences

- `frontend/review.lua` owns Review storage, rendering, and its editing float;
  `Review.edit` / `Review.create` carry the jump, the active tint, and the
  empty-deletes policy that used to sit in `commands/review.lua`.
- Review's read paths are unchanged: `Review.render` / `render_item` /
  `location` are what the `{reviews}` prompt and the entry previews call, and
  none of them opens a window.
- `tests/frontend/note_spec.lua` is gone; the editing-float behavior is pinned
  through `Review.edit` / `Review.create` in `tests/frontend/review_spec.lua`.
- This note supersedes the archived
  [note-editor-pure-ui](../../archived/architecture/2026-09-05-note-editor-pure-ui.md)
  decision.
