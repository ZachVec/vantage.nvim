# Agent Note: Annotation display uses the local Neovim cwd

Status: implemented

## Problem

Annotation picker previews and note-float titles used `Select.focused_cwd()`,
which preferred the focused Agent's cwd when one existed. Annotations are
anchored in buffers owned by the current Neovim instance, not by an Agent, so
their display paths should be relative to the local Neovim cwd. Tying their
rendering to the focused Agent made a local editing feature change meaning
when the terminal was pointed at another Agent.

## Decision

`select.lua` no longer exposes `focused_cwd()`. The annotation picker and the
note float use `Util.cwd()` directly.

Sending annotations to an Agent still uses the focused Agent's cwd because
that rendering happens inside `Prompt.render` with `Prompt.context(agent)`.
The display path and the send path are now separate.

## Alternatives considered

### Why not keep `focused_cwd()` for annotations?

It mixed Agent context into an nvim-local feature and made preview output
depend on which terminal window was focused. Annotations should not change
meaning when the Agent changes.

## Consequences

- `Select.focused_cwd()` is deleted.
- Annotation list previews and note-float titles use `Util.cwd()`.
- `{annotations}` prompt rendering still relativizes to the focused Agent's
  cwd when sent, because the prompt context supplies that cwd.
