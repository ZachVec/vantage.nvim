# Agent Note: Remove the marksman-based markdown gate

Status: implemented

## Problem

`make check` ran `scripts/verify-markdown.lua`, which drove the marksman LSP headlessly and reported "no diagnostics" whenever marksman published nothing. Investigation showed marksman never publishes its diagnostics in a headless Neovim process — its async `textDocument/publishDiagnostics` (and every other async notification) never reaches stdout, even via `vim.lsp.start_client` with full capabilities, while synchronous request/response works. The gate therefore reported a clean pass while checking nothing: a silent no-op.

## Decision

Remove the marksman-based link check. Delete `scripts/verify-markdown.lua` and the `make markdown` target (with its `MARKSMAN` tool lookup), and drop `markdown` from `make check`. Link correctness is left to marksman running interactively in an editor, where it does publish diagnostics.

## Alternatives considered

### Why not keep the gate and fix the headless invocation?

The failure is in marksman's .NET async notification delivery, not the gate's Lua: full client capabilities, graceful shutdown/exit, and Neovim's real LSP client all still yielded zero notifications headlessly. Fixing it would mean changing marksman itself (or its upstream), out of scope for this repo.

### Why not replace it with a hand-written Lua link checker?

A Lua checker would hard-code a subset of markdown link semantics and drift from marksman — the tool that actually reports these problems interactively. Keeping two divergent definitions of "broken link" is worse than not gating it in CI.

### Why not keep the gate as a best-effort check?

A gate that always passes is worse than no gate: it implies a guarantee it cannot deliver. Removing it makes the gap explicit.

## Consequences

- `make check` is now Agent Notes + stylua + lua-language-server; there is no markdown link gate.
- The prior markdown-gate note is rejected, since its rationale (marksman diagnostics before commit) no longer holds.

The rejected note is [markdown-gate-untracked](../../rejected/process/2026-08-31-markdown-gate-untracked.md).
