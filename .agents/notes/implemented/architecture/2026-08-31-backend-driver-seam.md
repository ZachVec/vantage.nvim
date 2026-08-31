# Agent Note: Pluggable Backend interface — tmux driver today, zellij later

Status: implemented

## Problem

The multiplexer choice (tmux) should not be welded into every call site, or a future zellij backend becomes a rewrite. But abstracting prematurely over an unknown second implementation risks a leaky, speculative interface.

## Decision

The Backend is a thin interface: `lua/vantage/backend/init.lua` resolves `require("vantage.backend." .. config.backend)` and exposes one surface (`list`, `groups`, `create`, `attach`, `select_window`, `kill`, `status`, `ensure_server`, `has_session`, `capture_pane`, `client_command`, `health`). `tmux` is the only driver today and owns all domain logic. Callers never touch tmux directly — `commands.lua`, `picker.lua`, `client.lua`, and `health.lua` go through `Backend.get()`. The Backend never infers context: cwd, group, and target are passed in explicitly.

## Alternatives considered

### Why not hardcode tmux calls everywhere?

It would make a later seam migration a rewrite; the one-line dispatch is nearly free and costs nothing today.

### Why not a deeper abstraction (pluggable capabilities, a generic process model)?

With one known driver there is nothing yet to share. The surface is small enough to re-derive when a second driver actually appears.

## Consequences

- A new driver implements the same module surface and is selected by `setup { backend = "zellij" }`; nothing above `backend/` changes.
- The interface is the de-facto contract; it grows when a second driver needs a method, or when a Frontend/health need (`capture_pane`, `client_command`, `health`) must not bypass the "never touch tmux directly" invariant.

The tmux driver's object model is documented in [the state-store note](2026-08-31-tmux-as-state-store.md).
