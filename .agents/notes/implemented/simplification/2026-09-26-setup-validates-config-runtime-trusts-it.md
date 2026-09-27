# Agent Note: Setup validates config; the runtime trusts it

Status: implemented

## Problem

`Config.apply` validated `cli.tools` and gave every surviving Tool a reference
hook, but most other user configuration stayed unchecked until it was used.
The runtime then carried guards for conditions only an invalid config could
produce:

- `frontend/terminal.lua` re-checked every `cli.win.keys` entry on each open,
  defaulted missing float/split sizes, translated `border = false` at open
  time, and treated an unknown `cli.win.layout` as a bottom split.
- `commands/prompt.lua` skipped non-string prompt templates during its setup
  scan but let the same template crash later when it was picked and sent.
- `frontend/review.lua` had no setup check for `reviews.item` fields, so a
  misspelled placeholder was typed literally.
- `config.lua` silently replaced a non-function `tool.format` with the
  default instead of reporting it.

Several other guards re-checked conditions whose only producer is repo code:
the pre-setup identity resolver in `Terminal`, `keys or {}`, the `or 0`
size defaults, `Entries.preview`'s `or none`, a `not spec.preview` test inside
`if spec.preview`, and dead `or ""` tails.

## Decision

`Config.apply` is the one setup-time validator for user configuration.
Invalid entries in a collection are dropped, invalid scalars fall back to
their default, and each case warns, so the runtime reads the applied config
as already valid.

- `sanitize_tools` also rejects a `format` that is present but not a
  function; the surviving-Tool loop then only fills in a missing hook.
- New `sanitize_prompts` drops non-string templates.
- New `sanitize_win` validates `layout`, the float/split sizes, normalizes
  `border = false` to `"none"`, and drops malformed `cli.win.keys` entries.
- `Review.setup` warns about a `reviews.item` template naming a field outside
  its vocabulary, mirroring the Prompt check; the `FIELDS` list moved above
  `setup` so it is the one owner of that vocabulary.
- `Prompt.setup` no longer re-checks template types.

With user config validated at setup, the runtime drops the corresponding
guards. `Terminal` installs `cli.win.keys` verbatim and asserts that `setup`
installed the action resolver; `open_win` reads sizes and border directly;
`Entries.preview` indexes its closed kind table; and `fzf_lua` captures the
`spec.preview` it already tested. `Terminal.open` also returns the failure
reason instead of notifying, so a failed attach is reported once, by the flow
that asked for the Terminal.

## Alternatives considered

**Keep the runtime guards.** Each one is cheap, but together they hide which
checks are seams. User config is a boundary crossed exactly once, at
`Config.apply`; a guard after that point cannot tell the next reader whether
the condition is external or merely a restated invariant.

**Raise on malformed `cli.win` config instead of warning and falling back.**
`cli.tools` already sets the precedent: an invalid entry is dropped, recorded
for `:checkhealth`, and the plugin runs. Raising would be stricter, but a
keymap typo or a misspelled layout would stop initialization entirely.
`sanitize_win` follows the existing shape; revisiting it means revisiting the
Tool policy too.

**Validate `reviews.item` in `Config.apply`.** The Review field vocabulary is
Review's own, and `Config` is a shared module that imports nothing but itself.
`Review.setup` already owns Review's setup-time work, so the check lives
there, the same split `Prompt.setup` uses for prompt placeholders.

**Keep the identity resolver for a Terminal opened before setup.** A `get()`
before setup is already a documented programming error in Backend and Picker.
The identity default made the same mistake silently bind a raw `rhs` string,
which could turn a named terminal action into a literal key sequence.

## Consequences

- Invalid config now warns once at setup and the plugin keeps running: an
  unknown layout falls back to `float`, a malformed keymap entry is dropped,
  a non-string prompt disappears from the Prompt pick, and a non-function
  `tool.format` is reported by `:checkhealth vantage`.
- Malformed `cli.win.keys` entries are no longer warned about on every
  Terminal open; they are dropped once, at setup.
- `Terminal.open` fails loudly when called before `Terminal.setup`; the
  composition root installs the resolver before any flow can open one.
- A failed attach reports one warning instead of an error notification plus a
  duplicate warning.
- `Entries.preview` errors for an entry kind outside the `frontend/entries.lua`
  vocabulary instead of previewing an empty pane; the kind set is closed and
  every producer is in that module.
