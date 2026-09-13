# Vantage Architecture

A coding-agent manager built as a Neovim plugin. The [Backend](glossary.md#backend) is a [Bridge](glossary.md#bridge) over a pluggable multiplexer [Driver](glossary.md#driver) (tmux today, room for zellij later); the [Frontend](glossary.md#frontend) is the plugin's own UI — a pluggable [Picker](glossary.md#picker) plus a single `:terminal` that is the [Terminal](glossary.md#terminal). tmux is the state store, multiplexer, renderer, and input layer; there is no custom TUI.

Terminology lives in the [glossary](glossary.md); this file describes how the pieces relate and the invariants that hold them together.

## Composition root and one-way dependencies

```
lua/vantage/
├── init.lua            composition root: apply config, resolve, install
├── config.lua / util.lua   shared configuration + helpers
├── health.lua          diagnostics adapter
├── backend/            bridge.lua + driver/ (registry, tmux, resources/tmux)
├── frontend/           terminal, display, note, review, picker/
└── commands/           dispatch + flows (attach, gather, kill, prompt, review)
```

Six categories, each with a fixed set of things it may import. `make check`
runs `scripts/verify-architecture.lua`, whose `ALLOWED` table is exactly this
graph; a module that imports against it fails the gate.

```
                 composition (init.lua)
                   │
      ┌────────────┼───────────────┐
      ▼            ▼               ▼
  commands ──▶ frontend ──────▶ backend
      │            │               │
      └────────────┴───────┬───────┘
                           ▼
                        shared (config, util)

  health ──▶ backend, frontend, shared        (nothing imports health)
```

- `composition` — `init.lua`. The only module that reaches every other
  category, and the only one nothing imports. `setup()` applies configuration,
  resolves the configured Driver and Picker, then installs Prompt/Review hooks
  and the `:Vantage` command.
- `commands` — orchestrates flows and imports `frontend/`, `backend/`, its own
  pieces, and shared modules.
- `frontend` — imports `backend/` (through the Bridge) and its own pieces.
- `backend` — imports only shared modules.
- `shared` — `config.lua` and `util.lua`, importable by every category and
  importing nothing but itself. It is a dependency-checking category, not a
  domain term: the [glossary](glossary.md) is where domain words live. The
  verifier files any module path it cannot classify here. A seam's contract
  types live with their seam — `vantage.Driver` in `backend/driver/init.lua`,
  the picker contract in `frontend/picker/init.lua`, `vantage.NoteOpts` in
  `frontend/note.lua`; `config.lua` keeps the option types and the reference
  spelling.
- `health` — `health.lua`, the diagnostics adapter. It may inspect Backend and
  Frontend but never the command layer, and no module imports it: Neovim calls
  it through `:checkhealth`.

Configuration is fail-fast. An unknown backend/picker name, an unavailable
implementation, or a missing picker dependency raises during `setup()`; no
fallback implementation is installed. Driver/Picker are resolved once and
cached; `get()` before `setup()` is a programming error. `health.lua` catches
that error and reports it.

`Config.options` remains the global configuration singleton. `Config.apply()`
owns defaults, merging, `cli.tools` validation, and the default reference
spelling every surviving Tool without a `format` hook gets;
`Config.tool_reference` is the only place a reference is spelled. Runtime
lifecycle belongs to the composition root.

## The multiplexer substrate

The plugin drives a private socket (default `vantage`, configurable via
`setup { socket = … }`) and keeps all domain state in multiplexer objects and
window options (`@agent-group`, `@agent-cmd`, `@agent-cwd`, `@agent-tool`,
`@agent-state`). Global server config — default terminal, history limit, focus
events, no status line, a 1-second status interval, and a top pane border
whose format shows `Group · Tool · cwd` plus per-Group State counts, and the
`client-detached` View cleanup hook — is applied exactly once, when the first
`new-session` starts the server. The counts are computed read-only per tick by
the tmux Driver's `counts.sh` resource inside a `#()` substitution,
deduplicated to one run per Group.

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
  client exiting) ends the attachment. The [Focus](glossary.md#focus) is
  derived from the live state on every read, never stored Neovim-side.

## Seams and contracts

**Driver** (`backend/driver/init.lua` resolves the configured module from a
whitelist):

- `create({ group, cmd, cwd, tool })` → `Agent, nil` or `nil, err`; creating
  the Group (and on the first creation the server and its config). Metadata
  failures roll back the partial Agent.
- `agents()` → `Agent[], nil` or `nil, err`: the live inventory in creation
  order. A missing server reads as an empty inventory, not as an error.
- `client_window(pid)` → `window, nil`, `nil, nil`, or `nil, err`: the window
  the client with that pid displays, as the Driver's own opaque id. No client
  with that pid is `nil, nil` (a normal answer); a missing server is `nil` plus
  the reason, so "no Terminal client" and "nothing is running" stay distinct.
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
`inventory()`, `focus(pid?)`, `client_window(pid)`, `create`, `retarget(pid,
agent)`, `send(agent, text)`, `capture(agent)`, `attach(agent)`,
`kill_view(view)`, `kill_agent`, `kill_group`, `status`. It holds no state and
does no UI; the prompt flow resolves the Focus and renders templates, then
hands the Bridge the final text.

The two reads are separate because they answer different questions.
`inventory()` returns the flat Agent list plus the Groups derived from it (each
Group once, in the Agents' order) and never reads the clients, so a caller that
does not care what the Terminal shows — the kill flow, the Group prompt — does
not pay for the extra multiplexer query. `focus(pid)` is the [Focus](glossary.md#focus)
read: it matches `client_window(pid)` against the inventory and returns the
Agent, or `nil` plus one of the reasons in `config.lua` (`FOCUS_NO_TERMINAL`,
`FOCUS_NO_CLIENT`, `FOCUS_NO_FOCUS`, `FOCUS_SERVER_DOWN`) or the Driver's own
error. Callers report that string as-is; nothing branches on which reason it
is, so the reasons are messages rather than a cause vocabulary. The Bridge
never reaches for the Terminal's pid itself: the command layer passes it in,
keeping the Backend from importing the Frontend.

A Tool's reference spelling is configuration, not Backend state:
`Config.apply()` gives every surviving `cli.tools` entry a `format` (defaulting
to config's own default), and `Config.tool_reference(tool, cwd, path,
start_row, end_row)` is the one place a reference is spelled — it relativizes
the path against the Agent's cwd, builds the `:L` suffix from the position,
applies the hook, and reads a nil or "" return as "no reference". `tool` is nil
with no Focus, or names a Tool a later setup dropped; both spell the default
form, which is how an Agent created under a since-dropped Tool still renders.
The read-split, the reference-spelling owner, and where seam types live are
recorded in
[focus-is-its-own-read](../.agents/notes/implemented/architecture/2026-09-13-focus-is-its-own-read.md),
[reference-spelling-has-one-owner](../.agents/notes/implemented/architecture/2026-09-13-reference-spelling-has-one-owner.md),
and
[seam-types-live-with-their-seam](../.agents/notes/implemented/architecture/2026-09-13-seam-types-live-with-their-seam.md).

**Terminal** (`frontend/terminal.lua`) is a dumb display surface: `open(argv)`
starts the terminal job, `show`/`hide` manage the window without killing the
job, `destroy` stops the job and deletes the buffer, and a `TermClose` autocmd
does the same whenever the client exits. One Terminal per Neovim instance.

**Picker** (`frontend/picker/init.lua`) is a facade over a pluggable renderer.
Commands call `Picker.pick(spec, opts)`, `Picker.pick_multi(spec, opts)`, or
`Picker.pick_plain(...)`; `get()` is internal. A picker declares exactly three
capabilities:

- `preview` — it can render `item:preview()`.
- `command` — it can bind the flow's picker commands.
- `multi` — it can confirm several rows at once.

A picker without `multi` renders a multi-selection request as a single choice,
so `on_choices` always receives a list. `PickOpts` carries `on_choice` and
optional `commands`/`on_close`; `PickMultiOpts` carries `on_choices` and the
same optional `on_close`, run whenever the picker closes.

`opts.commands` is a list of keymap-shaped descriptors
`{ lhs, rhs, desc? }`, where `rhs(ctx)` receives `{ item, items }` and returns
`true` when the item list may have changed. A true result re-reads
`items_provider` and refreshes (or closes on an empty result). Commands are
global to the picker UI; the facade rejects duplicate `lhs` values and drops
commands for a picker without the `command` capability. Group scoping is an
ordinary command, not a Picker concept.

## Flows and the command surface

- `commands/attach.lua` owns `toggle`/`switch` plus their shared
  Agent/Tool rows, Group choice, creation handoff, and the `<c-g>` scope and
  `<c-x>` kill commands. A row is data: choosing one returns a selection
  (`focused`, an Agent, or a Tool to create from), and the flow — not the row —
  creates, retargets, or opens the Terminal. `toggle` and `switch` each keep
  their own tail; only the "attach and install the terminal keymaps" step is
  shared.
- `commands/gather.lua` owns the `files` and `buffers` Terminal actions: it
  lists candidates under the Focus's cwd (fd → ripgrep → a Lua walk), spells
  every chosen `<relpath>` through the Tool's `format`, joins the results with
  `setup { gather = { join = … } }`, and pastes them with a trailing space. One
  reference dropped by the hook drops the whole send.
- `commands/actions.lua` maps Terminal actions (`toggle`, `switch`, `prompt`,
  `files`, `buffers`) to command functions and installs `cli.win.keys` into the
  terminal buffer.
- `:Vantage toggle` owns presence: hide/show; with no Terminal, pick an Agent
  (Tool rows create one) and open the Terminal on it.
- `switch` (terminal token) owns target: `retarget` to the resolved Agent.
- `:Vantage detach` destroys the Terminal; Agents and Groups survive.
- `:Vantage status` shows the Driver's session/client summary.
- `:Vantage review [list|clear]` manages Reviews (bare adds over the range);
  the `{reviews}` placeholder batches them into a Prompt.
- `:Vantage kill` picks an Agent or Group and kills it.
- Terminal actions via `cli.win.keys`: `switch`, `prompt`, `toggle`, `files`,
  `buffers`.

Creating an Agent from a Tool row resolves the tool to its command, uses the
global Neovim cwd, and always asks for a Group; `retarget` identifies the
Terminal's client by the terminal job's pid, which the command layer reads from
the Terminal and passes in.

`:Vantage` subcommands are dispatched from `commands/init.lua`; the prompts,
gather, and review flows resolve the Focus before acting and warn the reason
string when there is none.

## Review and Prompt

Reviews live entirely in memory (`frontend/review.lua`: extmark + per-buffer
registry) and render through `setup { reviews = { item = … } }`; the Prompt
vocabulary (`{file}`, `{line}`, `{reviews}`) is the prompt flow's own resolver
keys, and `Prompt.setup()` warns about a configured template that names an
unknown token — `health.lua` may not import the command layer. Prompt text and
gathered references are pasted with bracketed paste and never auto-submit.
Every location reference — a Prompt's placeholders, each Review's `{lines}` /
`{file}`, and each gathered row — is spelled by the Focus's Tool through
`Config.tool_reference` (default: `file` and its `loc` suffix separated by a
space), and `gather.join` decides how gathered references are joined.
