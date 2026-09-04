# Agent Note: Snacks picker preview shows no line numbers

Status: implemented

## Problem

With `setup { picker = "snacks" }`, every preview-capable Vantage pick — the
Agent list behind `:Vantage switch` (and `toggle`'s pick step), the kill list,
and the annotation picker — renders its preview inside snacks' preview window.
Snacks creates that window with the `number` column on by default (its
`picker/core/preview.lua` builds `wo.number = win.preview.minimal ~= true`,
and no layout sets `minimal`), so a captured terminal pane appeared with a
code-view gutter. The gutter is meaningless there: the preview shows an
Agent's terminal output (or a rendered annotation template), not a file whose
line numbers refer to anything.

## Decision

`picker/snacks.lua` passes preview-window window options with every
preview-capable pick: a shared `NO_PREVIEW_LINENR = { number = false,
relativenumber = false }` rides as `win = { preview = { wo = … } }` on
`pick_agent`, `pick_kill`, and `pick_annotation`. Snacks merges pick-level
opts last (defaults → user config → source → call opts), so Vantage's picks
resolve their preview window with the gutter off regardless of the user's
global snacks `win.preview` config. `relativenumber` is pinned only because
snacks already defaults it off — the pin survives a future snacks default
change. Everything else about the preview window stays snacks' default;
only the line-number gutter is removed.

## Alternatives considered

### Why not turn the gutter off inside the preview callbacks (`ctx.preview:wo`)?

Snacks re-applies its resolved window-config options on every preview `reset`
(once per item change), so a per-callback nudge has to be repeated after every
fill and works against the config path. Declaring `win.preview.wo` once per
pick lets snacks itself create and keep the window number-free.

### Why not set `win.preview.minimal = true`?

That is snacks' own lever that also disables the number column (`number`
derives from `minimal ~= true`), but it additionally resolves the preview
window against snacks' minimal style, resetting window options wholesale — a
broader visual change than the reported gutter. The `wo` pin is the narrow
lever.

### Why not let the preview inherit the user's window options like the note float?

The [note-float decision](../feature/2026-09-04-note-float-follows-user-window-options.md)
inherits options because that float is the user's own editable surface, where
their `number`/`cursorline` are a fidelity cue. A Picker preview is a
plugin-owned read-only rendering of a terminal capture or template text: its
rows are not a file's lines, so a `number` gutter would display numbers that
refer to nothing. Deterministic off is the right default for this surface.

### Why not add a Vantage config option?

Every preview Vantage renders through snacks is this same kind of non-file
text, so there is no legitimate per-user case for the gutter; the reported gap
does not warrant widening the config surface.

## Consequences

- User-visible change for `picker = "snacks"`: the switch/kill/annotation
  picker previews no longer show a line-number gutter.
- The override is pick-scoped and un-overridable from the global snacks
  config (call opts merge last); a user who wants the gutter back would need
  a new Vantage option.
- Only `lua/vantage/picker/snacks.lua` changes. `native` has no preview and
  fzf-lua renders its preview in fzf's own terminal surface, so neither is
  affected.
- Presentation stays otherwise snacks-default (`cursorline`, highlights, …
  unchanged); the fix is a window option on the preview pane, never a change
  to buffers or items.

Rides the [pluggable-picker-frontend note](../architecture/2026-08-31-pluggable-picker-frontend.md):
each implementation owns its rendering, and snacks' preview window is Vantage's
own surface to configure.
