# Vantage Architecture

A coding-agent manager built as a Neovim plugin. The [Backend](glossary.md#backend) is a [Bridge](glossary.md#bridge) over a pluggable multiplexer [Driver](glossary.md#driver) (tmux today, room for zellij later); the [Frontend](glossary.md#frontend) is the plugin's own UI — a pluggable [Picker](glossary.md#picker) plus a single `:terminal` that is the [Terminal](glossary.md#terminal). tmux is the state store, multiplexer, renderer, and input layer; there is no custom TUI.

Terminology lives in the [glossary](glossary.md); this file describes how the pieces relate and the invariants that hold them together.

## Composition root and one-way dependencies

```
lua/vantage/
├── init.lua            composition root: apply config, resolve, install
├── config.lua / util.lua   shared configuration + helpers
├── health.lua          diagnostics adapter
├── backend/            bridge.lua + driver/ (init registry, tmux)
├── frontend/           terminal, display, note, review, picker/
└── commands/           dispatch + actions, terminal_keys, attach, flows
```

- `init.lua` is the composition root. `setup()` applies configuration, resolves
  the configured Driver and Picker, then installs Prompt/Review hooks and the
  `:Vantage` command.
- `commands/` orchestrates flows and imports `frontend/`, `backend/`, and
  shared modules.
- `frontend/` imports `backend/` (through the Bridge) and its own pieces.
- `backend/` imports only shared modules.
- `health.lua` is a diagnostics adapter: it may inspect Backend and Frontend,
  but never the command layer.
- `make check` runs `scripts/verify-architecture.lua`, which rejects reverse
  module dependencies.

Configuration is fail-fast. An unknown backend/picker name, an unavailable
implementation, or a missing picker dependency raises during `setup()`; no
fallback implementation is installed. Driver/Picker are resolved once and
cached; `get()` before `setup()` is a programming error. `health.lua` catches
that error and reports it.

`Config.options` remains the global configuration singleton. `Config.apply()`
owns defaults, merging, and `cli.tools` validation; runtime lifecycle belongs
to the composition root.

## The multiplexer substrate

The plugin drives a private socket (default `vantage`, configurable via
`setup { socket = … }`) and keeps all domain state in multiplexer objects and
window options (`@agent-group`, `@agent-cmd`, `@agent-cwd`, `@agent-tool`,
`@agent-state`). Global server config — default terminal, history limit, focus
events, no status line, a 1-second status interval, and a top pane border
whose format shows `Group · Tool · cwd` plus per-Group State counts, and the
`client-detached` View cleanup hook — is applied exactly once, when the first
`new-session` starts the server. The counts are computed read-only per tick by
`scripts/vantage-counts` inside a `#()` substitution, deduplicated to one run
per Group.

The server is started by the first Agent creation and never re-checked
afterwards: operations assume it lives. A missing server reads as an empty
inventory; other operation failures return their real error.

## Domain model over the multiplexer

- A **Group** is one tmux session group. Its persistent **Anchor** session
  owns the Agent windows and survives with no client attached. Each Terminal
  client attaches to a transient **View** session grouped with the Anchor, so
  clients sharing a Group have independent current windows. When an Agent's
  last window closes the Anchor dies with it (and the multiplexer server exits
  with its last session).
- An **Anchor** is the Group's persistent session, named after the Group. It
  is never attached directly by the plugin and is never marked as a View.
- A **View** is a transient grouped session belonging to one Terminal client.
  `client-detached` destroys it when its client exits; a cross-Group
  `retarget` moves the client to a fresh View in the destination Group and
  destroys the old View.
- An **Agent** is one window containing exactly one pane, marked with the
  `@agent-*` options. Its shared record carries an opaque `id` (the Driver's
  identity), a driver-neutral `seq` for creation order, Group, command, Cwd,
  Tool, and optional State. tmux's `@N` format is parsed only inside the tmux
  Driver.
- The **attachment** is the Terminal's client pointed at a View. Opening the
  Terminal creates the View and starts the attach command; closing it (or the
  client exiting) ends the attachment. The focused Agent is derived from the
  live state on every `snapshot`, never stored Neovim-side.

## Seams and contracts

**Driver** (`backend/driver/init.lua` resolves the configured module from a
whitelist):

- `create({ group, cmd, cwd, tool })` → `Agent, nil` or `nil, err`; creating
  the Group (and on the first creation the server and its config). Metadata
  failures roll back the partial Agent.
- `snapshot(pid?)` → `{ agents, groups, focused? }, nil` or `nil, err` from one
  shell process (two chained multiplexer commands).
- `retarget(pid, agent)` → `true` or `false, err`; same-Group switching selects
  a window in the client's own View, while cross-Group switching creates a
  fresh View, moves the client, and destroys the old View.
- `attach(agent)` → `{ view, argv }` or `nil, err`; creates a fresh View for
  the Terminal and returns its attach argv.
- `kill_view(view)` → `true` or `false, err`.
- `kill_agent(agent)` / `kill_group(group)` → `true` or `false, err`.
  `kill_group` destroys the Anchor and every View.
- `send_keys(agent, text)` → `true` or `false, err`; temporary buffers are
  cleaned up.
- `capture_pane(agent, max_lines?)` → `lines, nil` or `nil, err`;
  `status()` → `{ clients, sessions }, nil` or `nil, err`;
  `health()` → health-check records.

The Driver returns errors and never notifies the user. The Bridge passes
results through; command flows decide how to report them.

**Bridge** (`backend/bridge.lua`) is the Frontend's only door to the Backend:
`agents(pid)`, `create`, `retarget(pid, agent)`, `send(agent, text)`,
`capture(agent)`, `attach(agent)`, `kill_view(view)`, `kill_agent`,
`kill_group`, `status`. It holds no state and does no UI; the prompt flow
resolves the focused Agent and renders templates, then hands the Bridge the
final text.

**Terminal** (`frontend/terminal.lua`) is a dumb display surface: `open(argv)`
starts the terminal job, `show`/`hide` manage the window without killing the
job, `destroy` stops the job and deletes the buffer, and a `TermClose` autocmd
does the same whenever the client exits. One Terminal per Neovim instance.

**Picker** (`frontend/picker/init.lua`) is a facade over a pluggable renderer.
Commands call `Picker.pick(spec, opts)` or `Picker.pick_plain(...)`; `get()` is
internal. A picker declares exactly two capabilities:

- `preview` — it can render `item:preview()`.
- `command` — it can bind the flow's picker commands.

`opts.commands` is a list of keymap-shaped descriptors
`{ lhs, rhs, desc? }`, where `rhs(ctx)` receives `{ item, items }` and returns
`true` when the item list may have changed. A true result re-reads
`items_provider` and refreshes (or closes on an empty result). Commands are
global to the picker UI; the facade rejects duplicate `lhs` values and drops
commands for a picker without the `command` capability. Group scoping is an
ordinary command, not a Picker concept.

## Flows and the command surface

- `commands/attach.lua` owns `toggle`/`switch` plus their shared
  Agent/Tool rows, Group choice, creation handoff, and `<c-g>` scope command.
- `commands/terminal_keys.lua` installs `cli.win.keys`; `commands/actions.lua`
  maps built-in tokens (`toggle`, `switch`, `prompt`) to command functions.
- `:Vantage toggle` owns presence: hide/show; with no Terminal, pick an Agent
  (Tool rows create one) and open the Terminal on it.
- `switch` (terminal token) owns target: `retarget` to the resolved Agent.
- `:Vantage detach` destroys the Terminal; Agents and Groups survive.
- `:Vantage status` shows the Driver's session/client summary.
- `:Vantage review [list|clear]` manages Reviews (bare adds over the range);
  the `{reviews}` placeholder batches them into a Prompt.
- `:Vantage kill` picks an Agent or Group and kills it.
- Terminal tokens via `cli.win.keys`: `switch`, `prompt`, `toggle`.

Creating an Agent from a Tool row resolves the tool to its command, uses the
global Neovim cwd, and always asks for a Group; `retarget` identifies the
Terminal's client by the terminal job's pid.

## Review and Prompt

Reviews live entirely in memory (`frontend/review.lua`: extmark + per-buffer
registry) and render through `setup { reviews = { item = … } }`; the Prompt
vocabulary (`{file}`, `{line}`, `{function}`, `{class}`, `{reviews}`) lives in
`config.lua` as a shared contract, health-checked at startup. Prompt text is
pasted with bracketed paste and never auto-submits.
