# Vantage Architecture

A coding-agent manager built as a Neovim plugin. Its [Backend](glossary.md#backend) is a Lua domain layer over a pluggable multiplexer [Driver](glossary.md#driver) (tmux today, room for zellij later); its [Frontend](glossary.md#frontend) is the plugin's own UI — a pluggable [Picker](glossary.md#picker) (`native` / `fzf-lua` / `snacks`) plus a single `:terminal` that is the [Client](glossary.md#client). tmux is the state store, multiplexer, renderer, and input layer; there is no custom TUI.

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

- The **Backend** is a pluggable interface: a concrete **Driver** (tmux today, zellij later) implements it, selected via `setup { backend = … }`. Callers go through `Backend.get()` and never touch tmux directly — the Client's attach command (`client_command`) and the health check (`health`) are Backend methods too; the Backend never infers context — cwd, group, and target are passed in explicitly.
- The **Frontend** operates exactly one **Client** (the single `:terminal`), re-targeted with each switch, and selects through the **Picker**, a pluggable interface of its own: a picker implementation (`native` / `fzf-lua` / `snacks`) is chosen via `setup { picker = … }` and resolved through `Picker.get()`. A frontend orchestrator (`lua/vantage/select.lua`) builds the items and assembles a `PickSpec` per flow — the items to render, preview content (pane previews go through the Backend `capture_pane`, so the Frontend never touches tmux directly), the prompt glyph, an environment fact, and any in-flight action — and the implementations stay presentation-only: they depend on nothing but their engine, render the spec, deliver the chosen value through the positional `on_choice`, and report an empty list through a boolean return. The Agent list, the kill list, the annotation picker, the Agent-creation wizard (Tool then Group), and `:Vantage prompt` all pick through this seam (the last two via the plain-select form `pick_plain`); only `native` calls `vim.ui.select`, the environment's renderer by definition. Light Yes/No confirmations use Neovim's built-in confirm dialog.
