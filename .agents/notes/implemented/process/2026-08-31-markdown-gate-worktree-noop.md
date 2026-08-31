# Agent Note: Markdown gate hard-fails on marksman single-file mode

Status: implemented

## Problem

`make markdown` (via `scripts/verify-markdown.lua`) drives marksman headlessly and reports "no diagnostics" whenever marksman publishes nothing. Marksman only treats a folder as a real workspace when it contains a VCS directory (`.git`/`.hg`/`.svn`/`.jj`) or a `.marksman.toml` file — see `Folder.isRealWorkspaceFolder`. A git worktree stores `.git` as a *file* (`gitdir: …`), so marksman logs "Workspace folder is bogus", indexes zero notes, and falls back to single-file mode, which skips all cross-file link checks. The gate then reported a clean pass while checking nothing, letting an ambiguous `README.md` link through.

## Decision

1. Track a `.marksman.toml` marker at the repo root. It is a regular file present in every checkout (including worktrees), so marksman accepts the folder as a real workspace and performs cross-file link resolution there too.
2. Harden `scripts/verify-markdown.lua`: after marksman initializes, if its stderr contains `Workspace folder is bogus`, fail the gate (exit 1) instead of reporting a clean pass — a check that did nothing must not pass.

## Alternatives considered

### Why not run the gate only from the main checkout?

Changes are regularly made inside `git worktree`s (as in this change and the ones before it); a gate that only works in the main checkout would silently skip the exact environments where changes are actually made. A marker file fixes every checkout uniformly.

### Why not detect `.git`-is-a-file directly in the gate?

That couples the gate to git worktree internals and only catches one reason marksman rejects a folder (a scratch directory without any marker is another). Matching marksman's own `bogus` log line detects the actual failure regardless of cause.

### Why not send a richer LSP handshake to force diagnostics?

The degradation is workspace detection, not a missing client capability, so the marker plus the hard-fail addresses the confirmed cause. Headless diagnostic publishing remains a separate open question if it proves necessary.

## Consequences

- The markdown gate now checks links in worktrees, and fails loudly if marksman ever drops back to single-file mode instead of silently passing.
- `.marksman.toml` is a comment-only config marker; marksman reads it as an empty config and keeps its defaults.

The gate this hardens is [the markdown-gate-untracked note](2026-08-31-markdown-gate-untracked.md).
