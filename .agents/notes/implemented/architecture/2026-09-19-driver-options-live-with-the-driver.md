# Agent Note: Driver options live with the Driver

Status: implemented

## Problem

`Config.options` is the shared option table every category reads, and it named
one multiplexer concept directly: `socket`, the tmux-private socket name. A
Driver is pure multiplexer mapping — tmux today, room for zellij later — and a
socket is a tmux idea, so the shared option table and the published
`vantage.Config` type both advertised a Driver's vocabulary as general.

The name was also spelled in three places: `config.lua`'s default, the tmux
Driver's `socket()` read, and fallback defaults inside the Driver's two
resources (`counts.sh`, `status.sh`). A user who configured a custom socket
could silently disagree with a hand-run resource script that had fallen back
to `vantage`.

## Decision

Driver-specific options live in `Config.options.backend_opts`, keyed by the
Driver's registry name:

- `setup { backend_opts = { tmux = { socket = "vantage" } } }` is the one
  user-facing spelling; `tmux.lua` reads it through its `socket()` helper.
- `backend/init.lua` states the convention at the seam: a Driver reads
  its own entry, and the shared option table names no multiplexer concept.
- The socket stays configurable and keeps the `vantage` default. It is the
  cross-process rendezvous key — every Neovim instance and every tmux
  invocation must resolve the same name — and the tmux Driver's suite uses it
  to run against a per-pid socket.
- Both Driver resources require `-L <socket>` rather than falling back to a
  hardcoded `vantage`. The plugin always passed it, so the fallback could only
  disagree with the configured name; a missing socket now fails with usage
  instead. `status.sh`'s calling convention for the future per-Agent lifecycle
  scripts takes it explicitly too.

## Alternatives considered

**Hardcode the socket in `tmux.lua` and delete the option.** The tempting
shape: if a socket is tmux-only, why is it in the shared table at all? It
removes a documented option (README, `doc/vantage.nvim.txt`,
`docs/architecture.md`) with no replacement, and it blocks the two things the
knob is for: a second, independent Vantage world on one machine, and test
isolation. `tmux_spec.lua` runs `kill-server` against its socket before
every test, so a hardcoded name would make `make test` kill the developer's
live server and every Agent in it. It would not even remove the knob — it
would move it to an undocumented test-only seam.

**Keep `socket` in the shared table and document it as tmux's.** The
`vantage.Config` type keeps a tmux word, and every future Driver inherits an
option it has no use for.

**A `backend_opts` bag without per-Driver keys.** The shared table then still
holds the word `socket`, which is exactly the concept this move removes.

## Consequences

- `setup { socket = … }` is gone; the knob is
  `setup { backend_opts = { tmux = { socket = … } } }`. README,
  `doc/vantage.nvim.txt`, and `docs/architecture.md` are updated in the same
  change.
- `vantage.Config` carries `backend_opts` instead of `socket`, and the Driver
  seam documents the convention instead of a Driver's vocabulary.
- A Driver resource invoked without `-L` exits 2 with a usage line rather than
  addressing the default socket.
- `tests/config_spec.lua` and `tests/backend/tmux_spec.lua` set and
  assert the nested option; the suite's isolation contract is unchanged.
