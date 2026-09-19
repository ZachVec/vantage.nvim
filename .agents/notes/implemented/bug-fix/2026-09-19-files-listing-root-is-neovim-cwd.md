# Agent Note: `files` enumerates Neovim's cwd and spells references against the Agent's

Status: implemented

## Problem

`commands/gather.lua` passed one value — the Focus's cwd — to two different
questions. It was the lister's working directory, so `files` offered whatever
the Agent's repository contained, and it was the base the Picker and
`Config.tool_reference` relativized against, so the typed reference was a path
the Agent could resolve. When Agent and Neovim cwd were equal this was
invisible. When the user opened Neovim in another repository to reference its
files, the list stayed pinned to the Agent's repository and the files the user
was looking at were not offered at all — the flow enumerated the wrong tree
because the enumeration scope had been derived from the reference base.

## Decision

The two bases are split. `commands/gather.lua`'s `run` hands `Util.cwd()` —
Neovim's global cwd (`:cd`; not `:lcd`/`:tcd`), read once when the pick opens —
to the source's `stream`, and keeps `agent.cwd` for the reference alone:

- **Enumeration and display follow the tree the user is browsing.**
  `stream_files` lists under Neovim's cwd, and both sources build their entries
  with that same base, so `entries.file`/`entries.buffer`'s `cwd` parameter is
  a display base rather than the Focus's cwd. `buffers` changes with `files`
  because the two share the one-argument `stream(cwd)` shape; it has no listing
  root of its own.
- **The typed reference is unchanged.** Each chosen entry's `path` is absolute,
  and `Config.tool_reference(tool, agent.cwd, path)` still relativizes it
  against the Focus's cwd, falls back to the absolute path when it escapes, and
  passes the result through the Tool's `format` hook. In the disjoint-repository
  case every reference is therefore absolute.
- **Display and reference may disagree.** They answer different questions: the
  label names a file inside the listed tree, the reference is a path the Agent
  can resolve. With a nested Agent cwd the list shows `sub/b.lua` while `b.lua`
  is typed; with a disjoint tree the list shows `z.lua` while the absolute path
  is typed.

README, `doc/vantage.nvim.txt`, and `docs/architecture.md` state the Neovim-cwd
listing root and the relative/absolute reference rule.

## Alternatives considered

### Why not keep listing from the Focus's cwd?

That is the bug: it derives the enumeration scope from the reference base. The
user's tree is what `files` should offer, and the Agent's cwd is only where its
process happens to run; a Focus in a sibling repository must not make the
current repository unreachable.

### Why not display entries relative to the Agent's cwd, so the label equals the reference?

It keeps the "what you see is what is typed" reading, but it needs the source
stream to carry two bases — and `buffers` has no listing root to pair with the
second one. In the disjoint case it also turns the whole list into absolute
paths, right where a readable tree matters most. The display/reference split is
the accepted cost.

### Why not add a `gather.root` option?

There is one correct enumeration scope, and a config knob would need a default,
documentation, a health story, and an answer for which flows it governs — all
to let a user re-select the behaviour this change fixes. Add it when a second
real workflow needs the old root, not before.

### Why not skip the Tool's `format` hook when a path escapes?

The hook owns how a reference is spelled. Branching on "inside/outside" would
split that ownership across two code paths and take the dialect's decision about
an absolute path away from the dialect — Claude's `@/abs/path` is the hook's
business.

## Consequences

- `files` offers the tree of the Neovim instance that invoked it, even when the
  focused Agent lives in another repository; files inside the Agent's cwd are
  typed relative and everything else absolute.
- Picker labels no longer always equal the typed reference (identical trees stay
  equal, a nested Agent cwd differs, a disjoint tree is all absolute). The
  superseded facts live in
  [the file/buffer references note](../feature/2026-09-11-file-buffer-references.md)
  and [the streaming note](../feature/2026-09-19-streaming-file-listing.md),
  both updated in place.
- `tests/commands/gather_spec.lua` pins the split: a nested root expects
  `sub/b.lua` displayed with `b.lua` typed alongside the absolute sibling, and a
  disjoint root expects the absolute reference.
