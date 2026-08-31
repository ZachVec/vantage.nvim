# Agent Note: Pluggable Picker frontend — native / fzf-lua / snacks

Status: implemented

## Problem

Selection was hardwired to `vim.ui.select` in `picker.lua`, so every selection
flow (agent, tool, group, kill) was welded to Neovim's built-in UI. Users with
fzf-lua or snacks could get them only through a global `vim.ui.select` override
— no per-plugin choice, and no preview of an Agent's pane.

## Decision

The Picker is a pluggable Frontend interface that mirrors the Backend seam.
`lua/vantage/picker/init.lua` resolves the configured implementation through a
whitelist registry (a raw user string is never `require`d) and exposes
`Picker.get()`. Each implementation — `native`, `fzf-lua`, `snacks` — exposes
the same five domain pickers (`pick_agent`, `pick_tool`, `pick_group`,
`pick_kill`, `pick_prompt`) with identical callback contracts, selected via
`setup { picker = … }` (default `native`). Callers go through `Picker.get()`.

Shared item construction lives in `picker/items.lua`: it builds rich items
(each carrying a `text` display string plus the domain fields a callback needs)
and owns the free-text Group prompt. Implementations own only rendering and
choice recovery; `fzf-lua` and `snacks` render an Agent's pane preview through a
new Backend method `capture_pane(target, max_lines)`, so the Frontend never
touches tmux directly.

- `native` drives `vim.ui.select` directly (respecting any global
  `vim.ui.select` override the user already has).
- `fzf-lua` drives `fzf_exec`; because fzf-lua returns display strings, entries
  carry a numeric prefix that round-trips the item index (the scheme fzf-lua's
  own ui_select shim uses).
- `snacks` drives `snacks.picker` with `format = "text"` and an explicit
  `picker:close()` in `confirm`.

Missing dependencies and unknown values fall back to `native` with a warning on
first use (lazy `require`, so the picker plugin is never eager-loaded).

## Alternatives considered

### Why not keep calling `vim.ui.select` and only register the third-party shim?

It leaves the plugin welded to `vim.ui.select` and subject to whichever global
override is installed, contradicting a per-plugin `picker` choice; least code,
but not an abstraction.

### Why not a generic `select(items, opts, on_choice)` primitive?

It is the smallest seam, but preview and other per-picker presentation would
have to leak through the shared `opts`, imposing one preview contract across
pickers with very different preview mechanisms (and one — native — with none).
Domain-level `pick_*` functions give each implementation its own presentation
vocabulary.

### Why not share `display`/`from_display` helpers in the items module?

They are fzf-lua-specific glue (the only string-only picker); keeping them
inside `fzf_lua.lua` leaves the shared items module presentation-free.

## Consequences

- A new picker implementation adds one module and one registry entry; nothing
  above `picker/` changes.
- The Backend interface gains `capture_pane` (read-only, a few lines) so picker
  previews obey the "never touch tmux directly" invariant; it is a portable
  operation (zellij can snapshot a pane too).
- `native` still respects a global `vim.ui.select` override, so default behavior
  is unchanged for existing users.

The Backend seam it mirrors is [the backend-driver-seam note](2026-08-31-backend-driver-seam.md); the single-Client Frontend it lives in is [the single-terminal-frontend note](2026-08-31-single-terminal-frontend.md).
