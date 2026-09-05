# Agent Note: Backend seam registry + tmux fallback

Status: implemented

## Problem

`backend/init.lua`'s `M.get()` was `require("vantage.backend." ..
config.backend)`: it `require`d the raw user string with no whitelist and no
fallback, so an unknown `backend` value raised at require time (and could load
an arbitrary module path). The sibling seam `picker/init.lua` already had the
right pattern — a `REGISTRY` whitelist plus a warn-and-fallback — so the two
seams had diverged.

## Decision

`backend/init.lua` now mirrors `picker/init.lua`:

- A `REGISTRY` maps user-facing names to module paths (`tmux` only today).
- Unknown name → warn + fall back to `tmux`.
- `pcall(require)` failure (driver module missing/broken) → warn + fall back to
  `tmux`.

`health.lua` benefits indirectly: `:checkhealth` calls `Backend.get().health()`,
which now degrades to `tmux` instead of raising on a bad `backend` value.

## Alternatives considered

### Why not hard-error on an unknown backend?

The picker warns and falls back; erroring would make `backend` fail-stop while
`picker` is fail-soft, and would turn `:checkhealth` from a report into a crash.

## Consequences

- `backend/init.lua` no longer `require`s a raw user string; the whitelist is
  the single source of known drivers.
- The backend and picker seams follow the same registry + fallback shape.
