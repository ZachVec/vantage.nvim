# Agent Note: Markdown gate checks untracked notes and docs

Status: rejected — the marksman markdown gate was a headless no-op and is removed

## Problem

`make check` ran `scripts/verify-markdown.lua`, which enumerated Markdown files with `git ls-files "*.md"` — only files already tracked by git. A brand-new Agent Note or developer-docs page (written but not yet committed) was invisible to the gate, so a broken link or marksman diagnostic it introduced only surfaced after the first commit.

## Proposal

Keep the full tracked-`*.md` sweep and additionally enumerate untracked Markdown files under `.agents/` and `docs/` via `git ls-files --others --exclude-standard -- .agents/ docs/`, filtered to `*.md`, so a new file is checked before it lands.

## Alternatives considered

### Why not include every untracked `.md` in the repo?

Scratch Markdown outside `.agents/` and `docs/` is not part of the shipped docs and would add noise; scoping to the two doc homes keeps the gate targeted.

### Why not enumerate files from disk instead of git?

Disk enumeration would pull in `.gitignore`d and generated files and re-implements what `git ls-files` already answers; the two `git ls-files` calls (tracked + untracked) reuse git's own classification.

The gate this proposal extended was removed: marksman never publishes its diagnostics in a headless Neovim process, so `verify-markdown.lua` reported a clean pass while checking nothing. See [remove-marksman-gate](../../implemented/process/2026-08-31-remove-marksman-gate.md).
