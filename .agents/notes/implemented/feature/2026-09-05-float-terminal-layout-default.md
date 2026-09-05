# Agent Note: Float terminal layout is the default

Status: implemented

## Problem

The opt-in float Client (see the [float terminal layout opt-in
note](2026-09-05-float-terminal-layout-opt-in.md)) is the only layout that
removes the meaningless statusline row from the agent view — and on the
maintainer's daily setup (nvim 0.12.3, claude and codex TUIs) the cursor
flicker that originally drove floats out of the default (see the
[full-terminal-layout note](2026-09-03-full-terminal-layout.md)) no longer
shows. The default was therefore the *only* layout that still shows an empty
statusline row by default, despite the float being the statusline-free one
people want. The defaults carried over from the float era are also needlessly
chrome-heavy: 0.9 × 0.9 of the editor with a rounded border leaves margins and
a border around a window whose whole point is to be a pure terminal.

## Decision

`cli.win.layout = "float"` is the default again, with
`cli.win.float = { width = 1.0, height = 1.0, border = "none" }`:
`width`/`height` are fractions of the editor area (0 < v <= 1, unchanged from
the opt-in surface), 1.0 fills it, and `border = "none"` removes the surrounding
chrome; the `full` layout stays available as the opt-out for users who see the
float's per-frame terminal-cursor redraw flicker. Nothing else moves: the
default-flip is a default change plus docs; the float's open/hide/show
mechanics and the [snacks focus fix](../bug-fix/2026-09-05-float-terminal-switch-loses-focus.md)
are unchanged, and split layouts keep their statusline-row limitation
(`'laststatus'` >= 2 gives every tiled window one).

## Alternatives considered

### Why not keep `full` as the default?

`full` was default only because of the flicker observation recorded in the
2026-09-03 note; that observation no longer reproduces on the setup the note
was written against, so the default no longer has its justification. `full` is
one line of config away for anyone who still sees the flicker, and the
rationale stays in the notes instead of the default.

### Why not keep `width = 0.9, height = 0.9, border = "rounded"`?

Those were carry-overs from the pre-2026-09-03 float surface. The default
float's reason to exist is the pure-terminal view; a 10% margin and a border
are exactly the chrome that view exists to remove, and they cost the agent
TUI about two text rows and a screen-width column. Users who want a smaller,
bordered float still have `cli.win.float`.

### Why not accept absolute sizes now (columns/rows)?

The fraction surface is established and satisfies "fill the editor" with a
single 1.0; accepting absolute values as well would change the option
contract in the same change as the default flip for no requirement. Left for a
future ask.

## Consequences

- New installs and setups without an explicit `layout` now get the
  full-size, borderless floating Client; an existing `layout = "full"` (or
  `"full"`-style mnemonic) keeps the tab layout. A stale `layout = "float"`
  string from the pre-opt-in era is no longer a fall-through to the split
  path — it is the default mode.
- README.md, doc/vantage.nvim.txt, and the `vantage.Win` defaults in
  `lua/vantage/config.lua` describe float as the default with the flicker
  caveat and `full` as the opt-out.
- The [opt-in note](2026-09-05-float-terminal-layout-opt-in.md) stays active
  with its facts updated (the default it recorded was itself changed, in this
  same change, before any release); the
  [full-terminal-layout note](2026-09-03-full-terminal-layout.md) stays active
  carrying the flicker rationale and the retitle decision — its "full is the
  default" phrasing is superseded and cross-linked here, its retitle decision
  is not.
