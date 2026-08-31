# Agent Note: Markdown gate checks untracked notes and docs

Status: implemented

## Problem

`make check` runs `scripts/verify-markdown.lua`, which enumerated Markdown files with `git ls-files "*.md"` — only files already tracked by git. A brand-new Agent Note or developer-docs page (written but not yet committed) was invisible to the gate, so a broken link or marksman diagnostic it introduced only surfaced after the first commit.

## Decision

The gate keeps its full tracked-`*.md` sweep and additionally enumerates untracked Markdown files under `.agents/` and `docs/` via `git ls-files --others --exclude-standard -- .agents/ docs/`, filtered to `*.md`. These two directories are the homes of Agent Notes and developer docs, where a new file is expected to be checked before it lands; untracked `.md` elsewhere stays out of scope.

## Alternatives considered

### Why not include every untracked `.md` in the repo?

Scratch Markdown outside `.agents/` and `docs/` is not part of the shipped docs and would add noise; scoping to the two doc homes keeps the gate targeted.

### Why not enumerate files from disk instead of git?

Disk enumeration would pull in `.gitignore`d and generated files and re-implements what `git ls-files` already answers; the two `git ls-files` calls (tracked + untracked) reuse git's own classification.

## Consequences

- A new (uncommitted) Agent Note or developer-docs page is linted by `make check`, so broken links and marksman diagnostics are caught before the first commit.
- The gate costs one extra `git ls-files` invocation; no runtime code changes.

The Agent Note system this gate complements is [the Agent Notes note](2026-08-31-agent-notes.md).
