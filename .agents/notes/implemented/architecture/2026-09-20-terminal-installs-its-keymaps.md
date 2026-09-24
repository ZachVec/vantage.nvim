# Agent Note: The Terminal installs its own keymaps

Status: implemented

## Problem

`cli.win.keys` was applied from the command layer: `commands/actions.lua` read
the option, resolved each entry's `rhs` through its token map, and bound the
entries on a buffer the module did not own. The buffer is created in
`frontend/terminal.lua`, and the install step itself lived at one call site in
`commands/attach.lua` (`Actions.apply(Terminal.buffer)`). One fact — this
buffer carries the user's terminal keymaps — was spread over three files.

The rest of the option family already lived with the Terminal window:
`frontend/terminal.lua` reads `cli.win.layout`, `cli.win.float`, and
`cli.win.split` when it opens the buffer, so `cli.win.keys` was the only part
of its own window's configuration the Terminal did not own. The install step
was also caller-remembered: a Terminal opened any other way — a future
reattach, a spec — would come up without its keys, and nothing in the Terminal
said so.

## Decision

`frontend/terminal.lua` installs `cli.win.keys` on the buffer `open` creates.
`commands/attach.lua` attaches the client and holds the Attachment; it no
longer installs anything.

The one part of an entry the Frontend cannot answer for itself is what a `rhs`
string *means*, because a token names a command. That arrives as an injected
dependency: `open(argv, resolve)` takes the resolver and applies it to each
entry's `rhs`, and `commands/attach.lua` passes `commands/actions.lua`'s
`resolve`. The resolver contract is the `vantage.TerminalActionResolver` alias
in `frontend/terminal.lua`, next to its one consumer, and the Frontend never
imports the command layer the architecture gate forbids.

`commands/actions.lua` is now the token table and `resolve` alone: it no
longer reads `Config.options` and no longer binds keymaps. The installation
moved with its warnings, and keeps its ordering — entries are bound after the
job starts, so a Terminal whose client cannot start installs nothing (and
`destroy` removes the buffer with it).

## Alternatives considered

### Why not keep `Actions.apply(buffer)` and call it from the Terminal?

That is the same split one edge further along: the Frontend would import the
command layer, which `scripts/verify-architecture.lua` rejects outright. The
command layer owns what a token means, not when a buffer gets its keys.

### Why not hand `open` the resolved keymap list?

Then the command layer would read `cli.win.keys` and the Terminal would bind
whatever it was handed. Two layers would read one option family, and the
install step would be the caller's to remember again — exactly the arrangement
this change removes. Handing over the *meaning* of an `rhs` keeps the option
read, the buffer, and the binding in one place.

### Why not resolve tokens in `Config.apply`, which runs in the composition root?

The composition root may import both layers, so it could rewrite `cli.win.keys`
`rhs` strings into functions and leave the Terminal binding verbatim. But then
the Terminal's own reading of the option would depend on a step performed
elsewhere, and any config that did not pass through it would bind `"switch"`
as a key sequence. Resolving at the seam keeps that lie out of the Terminal's
interface.

### Why not a public `Terminal.install_keys(buffer, resolve)`?

Installation is a step of opening, not a second entry point: public, it lets a
caller bind keys to a buffer the Terminal does not own, or install twice. The
spec reaches it through `open` with a stubbed job — the same seam callers use.

## Consequences

- `frontend/terminal.lua` owns the whole `cli.win` option family, and
  `commands/actions.lua` shrank to the token map plus `resolve`, dropping its
  `config` and `util` imports.
- Terminal keymaps are installed whenever the Terminal opens rather than by
  whichever command opened it; `commands/attach.lua` only attaches and holds.
- `tests/frontend/terminal_spec.lua` pins the installation through `open`: a
  resolved token arrives as a callback, a plain `rhs` binds verbatim in every
  mode its entry names, and a malformed entry warns without stopping the rest.
  `tests/commands/attach_spec.lua` pins that the flow hands the Terminal the
  action resolver.
- Facts updated in place:
  [converge-command-surface-to-terminal-actions](../simplification/2026-09-06-converge-command-surface-to-terminal-actions.md)
  and `docs/architecture.md`.
