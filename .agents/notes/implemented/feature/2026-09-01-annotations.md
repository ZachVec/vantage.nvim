# Agent Note: Annotations — notes anchored to ranges, batched via {annotations}

Status: implemented

## Problem

Agents are interactive REPLs: the only way to give one context is to type it.
[Prompts](2026-08-31-prompts.md) solve "recall a canned message", but a coding
session also accumulates ad-hoc observations across many files — "this block is
duplicated", "rename this later", "why is this doing X?" — that the user wants
to collect as they read and then hand to the Agent in one go. Nothing let you
attach a note to a specific range of a normal file and batch-send the set.

## Decision

An `Annotation` is a free-text note anchored to a line range in a normal
buffer, collected in memory only: a per-buffer registry maps an extmark id to
`{ buf, start_row, end_row, note }`, and the extmark carries the range plus a
`number_hl_group` tint. They are managed through the `:Vantage annotate`
subcommands — `annotate` (a range + a note float, the default action),
`annotate list` (open the picker), and `annotate clear` (clear all). Selecting in the picker jumps to the
range and opens an editable note float: a plain scratch buffer in normal mode,
so editing is ordinary Vim (multi-line, undo). The one added normal-mode
keymap, `annotations.keys.exit` (default `<Esc>`), commits the note and closes
the float; an empty note deletes the annotation after a `vim.ui.select`
confirmation. `annotations.keys.delete` (unset by default) deletes directly.

The picker goes through the pluggable Picker via a new `pick_annotation`
method: fzf-lua and snacks preview each annotation through the same
`annotations.item` template (WYSIWYG) and offer an in-place `<c-x>` delete;
native (`vim.ui.select`) has neither preview nor keymaps, so it is selection
only.

Rendering is deliberately number-column-only: the annotation's range tints the
line numbers (`VantageAnnotation`, resting) and swaps to
`VantageAnnotationActive` while its note float is open. There is no sign column
and no background highlight, so nothing shifts layout or obscures code; when
the number column is off there is nothing to tint, so nothing draws (the
annotation stays reachable via `annotate list`).

Sending reuses the Prompt pipeline: `{annotations}` is a prompt placeholder
whose resolver renders every annotation through the per-annotation template
`annotations.item` (default `"{lines} {note}"`) and returns nil when there are
none, so an empty set skips the send exactly like any other empty placeholder.
It ships as a built-in identity prompt (like `{file}`/`{line}`) and is hidden
from `:Vantage prompt` while there are no annotations. The item template's
fields are `{note}`, `{lines}` (`@<relpath> :L<start>-<end>`), `{code}` (the
selected lines), and the `{file}`/`{start}`/`{end}` building blocks. The
rendered text then flows through the existing per-tool `format` hook and
`send_keys`, which pastes via bracketed paste so the embedded newlines survive
(see the [prompts note](2026-08-31-prompts.md)). After a successful send of a
template containing `{annotations}`, `annotations.clear_on_send` (default true)
clears every annotation.

## Alternatives considered

### Why not show the range with a sign column or background highlight?

A gutter sign makes the sign column appear (and can widen it when other plugins'
signs coexist), shifting the whole window; a background `hl_group` obscures the
code. The number-column tint (`number_hl_group`) is layout-stable, never
touches code, and needs only one extmark for the whole range. The cost is a
dependency on `number`/`relativenumber` being on — accepted: with it off,
nothing draws and `annotate list` remains the way in.

### Why not a dedicated `:Vantage annotation send`?

Sending is exactly "type a rendered message into the focused Agent", which is
Prompt's job; a second send path would duplicate focused-Agent resolution, the
per-tool `format` hook, and `send_keys`. A `{annotations}` placeholder reuses
the whole pipeline and lets users wrap the batch in their own prose through a
normal prompt template.

### Why not persist annotations to disk?

A file format (location, schema, `.gitignore` interaction) is a much larger
commitment than the session-scoped in-memory state the rest of the plugin
already keeps in tmux. In-memory matches the Agent/View lifetime and adds no
on-disk format; persistence remains a possible follow-up.

## Consequences

- `{annotations}` is the first dynamic prompt placeholder; the prompts note's
  "no `{selection}`/`{input}`" scope is unchanged, and the two notes cross-link.
- Annotations are lost on buffer unload/reload or Neovim exit and never edit
  the file; users who want durable comments must use source comments instead.
- The `Vantage` user command gains `range = true` so `annotate` can take
  the visual selection; every other subcommand ignores the range.
- The note float is a plain scratch buffer with only the `keys.exit` (and
  optional `keys.delete`) keymaps added, so the user's own keymaps apply inside
  it — Vim-consistent, at the cost of their global mappings (e.g. `<leader>`)
  also firing there.
