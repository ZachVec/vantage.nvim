# Vantage Architecture

A coding-agent manager built as a Neovim plugin. The [Backend](glossary.md#backend) is a domain layer over a pluggable multiplexer [Driver](glossary.md#driver) (tmux today, room for zellij later); the [Frontend](glossary.md#frontend) is the plugin's own UI — a pluggable [Picker](glossary.md#picker) plus a single `:terminal` that is the [Terminal](glossary.md#terminal). tmux is the state store, multiplexer, renderer, and input layer; there is no custom TUI.

Terminology lives in the [glossary](glossary.md); this file describes how the pieces relate and the invariants that hold them together.

## Composition root and one-way dependencies

```
lua/vantage/
├── init.lua            composition root: apply config, resolve, install
├── config.lua / util.lua   shared configuration + helpers
├── health.lua          diagnostics adapter
├── backend/            init.lua (surface + Driver seam), tmux.lua, resources/tmux/
├── frontend/           terminal, entries, review, picker/
└── commands/           dispatch + Terminal actions + flows (attach, gather, kill, prompt, review)
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
  resolves the configured Driver and Picker, then installs Prompt/Review hooks,
  the Terminal's action resolver, and the `:Vantage` command.
- `commands` — orchestrates flows and imports `frontend/`, `backend/`, its own
  pieces, and shared modules.
- `frontend` — imports `backend/` and its own pieces.
- `backend` — imports only shared modules.
- `shared` — `config.lua` and `util.lua`, importable by every category and
  importing nothing but itself. It is a dependency-checking category, not a
  domain term: the [glossary](glossary.md) is where domain words live. The
  verifier files any module path it cannot classify here. A seam's contract
  types live with their seam — `vantage.Driver` in `backend/init.lua`
  and the picker contract in `frontend/picker/init.lua`; `config.lua` keeps the
  option types and the reference spelling.
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

The plugin drives a private socket — the tmux Driver's own option, default
`vantage`, set under `setup { backend_opts = { tmux = { socket = … } } }`, so
the shared option table names no multiplexer concept — and keeps all domain
state in multiplexer objects and window options (`@agent-group`, `@agent-cmd`,
`@agent-cwd`, `@agent-tool`, `@agent-state`). Global server config — default
terminal, history limit, focus events, no status line, a 1-second status
interval, and a top pane border whose format shows `Group · Tool · cwd` plus
per-Group State counts, and the `client-detached` View cleanup hook — is
applied exactly once, when the first `new-session` starts the server. The
counts are computed read-only per tick by the tmux Driver's `counts.sh`
resource inside a `#()` substitution, deduplicated to one run per Group; both
Driver resources take the socket with `-L`, so the configured name has one
owner.

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
  client exiting) ends the attachment. The Driver hands back an Attachment
  handle for it — the View the client sits on, with `focus` and `retarget`
  answering from live state — and the Terminal holds that handle for as long as
  its job lives. The [Focus](glossary.md#focus) is derived from the live state
  on every read, never stored Neovim-side.

## Seams and contracts

**Driver** (`backend/init.lua` resolves the configured module from a
whitelist):

- `create({ group, cmd, cwd, tool })` → `Agent, nil` or `nil, err`; creating
  the Group (and on the first creation the server and its config). Metadata
  failures roll back the partial Agent.
- `agents()` → `Agent[], nil` or `nil, err`: the live inventory in creation
  order. A missing server reads as an empty inventory, not as an error.
- `attach(agent, launch)` → `Attachment, nil` or `nil, err`: creates a fresh
  View, calls `launch(argv)` to put this Terminal's client on it, and destroys
  the View again when the client cannot start, so a failed start leaves no
  session behind. The View itself never leaves the Driver.
- The returned `Attachment` is the handle for that client. `focus()` answers
  the [Focus](glossary.md#focus) — the Agent the View's client displays, read
  from the View's current window and that window's Agent fields in one query,
  with a window that carries no Agent metadata answering `FOCUS_NO_FOCUS` — and
  `retarget(agent)` re-points the client, selecting a window in the same View
  or moving it into a fresh View of another Group and adopting that one. A
  View that is gone answers the multiplexer's own reason.
- `kill_agent(agent)` / `kill_group(group)` → `true` or `false, err`.
  `kill_group` destroys the Anchor and every View.
- `send_keys(agent, text)` → `true` or `false, err`; temporary buffers are
  cleaned up.
- `capture_pane(agent, max_lines?)` → `lines, nil` or `nil, err`;
  `status()` → `{ clients, sessions }, nil` or `nil, err`;
  `health()` → health-check records.

The Driver returns errors and never notifies the user. The Backend passes
results through; command flows decide how to report them.

`backend/init.lua` is the Frontend's only door to the Backend: `inventory()`,
`create`, `send(agent, text)`, `capture(agent)`, `attach(agent, launch)`,
`kill_agent`, `kill_group`, `status`, `health`. It holds no state and does no UI; the
prompt flow renders templates against the Focus its Attachment answers, then
hands the Backend the final text. Everything that needs a live Terminal client
lives on that Attachment and everything else lives here: no verb above the seam
takes a process pid.

The two reads are separate because they answer different questions.
`inventory()` returns the flat Agent list plus the Groups derived from it (each
Group once, in the Agents' order) and never reads the clients, so a caller that
does not care what the Terminal shows — the kill flow, the Group prompt — does
not pay for the extra multiplexer query. The [Focus](glossary.md#focus) is the
other read, and only the Terminal's own Attachment answers it: one query reads
the View's current window and that window's Agent fields together, and a window
that carries no Agent metadata is `no focused agent` rather than an error.
Callers report the reason string as-is; nothing branches on which reason it is,
so the reasons are messages rather than a cause vocabulary. A Neovim instance
with no Terminal has no Attachment at all — that fact stays in the Frontend,
which is why the Backend never reaches for a pid.

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

**Terminal** (`frontend/terminal.lua`) is a dumb display surface:
`setup(resolve)` installs the resolver that says what a `cli.win.keys` `rhs`
string means and the window-entry rule that owns the Terminal's mode (entering
its window restores terminal mode, since the Terminal has no Normal-mode state
of its own), and `open(argv)` starts the terminal job and installs
`cli.win.keys` on the buffer it just created; `hold(attachment)` keeps the
Attachment its client sits on (identity, never domain state), `show`/`hide`
manage the window without killing the job, `destroy` stops the job and deletes
the buffer, and a `TermClose` autocmd does the same whenever the client exits.
One Terminal per Neovim instance.

**Picker** (`frontend/picker/init.lua`) is a facade over a pluggable renderer.
Commands call `Picker.pick_fancy(spec, opts)` or `Picker.pick_naive(...)`;
`get()` is internal. A picker declares one capability: `command` — it can bind
the flow's picker commands. A pick beside its prompt states `many` (how many
entries the flow acts on) and `preview` (the standard preview function, when it
wants a preview pane); neither needs a capability declaration, because an
implementation that cannot confirm several or render a pane simply degrades —
`native` drains the stream and shows one choice, and shows no pane.

`spec.items` is the pick's item stream, written by the flow: `emit(chunk)`
appends entries as they are produced, `done()` ends the run, and the optional
return stops a run the picker outlived. An implementation starts it once per
engine run — the opening run, and a fresh run whenever a command reports that
the list may have changed — so a pick can show entries while the flow is still
producing them, while an engine with no stream surface waits for the run to end
and picks from the final list.

What a pick offers is a list of Entries — the shared type is
`vantage.picker.Entry` in `frontend/picker/init.lua`, and the vocabulary that
builds them is `frontend/entries.lua` (`Entries.agent`, `.tool`, `.group`,
`.file`, `.buffer`, `.review`). An Entry carries `text` (the line the
implementation renders), `kind` (the flow's own name for it), and whatever
fields the flow put there — plain data with no preview of its own. A flow asks
for a preview pane by handing `spec.preview` the one preview function the
entries module owns (`Entries.preview`), which answers the highlighted Entry's
lines by kind: nil for a kind with nothing to show, which keeps the pane and
leaves it empty. Implementations read `text` and call `spec.preview`; they
never write to an Entry, and the flow — not the Entry — decides what choosing
one means.

`on_choices` is the one selection callback and always receives at least one
entry: a picker that cannot confirm several answers with a one-element list, so
a flow that acts on a single entry reads `entries[1]`. An implementation owns
what its own close does: it leaves the window the pick was invoked from
current and compensates for its own teardown whenever its engine loses that
window, and lets the window's own owner settle the mode (a Vantage Terminal
restores terminal mode on window entry) — so no flow restores a window or a
mode, and no flow passes a close callback. `native` delegates that, like
everything else, to the global `vim.ui.select` (`docs/gotchas.md` records the
engine mechanics: snacks' `stopinsert` and Neovim's float-close fallback on one
side, fzf-lua's own `set_current_win(src_winid)` on the other).

A pick that has nothing to show opens empty and stays open until the user
cancels it: the "no agents" / "nothing to kill" warnings went with the design
that read the list before opening. A read that fails is the flow's own to
report, from inside its stream.

`opts.commands` is a list of keymap-shaped descriptors
`{ lhs, rhs, desc? }`, where `rhs(ctx)` receives `{ item, items }` and returns
`true` when the item list may have changed; a true result starts a fresh item
stream and refreshes the picker. Commands are global to the picker UI; the
facade rejects duplicate `lhs` values and drops commands for a picker without
the `command` capability. Group scoping is an ordinary command, not a Picker
concept.

## Flows and the command surface

- `commands/attach.lua` owns `show`/`switch` plus their shared
  Agent/Tool entries, Group choice, creation handoff, and the `<c-g>` scope and
  `<c-x>` kill commands. An Entry is data: its `kind` (`focused`, `agent`,
  `tool`) says what choosing it means, and the flow — not the Entry — creates,
  retargets, or opens the Terminal. `show` and `switch` each keep their own
  tail; only the "attach a client and hold it" step is shared.
- `commands/gather.lua` owns the `files` and `buffers` Terminal actions: it
  lists candidates under Neovim's global cwd — the tree the user browses,
  which the Focus's cwd need not contain (fd → ripgrep → find, streamed as the
  lister prints them), spells every chosen reference against the Focus's cwd
  through the Tool's `format` (relative inside it, absolute outside), joins the
  results with `setup { gather = { join = … } }`, and pastes them with a
  trailing space. One reference dropped by the hook drops the whole send.
- `commands/init.lua` owns the Terminal action tokens (`hide`, `switch`,
  `prompt`, `files`, `buffers`) — the strings a `cli.win.keys` `rhs` may name —
  and resolves each to the function that runs it, next to the `:Vantage`
  dispatch. The Terminal installs `cli.win.keys` on its own buffer and resolves
  each entry through that resolver, which the composition root installs at
  setup, because the Frontend may not import the command layer.
- `:Vantage show` owns presence: focus the Terminal when it is up, re-open the
  same buffer when it is hidden, and with no Terminal pick an Agent (Tool
  entries create one) and open the Terminal on it. The Frontend's `show`
  answers false when there is no client, so "which Agent" stays a command-layer
  decision.
- `:Vantage hide` (and the `hide` token) closes the Terminal's window and keeps
  the client attached. The key that hides never has to ask whether a Terminal
  exists, and the token set has no `show` — a token is installed on the
  Terminal's own buffer, where that window is open by construction.
- `switch` (terminal token) owns target: `retarget` to the resolved Agent.
- `:Vantage detach` destroys the Terminal; Agents and Groups survive.
- `:Vantage status` shows the Driver's session/client summary.
- `:Vantage review [list|clear]` manages Reviews (bare adds over the range);
  the `{reviews}` placeholder batches them into a Prompt.
- `:Vantage kill` picks an Agent or Group and kills it.
- Terminal actions via `cli.win.keys`: `hide`, `switch`, `prompt`, `files`,
  `buffers`.

Creating an Agent from a Tool entry resolves the tool to its command, uses the
global Neovim cwd, and always asks for a Group; `switch` re-points the client
through the Attachment the Terminal holds.

`:Vantage` subcommands are dispatched from `commands/init.lua`; the prompt and
gather flows resolve the Focus before acting and warn the reason string when
there is none. The Review list resolves it only to spell its entries: the base
is the Focus's Cwd and its Tool dialect, or Neovim's cwd and the default
dialect when no Terminal is attached.

## Review and Prompt

Reviews live entirely in memory (`frontend/review.lua`: extmark + per-buffer
registry) and render through `setup { reviews = { item = … } }`; the Prompt
vocabulary (`{file}`, `{line}`, `{reviews}`) is the prompt flow's own resolver
keys, and `Prompt.setup()` warns about a configured template that names an
unknown token — `health.lua` may not import the command layer. Prompt text and
gathered references are pasted with bracketed paste and never auto-submit.
Every location reference — a Prompt's placeholders, each Review's `{lines}` /
`{file}`, and each gathered entry — is spelled by the Focus's Tool through
`Config.tool_reference` (default: `file` and its `loc` suffix separated by a
space), and `gather.join` decides how gathered references are joined. A Review
reads the same in the list, in its preview, and in the `{reviews}` send — an
entry is the `{lines}` reference plus the note's first line — and the note
float's title names no reference of its own. `frontend/review.lua` also owns
that editing float (`Review.edit` / `Review.create`), including the jump, the
active tint, and the empty-deletes policy; the command layer only wires the
list and the add range.
