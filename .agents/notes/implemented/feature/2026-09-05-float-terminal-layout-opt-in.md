# Agent Note: Float terminal layout as an opt-in (statusline-free Client)

Status: implemented

## Problem

The Client's agent window showed a statusline row that carries nothing the
user acts on: `'laststatus'` is global (Nvim 0.12's default is 2, and
statusline plugins like lualine force 2/3 at setup), so every *tiled* window
owns a statusline row in its layout, terminal buffers included. In the agent
window that row renders a statusline plugin's content for a `vantage_terminal`
buffer — no filename to navigate, no mode to read. Disabling the filetype in
the plugin (lualine `disabled_filetypes.statusline`) only blanks the row's
*content*: the row itself is a layout slot (`w_status_height`, computed from
`laststatus` in `win_split`) and stays, wasting one terminal line. Neovim has
no per-window way to drop the row for a tiled window — `w_status_height == 0`
is float/global-statusline-only — so a pure-terminal agent view needed a
floating window.

## Decision

`cli.win.layout = "float"` is the layout that removes the meaningless
statusline row (it was removed in the [full terminal layout
change](2026-09-03-full-terminal-layout.md) and re-added here as an option);
the default is `float` — see the [float terminal layout default
note](2026-09-05-float-terminal-layout-default.md), which supersedes the
"default remains `full`" wording below. `cli.win.float = { width = 1.0,
height = 1.0, border = "none" }` extends the pre-removal option surface:
`width`/`height` are fractions of the editor area (0 < v <= 1), the window is
centered (`relative = "editor"`), clamps to at least 40 columns × 10 rows,
opens with `style = "minimal"`, and `border = false` maps to `"none"`.
`open_win` in `lua/vantage/client.lua` has a `float` branch again; every other
layout path is untouched.

The float is the one window where the meaningless row is really gone rather
than blanked: floating windows draw no statusline, and statusline plugins
skip them entirely — lualine's refresh excludes `win_gettype() == "popup"`
windows, which is what a plain float reports, so it never writes a
window-local statusline or winbar into the float. `Client.hide()` detects a
float via `nvim_win_get_config().relative ~= ""` and closes it directly; the
`enew` last-window fallback remains tiled-only, and stays reachable only for
tiled windows — Neovim refuses to close the last tiled window beneath a float,
so a float is never the session's only window.

## Alternatives considered

### Why not blank the statusline content in the tiled window instead?

That is what the statusline-plugin filetype disable already achieved (and
what the reporter had): the content goes, the row stays, because the row is
layout, not content. A window-local `statusline = ""` is not even guaranteed
blank — an empty local falls back to the *global* option value
(`stl = *wp->w_p_stl != NUL ? wp->w_p_stl : p_stl`), which is the
statusline plugin's own (blank for a disabled filetype, default content
otherwise). Neither reclaims the line.

### Why not make float the default again?

The per-frame terminal-cursor redraw inside floats on every Agent-TUI repaint
is exactly why the float layout was removed the first time; at the time of
this note the trade-off was opt-in and documented in the README and help text.
The default later moved to `float` anyway — see the [float terminal layout
default note](2026-09-05-float-terminal-layout-default.md): the flicker no
longer reproduced on the maintainer's setup, and `full` is kept as the
opt-out.

### Why not have Vantage set 'laststatus' 0/1 while the Client is open?

`laststatus` is global: 0/1 would remove statuslines (or their row) from every
other window and tab too, and statusline plugins re-assert 2/3 on every setup
and colorscheme change — a fragile fight over a user-owned option.

### Why not absolute float sizes (columns/rows)?

The prior `cli.win.float` surface was fraction-only; restoring it exactly
keeps the option vocabulary of the note that removed it coherent, and the old
fractions (0.9 / 0.9) read as "near full editor" at any window size. Absolute
sizes can be layered on later if someone asks.

## Consequences

- `cli.win.layout` accepts `full | left | top | bottom | right | float`; the
  `vantage.Win` type, the README sample, and `doc/vantage.nvim.txt` list
  `float` with its `cli.win.float` options and the flicker caveat. A stale or
  misspelled layout still falls through to the split path (bottom split).
- With `float`, the Client no longer owns a tab: `hide`/`toggle` closes the
  float directly, and the terminal reopens as a fresh float on `show`. The
  buffer `retitle` still runs — the name shows in other windows' bars and tabs
  when the buffer is displayed there; the float itself shows no winbar.
- The float's Agent view is free of statusline and winbar rows with any
  statusline plugin that skips floating windows (lualine does); a plugin that
  explicitly writes a window-local winbar into the float would still draw one.
- The [full-terminal-layout note](2026-09-03-full-terminal-layout.md) stays
  active: its flicker rationale still governs the default, and it carries the
  cross-link to this opt-in flip.
- Config note for the reporter: with `layout = "float"` the lualine
  `disabled_filetypes` entry for `vantage_terminal` is no longer needed
  (floats are already excluded); harmless to keep.
