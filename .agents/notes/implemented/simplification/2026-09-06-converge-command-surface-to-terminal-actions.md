# Agent Note: Converge :Vantage to direct commands and terminal keymap actions

Status: implemented

## Problem

`:Vantage` dispatched seven subcommands — `switch`, `kill`, `toggle`, `detach`,
`prompt`, `annotate`, `status`. In practice only four are ever invoked as
commands: `toggle`, `detach`, `annotate` and `status`. The other three
(`switch`, `kill`, `prompt`) are triggered from inside the vantage terminal,
bound through `cli.win.keys` entries whose RHS is a verbatim
`<cmd>Vantage switch<CR>` (and friends). Having a `:Vantage` entry point for
them was surface area that was never used directly.

The same uncertainty forced a runtime probe: because any subcommand could be
triggered either from the terminal window or from a normal window, `select.lua`
carried `invoked_from_terminal()` — "is the terminal open and is it the current
window?" — and threaded its result through `PickSpec`/`PlainSelectOpts`, where
only the snacks picker consumed it (to re-enter terminal mode after a picker
close and to gate the focused-Agent pin). Once each action's trigger context
is fixed by construction, that probe has nothing left to decide.

## Decision

- `:Vantage` dispatches only `toggle`, `detach`, `annotate` (`list`/`clear`)
  and `status`. `switch`, `kill` and `prompt` are removed from `run`,
  completion, and the `usage()` help.
- Terminal actions are first-class: a `cli.win.keys` `rhs` string naming
  `switch`, `kill`, `prompt`, or `toggle` resolves to the built-in action
  (new `lua/vantage/keys.lua`); any other `rhs` — a key sequence, a `<cmd>`
  string, or a Lua function — is bound verbatim as before. No default keymaps
  are shipped (the
  [single-terminal-frontend](../architecture/2026-08-31-single-terminal-frontend.md)
  "no default keymaps" decision stands); the four actions are opt-in.
- The `invoked_from_terminal()` probe is deleted. `PickSpec`/`PlainSelectOpts`
  carry `from_terminal` as a **caller-declared** constant instead:
  `switch`/`kill`/`prompt` (terminal-only) declare `true`, `annotate` declares
  `false`, and `toggle`'s open-path fallback declares `false`. The focused pin
  and the snacks terminal-mode restore key off that declared fact, never off a
  window probe.
- `Agent.switch`'s "no client" guard is removed: from a terminal keymap the
  terminal is live by construction, and `Client.retarget` keeps its own
  `is_attached` seam check.

## Alternatives considered

### Why not a structured action→key map (e.g. `{ t = { toggle = … }, n = { … } }`)?

A fixed map is closed: every terminal action must be enumerated and any
free-form binding needs a second escape hatch. Token-or-verbatim keeps the
existing 4-tuple list open — a string that matches an action runs it, anything
else binds as-is — so `cli.win.keys` stays a single, unrestricted mechanism.

### Why not keep the `invoked_from_terminal()` window probe?

Trigger context is now known statically per action, so the probe would be
computing a constant at runtime. Declaring it at the call site removes the
window-identity coupling and the "which window was current" defensive logic
behind it.

### Why not ship default keymaps for the terminal actions?

Shipping defaults would reverse
[single-terminal-frontend](../architecture/2026-08-31-single-terminal-frontend.md)'s
"no default keymaps" decision and needs array-merge override semantics to let
a user clear them. Keeping the default empty and documenting the four tokens
preserves that decision; the trade-off is that `switch`/`kill`/`prompt` are
unreachable until bound.

### Why not make `stopinsert`, `detach`, and `status` built-in tokens?

`stopinsert` is one line (`vim.cmd("stopinsert")`), so a verbatim function RHS
covers it without a token. `detach` and `status` are used from outside the
terminal and remain `:Vantage` commands, not terminal actions.

## Consequences

- `switch`, `kill` and `prompt` have no `:Vantage` entry point; they run only
  through a `cli.win.keys` token. `toggle` remains both a command and a token.
- `PickSpec.from_terminal` / `PlainSelectOpts.from_terminal` replace
  `invoked_from_terminal` across `select.lua`, `commands/*`, and the snacks
  picker; native and fzf-lua still ignore the field.
- `Agent.switch` and `Agent.kill` no longer take an argument: their `@N` /
  `group|@N` branches (now unreachable) and the `find_agent` helper are
  removed; both always run their interactive picker.
- README and `doc/vantage.nvim.txt` document the trimmed command list and the
  token-or-verbatim `cli.win.keys` form, with `switch`/`kill`/`prompt` marked
  terminal-only.
- Facts updated in place: `invoked_from_terminal` → `from_terminal` in
  [picker-pure-renderers](../architecture/2026-09-05-picker-pure-renderers.md),
  [agent-picker-order](../feature/2026-09-04-agent-picker-order.md),
  [float-terminal-switch-loses-focus](../bug-fix/2026-09-05-float-terminal-switch-loses-focus.md),
  [snacks-new-group-terminal-mode](../bug-fix/2026-09-05-snacks-new-group-terminal-mode.md),
  and [agent-picker-group-scope](../feature/2026-09-05-agent-picker-group-scope.md).
