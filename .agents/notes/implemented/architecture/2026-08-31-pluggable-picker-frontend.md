# Agent Note: Pluggable Picker frontend — native / fzf-lua / snacks

Status: implemented

## Problem

Selection was hardwired to `vim.ui.select` in `picker.lua`, so every selection
flow (agent, tool, group, kill) was welded to Neovim's built-in UI. Users with
fzf-lua or snacks could get them only through a global `vim.ui.select` override
— no per-plugin choice, and no preview of an Agent's pane.

## Decision

The Picker is a pluggable Frontend interface that mirrors the Backend seam.
`lua/vantage/frontend/picker/init.lua` resolves the configured implementation
through a whitelist registry (a raw user string is never `require`d) and
exposes the `Picker.pick(spec, opts)` / `Picker.pick_plain(...)` facade. Each
implementation — `native`, `fzf-lua`, `snacks` — declares `preview` and
`command` capabilities and renders the same neutral `PickSpec`; selected via
`setup { picker = … }` (default `native`).

Flow-owned modules (`commands/attach.lua`, `commands/kill.lua`,
`commands/review.lua`) build rows and preview content; implementations own only
rendering, choice recovery, and the engine-specific binding of neutral Picker
commands. Preview content reaches the Backend through the Bridge, so the
Frontend never touches tmux directly.

- `native` drives `vim.ui.select` directly (respecting any global
  `vim.ui.select` override the user already has).
- `fzf-lua` drives `fzf_exec`; because fzf-lua returns display strings, entries
  carry a numeric prefix that round-trips the item index (the scheme fzf-lua's
  own ui_select shim uses), hidden from the list with `--with-nth=2..` alone —
  `--nth` is evaluated against the transformed line and would drop the entry's
  own first field.
- `snacks` drives `snacks.picker` with `format = "text"` and an explicit
  `picker:close()` in `confirm`.

Missing dependencies and unknown values now fail fast during `setup()`; the
composition root resolves the implementation once. See
[composition-root-and-neutral-seams](2026-09-10-composition-root-and-neutral-seams.md).

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
  above `picker/` changes. It declares `preview`/`command` capabilities and
  implements `pick`/`pick_plain`.
- The Backend interface exposes `capture_pane` (read-only, a few lines) so picker
  previews obey the "never touch tmux directly" invariant; it is a portable
  operation (zellij can snapshot a pane too).
- `native` still respects a global `vim.ui.select` override, so default behavior
  is unchanged for existing users.
- Item construction and preview content live in the command flows, and the
  pickers are pure renderers over a `PickSpec` — see
  [the picker-pure-renderers note](2026-09-05-picker-pure-renderers.md).

The Backend seam it mirrors is [the backend-driver-seam note](2026-08-31-backend-driver-seam.md); the single-Client Frontend it lives in is [the single-terminal-frontend note](2026-08-31-single-terminal-frontend.md).
