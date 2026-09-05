# Agent Note: Annotations — note float follows user window options

Status: implemented

## Problem

The note float (the editable scratch window behind `:Vantage annotate` and the
`annotate list` picker action) was opened with Neovim's `style = "minimal"`:
Nvim then forces `number`, `relativenumber`, `cursorline`, `cursorcolumn`,
`signcolumn`, `foldcolumn`, `spell`, `list`, `colorcolumn` and friends off
regardless of the user's config. The float therefore never shows the user's
line numbers and looks like a read-only dialog — the opposite of what it is.
The [annotations note](2026-09-01-annotations.md) frames the float as "a plain
scratch buffer … so editing is ordinary Vim", and a user's first-glance cue
that it *is* an editable buffer (their line numbers, their cursorline) was
exactly what `minimal` removed.

## Decision

The note float takes its window options from the window it opens from, like a
normal split, unless the user opts out:

- New config: `annotations.float.style`, defaulting to `"inherit"`.
- `"inherit"` (default) passes **no** `style` key to `nvim_open_win`, so Nvim's
  default applies: the float's window-local options are taken from the window
  it opens over (falling back to global values where that window has no local
  override). Line numbers, relativeness, cursorline, signcolumn, `list`,
  `spell`, … follow the user's config, so the float reads as an editable
  buffer at a glance.
- `"minimal"` keeps the previous behavior: `nvim_open_win` receives
  `style = "minimal"`, forcing the clean dialog look (those options off).
- The two documented values are the contract. `"minimal"` is the only special
  value in code; any other value (including a stray empty string) behaves as
  `"inherit"` — the empty Nvim style is an implementation detail never exposed
  to users.

Geometry (centered `rounded` border, `width`/`height` formulas) and the
title/footer text stay in the note editor (`vantage.ui.note`); only the
window-option behavior changed. Scope stays at `annotations.float` so later
window-option keys have a home.

## Alternatives considered

### Why not keep `style = "minimal"` unconditionally?

A dialog look is a choice about *other* people's config. The float is a real
editing surface (multi-line, undo, the user's own keymaps) and the plugin
already documents it as one; its presentation should say so. Users who prefer
the dialog look can still set `float.style = "minimal"` explicitly.

### Why not a boolean, e.g. `annotations.float.minimal = true`?

A two-value enum with an explicit `"inherit"` default reads better in the
config block and in docs than an inverted boolean whose default is implied
(`minimal = false` says nothing about what *is* used). The enum also mirrors
the Nvim vocabulary (`style`) while hiding Nvim's bare empty-string value.

### Why not let the user pass Nvim's value through (`style = ""`)?

An empty string as a *configured* value is ambiguous (unset vs deliberate) and
makes "no special style" a spelling users must know. `"inherit"` names the
semantics; the code translates it to omitting the key.

### Why not copy options from the *source buffer* or follow only globals?

Copying buffer options is impossible across buffers (the float is a fresh
scratch buffer with no filetype) and following only globals would ignore the
per-window local values the anchor window actually shows — which is the look
the user just saw when they picked the range. Inheriting the anchor window is
what a split does and needs no option list to maintain.

### Why not also make geometry configurable now?

The reported gap was window options (line numbers at minimum). Border, size,
and title/footer were never part of it; adding keys nobody asked for would
widen the config surface and this note. `annotations.float` is the future home
if geometry follows.

## Consequences

- Behavior change for existing installs: the default note-float look flips
  from always-minimal to inheriting the user's window options, so line numbers
  and cursorline appear when the user's windows have them. Restoring the old
  look is one line: `annotations.float.style = "minimal"`.
- New public config key `annotations.float.style` ("inherit" default |
  "minimal"); defaults, LuaLS classes, README, and `doc/vantage.nvim.txt` are
  updated in this change.
- Only `ui/note.lua` (`Note.open`), `commands/annotation.lua`, and `config.lua`
  change in code; the
  picker previews and the range tint in the source window are unaffected.
- The float is a fresh scratch buffer, so buffer-local look (filetype
  formatting, `tabstop`, …) still does not follow the annotated file — only
  window options do. Noted as a boundary, not a regression.
- Follows but does not supersede the [annotations note](2026-09-01-annotations.md);
  the two stay cross-linked.
