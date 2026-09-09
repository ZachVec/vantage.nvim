# Agent Note: Vantage mini.test suite

Status: implemented

## Problem

Vantage shipped with no automated tests. The highest-risk surface — the tmux
Driver's domain operations and the pure Lua helpers around config, prompts,
annotations, and picker row assembly — had no regression net, and
`AGENTS.md` still described a future suite rather than a current one.

## Decision

Adopt a snacks.nvim-style headless suite:

- `tests/minit.lua` bootstraps lazy.nvim in an isolated `.tests/` stdpath and
  installs the test-only dependencies (`mini.test`, `luassert`, `say`) on first
  run. `scripts/test` and `make test` run every `tests/**/*_spec.lua` through
  `nvim --headless -l tests/minit.lua --minitest`.
- Specs use mini.test's busted-style `describe`/`it` with `luassert`
  assertions, mirroring snacks.nvim's test layout.
- The current inventory is `util_spec`, `config_spec`, `init_spec`,
  `commands/{toggle,prompt,kill,attach}_spec`,
  `frontend/{review,picker,terminal,note}_spec`, `backend/bridge_spec`, and
  `backend/driver_tmux_spec` (64 cases). Unit specs exercise real buffers where
  the behavior is buffer-bound and fake Bridge/Picker/Driver modules where a
  flow only needs the seam's contract.
- `backend_tmux_spec` runs against a per-process private socket
  (`vantage-test-<pid>`), kills stale state before each case, and kills the
  server in teardown. It never touches the user's default `vantage` socket.
  It covers create/list/groups/status/health/attach/same-Group retarget/
  no-client cross-Group failure/capture/send_keys/kill.
- `prompt_spec` does not install `nvim-treesitter-textobjects`; it pins the
  absent-plugin failure contract for `{function}`/`{class}` only.
- `make test` is standalone: it is not wired into `make check`, and no CI
  workflow is added in this change.
- One edge bug found while writing the suite is fixed in the same change:
  `Util.tilde` now treats an unset or empty `HOME` as "no home" instead of
  concatenating the `vim.NIL` sentinel.

## Alternatives considered

### Why not plenary.nvim/busted?

Plenary's harness is a heavier dependency and would drag a second Neovim
plugin into tests. mini.test is purpose-built for headless Neovim suites and
is what the requested snacks.nvim reference uses.

### Why not a pure-Lua runner with vendored dependencies?

Keeping lazy.nvim's rock-based bootstrap matches snacks.nvim exactly and keeps
third-party test code out of the repository. Its cost is a network and
hererocks build on the first `make test` run (including `libreadline-dev` for
the bundled Lua 5.1 build).

### Why not full headless UI/client tests in this round?

The Client is a `:terminal` and its cross-Group relocation needs a real
attached tmux client. Building that fixture now would add a pty/process layer
the suite does not yet need; the backend spec pins the no-client failure path
instead, and client relocation is left to a future UI-testing round.

### Why not wire `make test` into `make check` or CI?

The suite is new and its first run depends on network tooling; `make check`
stays the fast local gate until the suite is proven stable. CI is a separate
decision that should not ride along with the first test-suite change.

## Consequences

- `make test` now exists as the coverage entrypoint, and `AGENTS.md` describes
  the suite instead of promising one.
- Running the suite requires nvim and tmux; the tmux specs fail loudly when
  tmux is absent rather than silently skipping.
- The first `make test` run creates `.tests/` (gitignored) and needs network
  access; later runs reuse the installed dependencies.
- `Util.tilde` no longer errors when `HOME` is unset.
- The full cross-Group client relocation path and picker/terminal UI remain
  uncovered until the follow-up UI test round.
