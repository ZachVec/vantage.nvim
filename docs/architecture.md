# Vantage Architecture

A coding-agent manager built as a Neovim plugin. Its [Backend](glossary.md#backend) is a Lua domain layer over a pluggable multiplexer [Driver](glossary.md#driver) (tmux today, room for zellij later); its [Frontend](glossary.md#frontend) is the plugin's own UI — a vim.ui.select [Picker](glossary.md#picker) plus a single `:terminal` that is the [Client](glossary.md#client). tmux is the state store, multiplexer, renderer, and input layer; there is no custom TUI.

Terminology lives in the [glossary](glossary.md); this file describes how the pieces relate and the invariants that hold them together.

## The tmux substrate

tmux is the state store, multiplexer, renderer, and input layer; there is no custom TUI. The plugin drives a private socket (`tmux -L <socket>`, default `vantage`) and keeps all domain state in tmux objects — session groups, windows, and window options (`@agent-cmd`, `@agent-cwd`, `@agent-name`). Global tmux config (a `client-detached` hook, history limit, no status line) is applied idempotently once the server is running.

## Domain model over tmux

The [domain terms](glossary.md) map onto tmux objects:

- A **Group** is a tmux *session group*: one persistent **Anchor** session owns the Agents, plus transient **Views** grouped with it. The Anchor keeps the Group alive even when no View is attached; a Group is destroyed only by `kill <group>`.
- An **Agent** is a tmux window marked with `@agent-cmd` / `@agent-cwd` / `@agent-name`, shared across the Group's Views.
- A **View** is a transient session marked `@vantage-view 1`; a global `client-detached` hook destroys a View when its client detaches, so Views never accumulate. When all of a Group's Agents die, the Anchor and every View die with it.

Creating the first Agent uses `new-session` (which also starts the server and applies config); later Agents use `new-window -t <view>` to join the existing group. Attach creates a new grouped session and re-targets it at the chosen window.

## Layering and seams

- The **Backend** is a pluggable interface: a concrete **Driver** (tmux today, zellij later) implements it, selected via `setup { backend = … }`. Callers go through `Backend.get()` and never touch tmux directly; the Backend never infers context — cwd, group, and target are passed in explicitly.
- The **Frontend** operates exactly one **Client** (the single `:terminal`), re-targeted with each switch, and selects through the **Picker** (`vim.ui.select` today, swappable for fzf-lua / snacks / …).
