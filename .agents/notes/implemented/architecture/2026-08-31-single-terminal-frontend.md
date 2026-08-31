# Agent Note: Single re-targeted :terminal client, pluggable picker, no default keymaps

Status: implemented

## Problem

The Frontend needs to display agents and let the user switch, create, and kill them, without committing to one picker backend or a terminal-per-agent layout.

## Decision

- Exactly one Neovim `:terminal` (filetype `vantage_terminal`) is the Client; focus re-targets that same terminal to the chosen agent instead of opening new ones.
- Selection goes through the pluggable [Picker](2026-08-31-pluggable-picker-frontend.md) (`native` / `fzf-lua` / `snacks`), chosen via `setup { picker = … }`.
- No keymaps are added by default, and `cli.tools` is empty — the user provides tools (`name → cmd array`) and keymaps via `cli.win.keys` or a `FileType` autocmd.

## Alternatives considered

### Why not one terminal per agent?

Buffer/window sprawl and no single "current agent" surface; re-targeting one terminal keeps one stable window.

### Why not a built-in fuzzy picker?

It would duplicate fzf-lua/snacks and fight user overrides; the pluggable Picker integrates fzf-lua/snacks natively instead.

### Why not ship default tools and keymaps?

Tool binaries and keybindings are user-specific and non-portable; empty defaults avoid guessing and avoid collisions.

## Consequences

- Free-text prompts (a new Group name) use `input()` directly, which is insert-mode by default.
- The terminal is created lazily on first focus and re-targeted thereafter; closing it detaches the client and destroys only its View.

The View lifecycle that the terminal attaches to is [the Group/Anchor/Agent/View note](2026-08-31-group-anchor-agent-view.md).
