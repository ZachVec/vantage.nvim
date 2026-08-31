# Agent Note: tmux as the state store — no custom TUI

Status: implemented

## Problem

Vantage must run several long-lived coding agents, keep them alive after the editor view closes (headless), give each attached client its own display of the same agents, and pass keystrokes into them. A terminal multiplexer already solves persistence, rendering, and input for shell processes; the alternative was to build or embed a TUI.

## Decision

tmux is the state store, multiplexer, renderer, and input layer. The plugin drives a private tmux socket (`tmux -L <socket>`, default `vantage`, configurable via `setup { socket = … }`) and stores all domain state in tmux's own objects — session groups, windows, and window options like `@agent-cmd` / `@agent-cwd` / `@agent-name` / `@agent-tool`. There is no custom TUI: the only "UI" is a Neovim `:terminal` that attaches as a tmux client. Global tmux config (a `client-detached` hook, history limit, no status line) is applied idempotently once the server is running.

## Alternatives considered

### Why not a custom TUI?

It would reimplement terminal emulation, scrolling, input handling, and process lifetime — a large surface for no gain over a mature multiplexer.

### Why not Neovim's own `:terminal` + job control?

Process lifetime would couple to Neovim: agents would die or need re-parenting when the editor exits, and separate editor windows would not share one agent process.

### Why not another multiplexer (zellij)?

Plausible, but tmux 3.x is ubiquitous and already installed; zellij is deferred as a future Driver behind the Backend seam, not a second code path now.

## Consequences

- No TUI code to maintain; headless survival and client detach/attach come from tmux for free.
- The plugin is a thin domain layer over tmux: all state lives in tmux objects, so the Backend reconstructs it by listing sessions/windows rather than keeping its own store.
- The private socket isolates Vantage from the user's daily tmux server, so its hooks and options never touch unrelated sessions.

The mapping of that state onto tmux objects is [the Group/Anchor/Agent/View note](2026-08-31-group-anchor-agent-view.md); the choice to route every operation through a swappable driver is [the Backend seam note](2026-08-31-backend-driver-seam.md).
