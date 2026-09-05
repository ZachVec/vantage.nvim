# Agent Note: Full (tab) terminal layout + terminal buffer title

Status: implemented

## Problem

The Client terminal's default window layout was `float` (`cli.win.layout =
"float"`, a rounded near-full-editor-size floating window), and typing inside
it flickered: on every Agent-TUI repaint the `:terminal` cursor redrew
mid-screen, jumping to the middle of the editor while the user typed. Neovim
redraws the terminal cursor per-frame inside floating windows, so a full-screen
float plus a repainting Agent TUI. The trigger was isolated to the float
itself — tmux, the Agent, and `termsync` were all verified innocent.
Separately, the terminal buffer carried no name (`[No Name]`), so tab labels
and winbars gave no hint of which Agent was focused or where it runs.

## Decision

`cli.win.layout` accepts `full | left | top | bottom | right` (plus `float`,
again). The `float` value and the `cli.win.float` options table were removed as
the default — `float` later returned as an opt-in (see the [float terminal
layout opt-in note](2026-09-05-float-terminal-layout-opt-in.md)) and then
became the default (see the [float terminal layout default
note](2026-09-05-float-terminal-layout-default.md)); this note's flicker
rationale still governs why `full` exists as the opt-out, but `full` is no
longer the default. `full` opens the Client
terminal in a dedicated tab — `tab split`
duplicates the current window into the new tab, then `nvim_win_set_buf` swaps
the terminal buffer in — giving one normal (non-floating) window at the full
editor size. Because no floating window is ever created for the terminal, the
per-frame cursor redraw that caused the flicker cannot occur. The split
layouts (`left | top | bottom | right`) are unchanged for users who want the
terminal alongside the current window.

`retitle()` in `lua/vantage/client.lua` names the terminal buffer on every
focus: `<tool> · <cwd>`, tool first (e.g. `claude · /home/zach/vantage`),
falling back from `agent.tool` to `agent.name` to `vantage`, and dropping the
`· <cwd>` suffix when the Agent has no working directory. The tab label and
winbar then show the focused Agent instead of `[No Name]`. It runs on both
focus paths: re-targeting an already-attached Client and attaching a fresh
one. The rename is per-focus only — nothing polls or mirrors `@agent-state`
for the title; that state is written by the Agent tool's external callback
script, and a dynamic title over it was explicitly deferred.

## Alternatives considered

### Why not keep the float as the default layout?

The floating window is the flicker trigger itself: Neovim redraws the
`:terminal` cursor per-frame inside floats, so every Agent-TUI repaint
relocated the cursor to the screen middle while typing. No float option
avoids that, so `float` was removed as the default rather than fixed in place
(an opt-in `float` layout returned later — [float terminal layout opt
in](2026-09-05-float-terminal-layout-opt-in.md) — and became the default,
[per the default note](2026-09-05-float-terminal-layout-default.md), with
this flicker as the documented trade-off for the `full` opt-out).

### Why not a maximized split?

Maximizing a split window did not deliver the full-size surface the float
provided — the result was wrong-sized (down to a 1-line sliver) rather than a
correct full-editor window — and it keeps split bookkeeping for a layout that
wants none. A dedicated tab gives a true full-editor-size normal window with
neither the float's cursor redraw nor a split sliver.

### Why not name the value `fullscreen`?

The layout is a normal window in a dedicated tab with ordinary tab semantics,
not a float-like fullscreen takeover, so `full` names the full-editor-size
window without overpromising a fullscreen mode.

### Why not a dynamic/polling title?

A live title would have to track `@agent-state`, which is written by the Agent
tool's external callback script — a new polling or mirroring mechanism over an
external write path. Deferred: the name already updates whenever the user
switches the terminal to another Agent, which is when the title matters.

## Consequences

- Config change: `layout = "float"` and `cli.win.float` were removed; the
  `float` layout was later re-added as an opt-in, see the [float terminal
  layout opt-in note](2026-09-05-float-terminal-layout-opt-in.md), and is the
  default now, see the [float terminal layout default
  note](2026-09-05-float-terminal-layout-default.md). An unknown layout value
  still silently falls through to the split path (a bottom split) rather than
  erroring; `vantage.Win` in `lua/vantage/config.lua`, the `README.md`
  sample, and `doc/vantage.nvim.txt` list
  `float | full | left | top | bottom | right` with `float` as the default.
- With `full` the terminal owns a tab: `hide`/`toggle` closes the terminal
  window, which also closes its tab when that window is the tab's only one
  (when the terminal window is the session's very last window, `hide` swaps in
  an empty buffer instead, per the pre-existing single-window rule). The
  buffer and tmux client survive, so the next `show` reopens the same terminal
  in a fresh dedicated tab.
- The buffer name can go stale only if an Agent's working directory changes
  between focuses; it never claims to track live Agent state.
- The Client stays the single re-targeted terminal of the
  [single-Client-terminal decision](../architecture/2026-08-31-single-terminal-frontend.md);
  this note only decides how that one window is presented and named.
