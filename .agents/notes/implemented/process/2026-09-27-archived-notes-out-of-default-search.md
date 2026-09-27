# Agent Note: Archived Agent Notes stay out of default search

Status: implemented

## Problem

Reading the notes tree is how an agent recovers the rationale behind the code,
and the active corpus grows by one note per non-trivial feature or bug fix. The
frozen [`archived/`](../../archived/AGENTS.md) tree keeps low-future-value
implemented notes out of the active corpus, but it still sits inside the
repository's default search path. A default `rg` for a symbol, path, or phrase
therefore matches stale archived facts alongside the current decision, and a
lexical match can surface the frozen snapshot first. History should be reachable
on purpose, not returned by accident.

## Decision

The archive is excluded from default repository search by a root `.rgignore`
whose only rule is `/.agents/notes/archived/`. Ripgrep honors it without any gate
or toolchain change, and `make notes` still walks `archived/` directly and keeps
enforcing the archive metadata, so nothing about the freeze is weakened.

[`.agents/notes/AGENTS.md`](../AGENTS.md) states the matching standing order:
read the active lifecycle tree for a decision, and treat `archived/` as frozen
history that is searched explicitly only when history is intentionally cited.

## Alternatives considered

### Why not leave the archive in default search?

Rejected because archived facts go stale by design and can outrank the current
decision on a lexical match — exactly the useless-context cost this change
removes. The frozen-archive decision already says a sealed note is not current
authority; leaving it in default results contradicts that in practice.

### Why not move the archive outside the repository?

Rejected because the archive is still a valid in-repo link target and the record
of history belongs in the repository. Hiding it from default search keeps it
discoverable without mixing it into active decision discovery, which is the same
trade-off the [bootstrap Agent Note](2026-08-31-agent-notes.md) accepted when it
kept a frozen tree.

### Why not delete archived notes instead of hiding them?

Rejected because archival exists precisely to retain historical evidence that a
delete would erase; the [frozen-archive boundary](../../archived/AGENTS.md) keeps
it without maintaining it.

## Consequences

- Default repository search no longer returns archived note bodies, so agents
  read the active corpus by default.
- Historical access now requires naming `archived/` explicitly, which is the
  intent rather than a regression.
- `.rgignore` is ripgrep's mechanism; an editor or tool that ignores it still
  sees the archive. The exclusion is a search default, not an access control.
- The bootstrap note's three deviations (single-language, no manifest, pure-Lua
  verification) are unchanged; this only bounds what default discovery returns.
