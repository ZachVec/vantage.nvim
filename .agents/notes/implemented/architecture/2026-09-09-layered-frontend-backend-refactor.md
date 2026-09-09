# Agent Note: Layered frontend/backend refactor — Bridge verbs, uniform entries, no View

Status: implemented

## Problem

Successive feature notes had accumulated machinery that outlived its reasons:
session-grouped Views with Anchor sessions and a client-detached hook; picker
items carrying flow-injected `activate(after)` closures and incomplete per-kind
method sets; a Backend surface that fused domain semantics with tmux specifics;
commands split between `:Vantage` subcommands and terminal keymaps. The plugin
was to be rewritten wholesale with no compatibility requirement — functionality
references the old code, behavior does not need to — judged by three criteria:
readability, abstraction without over-abstraction, and performance.

## Decision

The plugin is three layers with one-way dependencies: `commands/` orchestrates
and imports `frontend/` and `backend/`; `frontend/` imports `backend/`;
`backend/` imports only `config`/`util`. Root modules (`init`, `config`,
`util`, `health`) are shared.

Backend:

- `backend/bridge.lua` is the bridge: pure-data domain verbs
  (`agents(pid)` → the flat inventory `{ agents, groups, focused }`, `create`, `retarget`,
  `send`, `capture`, `attach_command`, `kill_agent`, `kill_group`, `status`).
  It knows no UI and holds no state.
- `backend/driver/` is the pluggable seam: `init.lua` resolves the configured
  driver (whitelist + fallback to tmux), `tmux.lua` is pure tmux mapping with
  the domain-shaped verbs `create`, `snapshot(pid)`, `retarget(pid, agent)`,
  `attach_command`, `kill_agent`, `kill_group`, `send_keys`, `capture_pane`,
  `status`, `health`. zellij remains a distant seam only; no compatibility
  promise hardens the interface for it.

Domain model:

- **Group** = one plain tmux session; **Agent** = one single-pane window in it,
  carrying the `@agent-*` options. The attachment is the terminal's tmux
  client pointing at (Group, Agent). **View, Anchor, session groups, and the
  client-detached hook are deleted** — a session already persists headless and
  multiple clients on one session already show independent windows, so the old
  machinery duplicated tmux's own property.
- The server starts on the first `create` (`new-session`, which applies the
  global config exactly once per server start); no verb re-checks it. External
  kills surface as warnings on the next operation; there is no watchdog or
  reconciliation. `snapshot(pid)` is one bash process chaining
  `list-windows` + `list-clients`, so listings and the focused Agent cost one
  fork.
- `retarget(pid, agent)` is the single switch verb (`switch-client`), handling
  same-Group window changes and cross-Group relocation alike; the terminal's
  client is identified by the terminal job's pid.

Frontend:

- `frontend/terminal.lua` is a dumb display surface: `open(argv)` starts the
  terminal job and returns its pid, `show`/`hide`/`destroy` manage the window,
  and `TermClose` closes the window, deletes the buffer, and resets state — the
  attachment's lifecycle is the terminal's lifecycle. It stores no domain
  state and never resolves the focused Agent (that is derived per `snapshot`).
- Each command defines its own row classes behind a local protocol: the switch
  flow's `SwitchAgentEntry`/`SwitchToolEntry` resolve rows (`target(done)`),
  the kill flow's `KillAgentEntry`/`KillGroupEntry` delete rows (`delete()`),
  and the review flow's rows open notes; every row renders through `format()` /
  `preview()`. No entry carries a flow action.
- Picker implementations stay pure renderers (format/preview/on_choice,
  optional in-place delete where the flow enables it, optional `<c-g>` scope
  toggle reading the `group` field). The `from_terminal` flag is deleted: a
  picker detects the terminal window at open time by filetype.

Commands:

- `:Vantage` subcommands: `toggle`, `detach`, `status`, `review`, `kill`.
- Terminal tokens via `cli.win.keys` (resolved in `commands/toggle.lua`):
  `switch`, `prompt`, `toggle`. `switch` and `prompt` exist only inside the
  terminal; `kill` moved out to a command.
- Toggle owns presence (hide/show; with no terminal, pick-or-create then
  attach+show); switch owns target (`retarget`). The pick flow is shared; only
  the tail after `resolve()` differs, and that tail lives in each command —
  no callback is injected into entries.

Renames and behavior references:

- **Annotation → Review** everywhere: `:Vantage review`, `setup.reviews`,
  the `{reviews}` placeholder, `frontend/review.lua`, `commands/review.lua`.
- `kill` keeps its name at the domain layer (`kill_agent`/`kill_group`) because
  it terminates processes; `delete()` is only the generic entry protocol verb.
- A new Agent's cwd is the global Neovim cwd (follows `:cd`, ignores
  `:lcd`/`:tcd`); the Frontend resolves and passes it explicitly.

## Alternatives considered

### Why not keep Anchor sessions and grouped Views?

A plain tmux session persists with no clients attached, and two clients on one
session can look at different windows — the two properties Anchor+Views were
built to provide. Deleting them also deletes the client-detached hook and the
View-relocation machinery.

### Why not dispatch on a `kind` field instead of entry methods?

`resolve()`/`delete()` keep each flow's choice handler to one polymorphic line;
the uniform nil/false protocol means neither flows nor pickers ever test which
methods an entry has.

### Why not keep `activate(after)` with an injected flow tail?

Injection makes an entry's behavior depend on which flow built it and, for Tool
rows, smuggles a picker sub-flow into a method. `resolve()` inverts the
direction: the entry returns its target and each flow applies its own tail.

### Why not rename kill to delete?

`kill_agent`/`kill_group` terminate live processes (`kill-window`/
`kill-session`); `delete` reads as removing a record and would understate the
effect, especially for a Group other terminals are attached to.

### Why not keep the `from_terminal` PickSpec flag?

Terminal-ness is a runtime fact (the current window's filetype) at picker
open time, not state the caller should declare; deriving it removes a
caller-declared parameter and the restore-mode branching that followed it.

## Consequences

- `setup{}` keys and defaults are preserved except `annotations` → `reviews`
  (an intentional exception to the keep-the-keys rule); `cli.win.keys` tokens
  become `switch`/`prompt`/`toggle`.
- The Agent list no longer offers in-place `<c-x>` kill (kill is a command);
  the Review list keeps `<c-x>` deletion through `delete()`.
- Each nvim instance has at most one terminal, whose client is identified by
  the terminal job's pid; several instances may attach to one Group showing
  different Agents.
- `:Vantage kill` is a new user command; `switch`/`prompt` remain
  terminal-only, and there is no `:Vantage switch`/`:Vantage prompt`.
- Tests mirror the layers (`tests/backend`, `tests/frontend`, `tests/commands`).
- Superseded decisions are archived: Group/Anchor/Agent/View,
  picker-domain-objects, cross-group switch relocation, the Agent-picker
  `<c-x>` kill, and annotation-cwd-is-nvim-local.
