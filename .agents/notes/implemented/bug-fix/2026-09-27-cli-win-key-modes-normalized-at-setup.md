# Agent Note: Setup normalizes a cli.win.keys mode spelling

Status: implemented

## Problem

`doc/vantage.nvim.txt` tells users to set a `cli.win.keys` entry's `mode` to
`"n"`, `"t"`, or `"nt"` — one or more mode short-names concatenated. The only
code that read that spelling lived in the command layer:
`commands/actions.lua` split the string into single characters and handed
`vim.keymap.set` the resulting list.

The refactor that moved installation into the Terminal
([terminal-installs-its-keymaps](../architecture/2026-09-20-terminal-installs-its-keymaps.md))
carried the `vim.keymap.set` call across and dropped the split, and the
setup-validates-config change
([setup-validates-config-runtime-trusts-it](../simplification/2026-09-26-setup-validates-config-runtime-trusts-it.md))
left `mode` untouched in `sanitize_win`. `mode` now reached `vim.keymap.set`
verbatim, and that call takes one mode short-name or a list of them; a
concatenated `"nt"` is neither, so the call failed, the entry warned as
`invalid terminal keymap '<lhs>'`, and the keymap bound in no mode at all. A
documented, working spelling went silent with nothing else normalizing it.

## Decision

`Config.sanitize_win` resolves each surviving entry's `mode` into the
single-mode list `vim.keymap.set` takes: it splits a string into its
short-names (`"nt"` → `{ "n", "t" }`), joins and splits a list so its elements
may name several modes each, and turns a missing `mode` into `{ "n" }`, the
documented default. A `mode` that is neither a string nor a list of strings is
a malformed entry and is dropped with the same warning as the rest.

`frontend/terminal.lua` passes `keymap.mode` straight to `vim.keymap.set`;
the Terminal neither interprets the spelling nor supplies the default.

`tests/config_spec.lua` pins the normalization and the dropped bad `mode`
type; `tests/frontend/terminal_spec.lua` pins that `mode = "nt"` binds in both
modes through `open`; `tests/init_spec.lua` pins the missing-`mode` default
through `Init.setup`.

## Alternatives considered

**Split the spelling in the Terminal.** That is where the removed guard lived
and it is one line. But the spelling is user configuration, and `Config.apply`
is the boundary that reads user configuration; splitting at install would put
a second, unvalidated reading of the option back in the Frontend and leave
`Config.options` holding a spelling only `vim.keymap.set` understands.

**Drop `"nt"` from the documented spellings and require a list.** This keeps
the runtime simple by shrinking the public contract. It breaks a released
config spelling for no gain, and the concatenated form is the one users were
told to write.

**Reject unknown mode short-names at setup.** `sanitize_win` could drop
`mode = "q"` instead of letting `vim.keymap.set` reject it at open. That would
move the one existing install-time warning for bad keymaps without fixing
anything the bug is about; the split is the missing step, not the validation.

## Consequences

- A `cli.win.keys` entry with `mode = "nt"` binds in Normal and Terminal mode
  again, as the user-facing docs promise, and a `mode = { "n", "t" }` list
  keeps behaving as it did.
- `Config.options.cli.win.keys` holds mode lists after setup, so the Terminal's
  install step has no per-entry interpretation left.
- A non-string, non-list `mode` is dropped at setup, once, alongside the other
  malformed entries rather than at every Terminal open.
- An unrecognized mode short-name (`mode = "q"`) still fails in the install
  step and warns as `invalid terminal keymap '<lhs>'`; the bug was the split,
  and that path is unchanged.
