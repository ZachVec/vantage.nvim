# Agent Note: Single re-targeted Terminal, pluggable picker, no default keymaps

Status: implemented

## Problem

The Frontend needs to display agents and let the user switch, create, and kill them, without committing to one picker backend or a terminal-per-agent layout.

## Decision

- Exactly one Neovim `:terminal` (filetype `vantage_terminal`) is the Terminal; focus re-targets that same terminal to the chosen Agent instead of opening new ones.
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
- How that one window is presented (`cli.win.layout`, default `float` — a full-editor-size borderless float; `full` is the dedicated-tab opt-out) is decided in the [float-terminal-layout-default note](../feature/2026-09-05-float-terminal-layout-default.md); its `<tool> · <cwd>` buffer title was removed in the [tmux pane border note](../feature/2026-09-06-tmux-pane-status.md).

The attachment lifecycle (terminal exists ⇔ its client is attached) is owned by
[the layered refactor note](2026-09-09-layered-frontend-backend-refactor.md).
