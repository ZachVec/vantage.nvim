# Agent Note: Reviews — notes anchored to ranges, batched via {reviews}

Status: implemented

## Problem

Agents are interactive REPLs: the only way to give one context is to type it.
[Prompts](2026-08-31-prompts.md) solve "recall a canned message", but a coding
session also accumulates ad-hoc observations across many files — "this block
is duplicated", "rename this later", "why is this doing X?" — that the user
wants to collect as they read and then hand to the Agent in one go.

## Decision

A **Review** is a free-text note anchored to a line range in a normal buffer,
collected in memory only: a per-buffer registry maps an extmark id to
`{ buf, start_row, end_row, note }`, and the extmark carries the range plus a
`number_hl_group` tint. They are managed through `:Vantage review` —
`review` (a range + note float), `review list` (picker), and `review clear`.
Selecting a row jumps to its range and opens the editable note float; an
empty note deletes the Review after a confirmation.

The Review picker uses the normal `Picker.pick` path. fzf-lua and snacks
preview each Review through `reviews.item` and bind `<c-x>` as a flow-owned
Picker command; native has neither preview nor commands and is selection-only.
Rendering uses the number-column tint (`VantageReview`, with
`VantageReviewActive` while editing) so it never shifts layout or obscures
code.

`{reviews}` is a Prompt placeholder whose resolver renders every Review
through `reviews.item` (default `"{lines} {note}"`) and returns nil when there
are none. It is a built-in identity prompt and is hidden while there are no
Reviews. The item template fields are `{note}`, `{lines}`
(`<relpath>:L<start>-<end>`, spelled through the Tool's `format` hook — see
[the Tool format hook note](2026-09-11-tool-format-location-hook.md)),
`{code}`, `{file}`, `{start}`, and `{end}`.
After a successful send containing `{reviews}`, `reviews.clear_on_send`
(default true) clears them.

## Alternatives considered

### Why not show the range with a sign column or background highlight?

A gutter sign can widen the sign column and shift the window; a background
highlight obscures code. The number-column tint is layout-stable and needs one
extmark per range. With the number column off, `review list` remains the way
in.

### Why not a dedicated `:Vantage review send`?

Sending is exactly "type a rendered message into the focused Agent", which is
Prompt's job; a second path would duplicate focused-Agent resolution, the
per-tool `format` hook, and `send_keys`. `{reviews}` reuses the pipeline.

### Why not persist Reviews to disk?

A file format is a larger commitment than the session-scoped state the rest of
the plugin already keeps. Persistence remains a possible follow-up.

## Consequences

- `{reviews}` is a dynamic prompt placeholder; Reviews are lost on buffer
  unload/reload or Neovim exit and never edit the file.
- `:Vantage` keeps `range = true` so `review` can take the visual selection.
- The note float is a plain scratch buffer with `<Esc>` as the commit action.
- The current Picker command/capability contract is owned by
  [composition-root-and-neutral-seams](../architecture/2026-09-10-composition-root-and-neutral-seams.md).
