# Agent Note: The `files` lister is resolved once, at setup

Status: implemented

## Problem

`files` walked a preference chain at run time: it checked `executable` for
each program, ran the first one present, and gave way to the next when a run
failed before producing a line. The chain made the listing depend on when a
program happened to be probed, made a failure silently answer with a different
program's semantics (`find` reads no ignore files, so it lists what the project
ignores), and left the flow with recursion and partial-result branches for a
choice the user makes when installing software.

## Decision

`Gather.setup()` — called by the composition root with the other flow setups —
resolves the first of `fd`, `rg`, `find` that is executable and stores it. A
run uses that program only:

- A run failure reports `file listing failed (<name>)`; the flow does not try
  another program, and lines the run already produced stay listed.
- `rg --files`'s exit 1 stays an answer (an empty listing), not a failure.
- No program resolved answers `no file lister (fd, rg, or find)` when a run is
  attempted; setup itself succeeds, so `buffers` and every other feature are
  unaffected.
- Setup reads only `PATH`; installing a program or changing `PATH` means
  running setup again.

The listing root and the reference base are unchanged: candidates come from
the live Neovim global cwd
([the listing-root note](../bug-fix/2026-09-19-files-listing-root-is-neovim-cwd.md)),
and references are spelled against the Agent's Cwd.

## Alternatives considered

### Why not keep the run-time chain?

It is a fallback that can silently change the answer's semantics, and its
resolution is a hidden function of `PATH` at run time. Setup is the point the
plugin already resolves its pluggable implementations; the lister is the same
kind of choice.

### Why not resolve lazily on the first `files` call?

The first call would silently freeze whatever `PATH` held then, with no setup
boundary to point at — the same implicit dependence, moved.

### Why not probe `executable` on every run?

That leaves a program the user installed mid-session changing behavior without
a setup, and keeps the resolution logic (and its branches) in the flow.

## Consequences

- The streaming decision is unchanged — one asynchronous spawn, live batches,
  cancellable
  ([the file-listing note](../feature/2026-09-19-streaming-file-listing.md));
  only the chain and its fallback are gone.
- `tests/commands/gather_spec.lua` calls `Gather.setup()` after pinning `PATH`
  and covers preference order, no-fallthrough on failure, rg's empty answer,
  find alone, no lister, and re-resolution.
- README and `doc/vantage.nvim.txt` say the first present program is chosen
  when Vantage is set up.
