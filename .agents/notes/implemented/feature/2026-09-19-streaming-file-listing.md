# Agent Note: The file listing is a live stream

Status: implemented

## Problem

`files` built its whole list before the picker saw any of it: `Util.run`
(`vim.system(...):wait()`) blocked the editor on `fd`/`rg`, the result was
sorted, and only then was the list handed over. The picker seam could render a
stream by then ([picker-two-interfaces](../architecture/2026-09-18-picker-two-interfaces.md)),
but the one flow with a genuinely large list still emitted a single batch at the
end — nothing to render while the lister ran, and nothing to cancel when the
pane closed. The Lua walk behind fd and rg existed only for machines with
neither, duplicated the `.git` skip, sorted, and was slow enough to be the
reason nobody wanted it invoked.

## Decision

The `files` source is live. One lister is resolved at setup — the first of
`fd`, `rg`, `find` that is installed — and invoked in Neovim's global cwd — the
listing root, not the Agent's
([the listing-root note](../bug-fix/2026-09-19-files-listing-root-is-neovim-cwd.md))
— with one exclusion:

```sh
fd --type f --type l --color never -E .git
rg --files --no-messages --color never -g '!.git'
find . -type f -not -path '*/.git/*'
```

`find` is the last in preference order and the crudest: it reads no ignore
files, so a machine with only find lists what find sees (fd and rg both honour
`.gitignore`). No `fdfind` alias, no `.jj` exclusion, no Windows guard — Vantage
drives tmux, so the lister assumes POSIX tools (and Windows' `find.exe` is a
different program, which is why snacks guards it). The resolved program is used
for every later run; picking it once is
[the setup-time lister note](../architecture/2026-09-28-file-lister-resolved-at-setup.md).

Exit codes decide what a result means, because the three tools disagree:

| lister | listed files | no files | error |
|---|---|---|---|
| `fd` | 0 | 0 | 1 |
| `rg --files` | 0 | **1** | 2 |
| `find` | 0 | 0 | 1 |

`rg`'s 1 is an answer, not a failure — a project whose files are all ignored
must read empty rather than as an error. A lister that fails reports its
failure and stays with whatever it already emitted; nothing is retried with
another program. A process killed by a signal reports `128 + N` rather than
`vim.system`'s `code = 0`, so a truncated run is a failure. Nothing installed
answers `no file lister (fd, rg, or find)` when a run is attempted; a failing
lister answers `file listing failed (<name>)`; an empty successful listing is
not a failure and warns about nothing.

The listing is rendered in the lister's own order — the sort is gone, and `find`'s
leading `./` is normalized away.

`Util.run_lines(cmd, opts, on_lines, on_done)` is the one asynchronous spawn:
it splits stdout into complete lines per chunk (a partial tail is carried and
flushed before `on_done`), calls `on_lines` with a chunk's lines so a batch stays
a batch, reports the exit code (or the signal's `128 + N`, or `-1` when the
child cannot be spawned at all — `vim.system` raises on a bad cwd or a missing
binary), and returns a cancel that sends SIGTERM, then SIGKILL after 200ms
(`snacks.picker.source.proc`'s shape). The flow returns that cancel from its
source, so closing the pane — or a command refreshing it — stops the lister; a
cancelled run's late `on_done` is ignored by the source.

`fzf-lua`'s adapter now hands each emitted batch to fzf-lua's `on_write` table
callback: one pipe write per batch instead of one per entry, which is the write
pattern `emit(chunk)` was shaped for.

`buffers` is unchanged: it reads memory and emits one batch.

## Alternatives considered

### Why not keep the Lua walk as the last resort?

It was the reason a machine with none of the three programs still got a
listing, but it was also a second listing implementation with its own semantics
(it resolved symlinks to files, sorted, and could not be cancelled), and `find`
does the same job in one line of argv. Dropping it costs the machine with none
of the three listers installed its listing; that machine gets a warning instead
of a silent, slow scan.

### Why not sort the listing?

Sorting needs the whole list, which is exactly what streaming does not have.
fzf-lua and snacks rank by their own matcher, and the order a lister prints is
at least honest about where the entries came from; a stable order was never
promised in the user docs.

### Why not treat every non-zero exit code as a failure?

`rg --files` exits 1 when it found no files. Treating that as a failure would
report an error for a project whose files are all ignored. The code is read per
lister instead.

### Why not fall back to the next lister when the chosen one fails?

Entries already on screen are real paths under Neovim's cwd; retracting them
to try a cruder lister would trade a partial answer for a different one. The
setup-time choice (see
[the setup-time lister note](../architecture/2026-09-28-file-lister-resolved-at-setup.md))
settles the question before the run: a program that fails reports the failure
instead of silently answering with `find`'s ignore-blind listing.

### Why not hand over one line per callback?

Because a batch is what the seam emits and what fzf-lua writes in one pipe
write: splitting a chunk into per-line callbacks would put one `uv.write` per
file back on the hot path of a 100k-file listing.

## Consequences

- Under `fzf-lua` and snacks the list fills in while the lister runs, and
  closing the pane (or pressing a command that refreshes) kills the child.
  `native` still waits for the whole listing before it opens its select — the
  pre-change behaviour, now the cost of a picker with no stream surface.
- `commands/gather.lua` loses `walk`, `list_files`, and `file_items`; its two
  sources are `stream_files` (the resolved lister) and an in-memory buffers
  batch.
- `Util.run_lines` joins `Util.run` in `util.lua`; the synchronous runner stays
  for the tmux driver.
- README, `doc/vantage.nvim.txt`, and `docs/architecture.md` describe the
  lister as the first of fd, ripgrep, and find installed when Vantage was set
  up; `docs/gotchas.md` records the exit-code table, the ignore-file
  difference, find's precedence trap, `vim.system`'s signal reporting, and the
  interruptible-wait requirement for a TERM-trapping script.
- The user-facing wording of the stream is scoped to the pickers that have a
  stream surface: README and `doc/vantage.nvim.txt` say `fzf-lua`/`snacks` fill
  the list in as the lister prints, so `Esc` stops a long listing, while
  `native` waits for the whole listing before it opens.
- Two defects the streaming shape exposed are fixed and pinned separately: a
  notification raised from the lister's exit callback must reach the main loop
  ([note](../bug-fix/2026-09-19-notify-reaches-the-main-loop.md)), and snacks'
  abort of a superseded run must not stop the fresh one
  ([note](../bug-fix/2026-09-19-snacks-abort-is-scoped-to-its-run.md)).
- The gather spec drives the resolved lister with fake listers on `PATH`
  (preferring fd, a failure that does not fall through, a failure after a line,
  rg's empty answer, find alone, no lister at all, re-resolution on setup, and
  a cancelled run), `tests/util_spec.lua` covers
  `run_lines`'s splitting, flush, failure code, and cancel, and
  `tests/helpers.lua`'s `entries(spec)` now waits for a live source instead of
  asserting it finished synchronously.
- `make check` and `make test` pass (148 cases).
