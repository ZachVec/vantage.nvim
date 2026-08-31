# Agent Note: Single re-targeted :terminal client, vim.ui.select picker, no default keymaps

Status: implemented

## Problem

The Frontend needs to display agents and let the user switch, create, and kill them, without committing to one picker backend or a terminal-per-agent layout.

## Decision

- Exactly one Neovim `:terminal` (filetype `vantage_terminal`) is the Client; focus re-targets that same terminal to the chosen agent instead of opening new ones.
- Selection goes through `vim.ui.select`, so any `vim.ui` override (dressing, snacks, telescope-ui-select, fzf-lua, …) applies; the module boundary (`picker.lua`) is the future swap seam.
- No keymaps are added by default, and `cli.tools` is empty — the user provides tools (`name → cmd array`) and keymaps via `cli.win.keys` or a `FileType` autocmd.

## Alternatives considered

### Why not one terminal per agent?

Buffer/window sprawl and no single "current agent" surface; re-targeting one terminal keeps one stable window.

### Why not a built-in fuzzy picker?

It would duplicate fzf-lua/snacks and fight user overrides; `vim.ui.select` defers to whatever the user already installed.

### Why not ship default tools and keymaps?

Tool binaries and keybindings are user-specific and non-portable; empty defaults avoid guessing and avoid collisions.

## Consequences

- Free-text prompts (a new Group name) use `input()` directly, which is insert-mode by default.
- The terminal is created lazily on first focus and re-targeted thereafter; closing it detaches the client and destroys only its View.

The View lifecycle that the terminal attaches to is [the Group/Anchor/Agent/View note](2026-08-31-group-anchor-agent-view.md).
