# Vantage Architecture

A coding-agent manager built as a Neovim plugin. The [Backend](glossary.md#backend) is a [Bridge](glossary.md#bridge) over a pluggable multiplexer [Driver](glossary.md#driver) (tmux today, room for zellij later); the [Frontend](glossary.md#frontend) is the plugin's own UI — a pluggable [Picker](glossary.md#picker) plus a single `:terminal` that is the [Terminal](glossary.md#terminal). tmux is the state store, multiplexer, renderer, and input layer; there is no custom TUI.

Terminology lives in the [glossary](glossary.md); this file describes how the pieces relate and the invariants that hold them together.

## Three layers, one-way dependencies

```
lua/vantage/
├── init.lua / config.lua / util.lua / health.lua   shared
├── backend/            bridge.lua + driver/ (init registry, tmux)
├── frontend/           terminal, entries, picker/, review, note
└── commands/           init (dispatch), switch, toggle, kill, review, prompt, keys
```

- `commands/` orchestrates flows and imports `frontend/` and `backend/`.
- `frontend/` imports `backend/` (through the Bridge) and its own pieces.
- `backend/` imports only `config` and `util`.

The flow layer owns every user action; no picker row carries one. Each command
defines its own row classes behind one local protocol per flow: the switch
flow's rows resolve (`target(done)`), the kill flow's rows delete
(`delete()`), and the review flow's rows open notes — every row still renders
through `format()` / `preview()`.

## The multiplexer substrate

The plugin drives a private socket (default `vantage`, configurable via
`setup { socket = … }`) and keeps all domain state in multiplexer objects and
window options (`@agent-group`, `@agent-cmd`, `@agent-cwd`, `@agent-tool`,
`@agent-state`). Global server config — default terminal, history limit, focus
events, no status line, a 1-second status interval, and a top pane border
whose format shows `Group · Tool · cwd` plus per-Group State counts — is
applied exactly once, when the first `new-session` starts the server. The
counts are computed read-only per tick by `scripts/vantage-counts` inside a
`#()` substitution, deduplicated to one run per Group.

The server is started by the first Agent creation and never re-checked
afterwards: operations assume it lives, and an external kill surfaces as a
warning on the next operation. There is no watchdog and no reconciliation;
the next creation starts a fresh server and re-applies the config.

## Domain model over the multiplexer

- A **Group** is one session. It is never created alone: `create` targeting a
  new Group makes the session; a session persists with no client attached, so
  Agents survive every Terminal close. When an Agent's last window closes the
  session dies with it (and the multiplexer server exits with its last
  session).
- An **Agent** is one window containing exactly one pane, marked with the
  `@agent-*` options. There are no session groups, no anchor session, and no
  per-view session: several clients can attach to one session and each show a
  different window, which is all the old View machinery provided.
- The **attachment** is the Terminal's client pointed at (Group, Agent). It is
  not a multiplexer object: opening the Terminal starts the attach command,
  closing it (or the client exiting) ends the attachment, and `retarget`
  repoints it. The focused Agent is derived from the live state on every
  `snapshot`, never stored Neovim-side.

## Seams and contracts

**Driver** (resolved by `backend/driver/init.lua` from `setup { backend = … }`):

- `create({ group, cmd, cwd, tool })` → Agent record (creating the Group, and
  on the first creation the server and its config);
- `snapshot(pid?)` → `{ agents, focused? }` from one shell process (two
  chained multiplexer commands);
- `retarget(pid, agent)` → one `switch-client`, covering same-Group window
  changes and cross-Group moves;
- `attach_command(group, agent)` → the argv the Terminal runs;
- `kill_agent(agent)` / `kill_group(group)`;
- `send_keys(agent, text)`, `capture_pane(agent, max_lines?)`,
  `status()`, `health()`.

**Bridge** (`backend/bridge.lua`) is the Frontend's only door to the Backend:
`agents(pid)` (the flat inventory — Agents in creation order, derived Groups,
and the focused Agent), `create`, `retarget(pid, agent)`, `send(agent, text)`,
`capture(agent)`, `attach_command`, `kill_agent`, `kill_group`, `status`. It
holds no state and does no UI; the prompt flow resolves the focused Agent and
renders templates, then hands the Bridge the final text.

**Terminal** (`frontend/terminal.lua`) is a dumb display surface: `open(argv)`
starts the terminal job and returns its pid, `show`/`hide` manage the window
without killing the job, `destroy` stops the job and deletes the buffer, and a
`TermClose` autocmd does the same whenever the client exits. One Terminal per
Neovim instance.

**Picker** (`frontend/picker/`) implementations are pure renderers over a
`PickSpec` (`prompt`, `items_provider`, optional `group` scope filter). They
read `format()`/`preview()`, deliver the chosen row through `on_choice`, and
bind an in-place `delete()`/`<c-g>` toggle only where the flow asks for it.
The `from_terminal` flag is gone: an implementation detects the terminal
window by its filetype when the pick opens. Pane previews and Review previews
are computed by the entry builders (through `Bridge.capture` and Review
rendering), so renderers never touch the Backend.

## Flows and the command surface

- `:Vantage toggle` owns presence: hide/show; with no Terminal, pick an Agent
  (Tool rows create one) and open the Terminal on it.
- `switch` (terminal token) owns target: `retarget` to the resolved Agent.
- `:Vantage detach` destroys the Terminal; Agents and Groups survive.
- `:Vantage status` shows the Driver's session/client summary.
- `:Vantage review [list|clear]` manages Reviews (bare adds over the range);
  the `{reviews}` placeholder batches them into a Prompt.
- `:Vantage kill` picks an Agent or Group and kills it (no in-picker `<c-x>`
  in the Agent list — kill is a command; the Review list keeps its in-place
  delete).
- Terminal tokens via `cli.win.keys`: `switch`, `prompt`, `toggle` — resolved
  by `commands/toggle.lua`; `switch` and `prompt` exist only inside the
  Terminal.

Creating an Agent from a Tool row resolves the tool to its command, uses the
global Neovim cwd, and always asks for a Group; `retarget` identifies the
Terminal's client by the terminal job's pid.

## Review and Prompt

Reviews live entirely in memory (`frontend/review.lua`: extmark + per-buffer
registry) and render through `setup { reviews = { item = … } }`; the Prompt
vocabulary (`{file}`, `{line}`, `{function}`, `{class}`, `{reviews}`) is owned
by the prompt flow module, which health-checked against at startup. Prompt
text is pasted with bracketed paste and never auto-submits.
