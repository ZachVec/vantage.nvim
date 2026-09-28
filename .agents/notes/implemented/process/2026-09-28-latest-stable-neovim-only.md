# Agent Note: Vantage supports only the latest stable Neovim

Status: implemented

## Problem

The requirements claimed Neovim >= 0.10 in README, `doc/vantage.nvim.txt`, and
`:checkhealth`. Carrying that floor means either verifying behavior on versions
the maintainer does not run, or shipping a claim that may be false — the
Review range/undo work here behaved differently on 0.10.0 in an experiment,
and the supported floor would have had to be justified feature by feature.

## Decision

Vantage supports only the latest stable Neovim. This change writes
`vim.fn.has("nvim-0.12")` into `health.lua` and "Neovim >= 0.12" into README
and `doc/vantage.nvim.txt`; the verified version for this work was 0.12.3.
No compatibility branches, fallbacks, or patch probes for 0.10/0.11 are added.

The floor is a support policy, not a claim that a feature landed in 0.12: the
extmark options the Review work relies on are older than that, and the point is
that Vantage tests and documents against the stable release it actually runs.

## Alternatives considered

### Why not keep `>= 0.10`?

It is a support promise this project cannot verify here; the failure that
prompted the change was found by experiment, not by the test suite, so the
claim would rest on untested behavior.

### Why not support 0.10/0.11 with a conditional?

A version check would exist to keep an unverified path alive, and the user's
decision was to support the latest release only. Conditionals for old versions
also age into untested branches with no owner.

### Why not name the first version that fixes the experiment?

That would require reproducing the difference on every intermediate release to
justify one number, for a support window nobody promised. The policy is
latest-only.

## Consequences

- `:checkhealth vantage` reports the 0.12 floor and fails it on older
  versions; README and `doc/vantage.nvim.txt` state it.
- Future behavior may rely on the latest stable release without a
  compatibility branch, and old-version failures are out of scope by policy.
