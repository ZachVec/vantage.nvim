# Agent Note: Pluggable Backend interface — tmux driver today, zellij later

Status: implemented

## Problem

The multiplexer choice (tmux) should not be welded into every call site, or a future zellij backend becomes a rewrite. But abstracting prematurely over an unknown second implementation risks a leaky, speculative interface.

## Decision

The Backend is a thin interface: `lua/vantage/backend/driver/init.lua` resolves the driver through a `REGISTRY` whitelist, with `setup()` failing fast on an unknown or unavailable implementation. `backend/bridge.lua` exposes the domain surface (`agents`, `create`, `retarget`, `send`, `capture`, `attach_command`, `kill_agent`, `kill_group`, `status`) and passes Driver results/errors through. `tmux` is the only driver today and owns all multiplexer mapping. Callers never touch tmux directly. The Backend never infers context: cwd, group, and the opaque Agent id are passed in explicitly.

## Alternatives considered

### Why not hardcode tmux calls everywhere?

It would make a later seam migration a rewrite; the one-line dispatch is nearly free and costs nothing today.

### Why not a deeper abstraction (pluggable capabilities, a generic process model)?

With one known driver there is nothing yet to share. The surface is small enough to re-derive when a second driver actually appears.

## Consequences

- A new driver implements the same module surface and is selected by `setup { backend = "zellij" }`; nothing above `backend/` changes.
- The interface is the `vantage.Driver` LuaLS contract; it grows when a second driver needs a method, or when a Frontend/health need must not bypass the "never touch tmux directly" invariant. Current result/error semantics are owned by [composition-root-and-neutral-seams](2026-09-10-composition-root-and-neutral-seams.md).

The tmux driver's object model is documented in [the state-store note](2026-08-31-tmux-as-state-store.md).
