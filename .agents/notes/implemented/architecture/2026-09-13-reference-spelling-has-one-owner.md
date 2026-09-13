# Agent Note: Reference spelling has one owner

Status: implemented

## Problem

A location reference — a Prompt's `{file}` and `{line}`, a Review's `{lines}`
and `{file}`, and every gathered row — was assembled at five call sites across
three modules. Each site relativized the path, built the `:L` suffix, applied
the focused Tool's `format` hook, and decided for itself what a declining hook
means: the Prompt flow skipped the whole Prompt, the gather flow dropped the
whole send, and a Review preview silently rendered an empty string. An empty
string was read two ways on top of that — a decline in gather, a successful
empty fragment in Prompt and Review. `Config.tool_format(name)` was the hook's
one reader, while `commands/prompt.lua` and `frontend/review.lua` carried the
default spelling (`Util.reference`) on their own.

## Decision

`Config.tool_reference(tool, cwd, path, start_row, end_row)` is the one place a
reference is spelled:

- `tool` names the Focus's Tool. Nil (no Focus) and a Tool a later setup dropped
  both spell config's own default: `file`, plus `" " .. loc` when there is a
  position.
- `path` is relativized against `cwd` (absolute when it escapes), `start_row`
  and `end_row` become the `:L` suffix (`:L42` for one line, `:L2-4` for a
  range), and `tool.format(file, loc)` is applied last.
- A nil or "" return from the hook — and an empty path — means the reference
  does not exist. The function returns nil and the flow owns what to do about
  it.

The default spelling is a local function in `config.lua`; `Util.reference` and
`Config.tool_format` are gone. `vantage.ReferenceFormat` stays in `config.lua`
as `vantage.Tool.format`'s type. The hook's own contract is unchanged:
[Tool format hooks spell location references](../feature/2026-09-11-tool-format-location-hook.md)
still owns `format(file, loc)`, including nil or "" giving up on a reference.

## Alternatives considered

### Why not make the hook's return non-nil?

The hook is user config — an external input — and
[trust-non-nil-annotations](../simplification/2026-09-06-trust-non-nil-annotations.md)
puts that class of check at the seam, not behind a dropped `?`: an annotation
cannot constrain a function a user wrote, and the only moment it can be checked
is the call. Banning nil would also reverse the recorded decision and the two
specs that pin it.

### Why not return a decline reason (`nil, reason`)?

No caller branches on why a reference is missing; each reports it in its own
words, so a reason would be a cause vocabulary nobody reads. The one case that
does vary — a buffer with no name — is decided here as "no path, no reference",
which needs no name of its own.

### Why not keep `Util.reference` in the shared helpers?

Once the flows went through `tool_reference`, `Util.reference` had no reader
outside `config.lua`: `apply` was its only writer (it is the hook every Tool
without one gets) and `tool_format` its only reader. A helper with one internal
caller is surface area, not leverage.

### Why not keep `Config.tool_format` as a public reader?

`apply` guarantees every surviving Tool a `format` function, so the lookup is
one expression inside `tool_reference`. The accessor existed for the call sites
`tool_reference` now serves.

## Consequences

- One owner for what a reference looks like and for what a declining hook
  means; each flow keeps only its own policy — skip the Prompt, drop the send,
  blank preview.
- "" no longer survives as an empty fragment in a Prompt or a Review: like nil,
  it reads as a decline.
- The `:L` syntax has one owner, so a new caller or a new position shape
  touches `config.lua` only.
- `tests/config_spec.lua` pins the whole-file, single-line, range, missing-path,
  and declining-hook cases at the seam; the three flow specs spell through a
  named Tool.
