# Agent Note: The Backend's public surface is backend/init.lua

Status: implemented

## Problem

The module the Frontend imports as its door to the Backend lived at
`backend/bridge.lua`, a bespoke name. The repo's convention for a facade over a
pluggable implementation is `X/init.lua`: `frontend/picker/init.lua` presents
the Picker over its renderers, and `backend/driver/init.lua` presents the Driver
seam over its implementations. `backend/` had no `init.lua`, so
`require("vantage.backend")` did not exist and every consumer reached a level
deeper into `vantage.backend.bridge`.

The name was residue, not a design. `backend/init.lua` was once the Driver
registry, mirroring `frontend/picker/init.lua`
([backend-seam-registry](../../archived/architecture/2026-09-05-backend-seam-registry.md));
when resolution moved down into `backend/driver/init.lua`
([backend-driver-seam](2026-08-31-backend-driver-seam.md)), the facade stayed
behind under the old `bridge.lua` name. Two glossary terms — Backend and
Bridge — then described one thing.

## Decision

`backend/bridge.lua` is `backend/init.lua`, and `require("vantage.backend")` is
the Backend's public surface the Frontend imports. The module's behavior is
unchanged: it keeps the composed reads (`inventory`, `focus`, `create`) and the
pass-throughs to the Driver, holds no state, and knows no UI.

The term Bridge is retired. The glossary's Backend entry now carries its
meaning, and the Driver entry points at it, so one term names one thing. The
`architecture` gate needs no change: `scripts/verify-architecture.lua`
classifies by path prefix and its composition test matches only the top-level
`lua/vantage/init.lua`, so `backend/init.lua` is still `backend`.

## Alternatives considered

### Why not keep `backend/bridge.lua`?

Nothing consumed the name. The facade-over-pluggable-implementation convention
already had a home (`X/init.lua`), and the Backend was the only facade that
broke it. Keeping the file would have left the glossary explaining two terms
for one surface.

### Why not fold the whole surface into the Driver instead of renaming it?

That was the larger proposal this rename grew out of, and it loses on the
composed reads. `inventory`'s Group derivation and `create`'s Tool resolution
are pure Lua over shared configuration, so moving them below the seam buys no
native query and duplicates them per Driver. `focus` did later move to a single
native Driver read, as its own decision
([focus-is-one-driver-read](2026-09-13-focus-is-one-driver-read.md)); the
rename itself retires the name without relocating the Lua-only composites
([focus-is-its-own-read](2026-09-13-focus-is-its-own-read.md)).

### Why not keep the module and only drop the glossary term?

That leaves the file out of step with every other facade and keeps a path that
reads as a sub-concept of the Backend rather than the Backend's own surface.
The rename is mechanical; the naming mismatch would have outlived it.

## Consequences

- Seven source modules import `vantage.backend`; the local binding is `Backend`.
- `tests/backend/bridge_spec.lua` is `tests/backend/backend_spec.lua`, and the
  flows' stubs key on `package.loaded["vantage.backend"]`.
- `docs/glossary.md`, `docs/architecture.md`, and `AGENTS.md`'s layout block
  name the new path; the Backend glossary entry absorbed the Bridge definition.
- Implemented Agent Notes that named `Bridge.*` or `backend/bridge.lua` were
  updated in place for the rename; no implemented note's decision is
  superseded, so nothing is archived and no partial supersession stays open.
- Behavior is unchanged: no command, option, default, or multiplexer call
  moves. `README.md` and `doc/vantage.nvim.txt` are untouched.
