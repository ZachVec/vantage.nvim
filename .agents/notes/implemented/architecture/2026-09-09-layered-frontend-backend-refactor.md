# Agent Note: Layered frontend/backend refactor — Backend verbs, uniform entries

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

- `backend/init.lua` is the Backend's public surface and the Driver seam: the
  domain verbs (`inventory()` → the flat Agents plus the Groups derived from
  them, `create`, `send`, `capture`, `attach`, `kill_agent`, `kill_group`,
  `status`, `health`), the `REGISTRY`/`REQUIRED` pair that resolves and checks
  the configured driver (a whitelist; an unknown or unavailable name fails fast
  at `setup()`, per
  [composition-root-and-neutral-seams](2026-09-10-composition-root-and-neutral-seams.md)),
  and the Focus and re-target methods on the Attachment `attach` returns. It
  knows no UI and holds no state. The later
  [one-layer, View-keyed Attachment note](2026-09-20-backend-one-layer-and-view-keyed-attachment.md)
  folded the registry and the contract into that one file.
- `tmux.lua` is pure tmux mapping with the domain-shaped verbs `create`,
  `agents()`, `attach(agent, launch)`, `kill_agent`, `kill_group`, `send_keys`,
  `capture_pane`, `status`, `health`. zellij remains a distant seam only; no
  compatibility promise hardens the interface for it.

Domain model:

- **Group** = one tmux session group; **Agent** = one single-pane window in its
  Anchor,
  carrying the `@agent-*` options. The attachment is the terminal's tmux
  client pointing at (Group, Agent). This note originally deleted View, Anchor,
  session groups, and the client-detached hook; that premise was false and is
  superseded by
  [restore-per-client-views](2026-09-10-restore-per-client-views.md), which
  restores the session-group model.
- The server starts on the first `create` (`new-session`, which applies the
  global config exactly once per server start); no verb re-checks it. External
  kills surface as warnings on the next operation; there is no watchdog or
  reconciliation. `agents()` reads `list-windows` and the Attachment's
  `focus()` reads the View's current window with its Agent fields in one
  session-targeted query, so a caller that needs only the inventory never pays
  for the Focus read.
- `retarget(agent)` is the single switch verb (`select-window`, or
  `switch-client` across Groups), handling same-Group window changes and
  cross-Group relocation alike; the client is identified by the View its
  Attachment holds.

Frontend:

- `frontend/terminal.lua` is a dumb display surface: `open(argv)` starts the
  terminal job, `hold(attachment)` keeps the handle its client sits on,
  `show`/`hide`/`destroy` manage the window, and `TermClose` closes the window,
  deletes the buffer, and resets state — the attachment's lifecycle is the
  terminal's lifecycle. It stores no domain state and never resolves the Focus
  itself (the Attachment answers it).
- Each command offers its own entries: the attach flow Agent and Tool
  entries, the kill flow Agent and Group entries, the review flow Review
  entries — all built by the shared vocabulary in `frontend/entries.lua`,
  whose `kind` the flow branches on
  ([picker entries are data](2026-09-13-picker-entries-are-data.md)). No entry
  carries a flow action: the attach flow's `<c-x>` kill and `<c-g>` scope
  toggle are flow-owned picker commands, not entry methods. The `<c-x>` command
  kills the entry's Agent in place; the pinned `(focused)` entry and Tool
  entries are no-ops, with the behavior owned by the
  [restored kill note](../bug-fix/2026-09-10-agent-picker-cx-kill-restored.md).
- Picker implementations stay pure renderers over the flow's entries and
  flow-owned commands: text, preview, and `on_choice`, with the `<c-x>`
  kill/delete and the `<c-g>` scope toggle arriving as the `{ lhs, rhs, desc }`
  descriptors the
  [composition root](2026-09-10-composition-root-and-neutral-seams.md) owns.
  The `from_terminal` flag is deleted: a picker detects the terminal window at
  open time by filetype.

Commands:

- `:Vantage` subcommands: `show`, `hide`, `detach`, `status`, `review`, `kill`.
- Terminal tokens via `cli.win.keys` (resolved in `commands/init.lua`, installed
  by the Terminal on its own buffer):
  `hide`, `switch`, `prompt`, `files`, `buffers`. These exist only inside the
  terminal; `kill` moved out to a command.
- Presence and target are separate commands: `show` owns presence (focus,
  re-open, or with no terminal pick-or-create then attach+show) and `hide`
  closes the window and keeps the client; `switch` owns target (`retarget`).
  The pick flow is shared; only the tail after `resolve()` differs, and that
  tail lives in each command — no callback is injected into entries.

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

### Why not keep entry methods (`resolve()`, `delete()`) instead of a `kind`?

They kept each flow's choice handler to one polymorphic line, but the price was
a second contract behind the Picker's: each flow declared its own classes, the
same Agent text and pane preview existed twice, and an implementation could
write into the flow's own entry. The `kind` field the flows already needed for
their own dispatch keeps one surface
([picker entries are data](2026-09-13-picker-entries-are-data.md)).

### Why not keep `activate(after)` with an injected flow tail?

Injection makes an entry's behavior depend on which flow built it and, for Tool
entries, smuggles a picker sub-flow into a method. The flow's own handler
inverts the direction: it reads the entry's target off the data and applies its
own tail.

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
  become `hide`/`switch`/`prompt`/`files`/`buffers`.
- The Agent list's in-place `<c-x>` kill was later restored under flow-owned
  commands (the
  [restored kill note](../bug-fix/2026-09-10-agent-picker-cx-kill-restored.md));
  the Review list's `<c-x>` deletion is the same shape — a flow-owned picker
  command, not an entry method.
- Each nvim instance has at most one terminal, whose client is identified by
  the Attachment's View. The later
  [restore-per-client-views](2026-09-10-restore-per-client-views.md) note
  restores a View session per client so several instances can attach to one
  Group and show different Agents independently, and
  [backend-one-layer-and-view-keyed-attachment](2026-09-20-backend-one-layer-and-view-keyed-attachment.md)
  moves that identity off the terminal job's pid and onto the View.
- `:Vantage kill` is a new user command; `switch`/`prompt` remain
  terminal-only, and there is no `:Vantage switch`/`:Vantage prompt`.
- Tests mirror the layers (`tests/backend`, `tests/frontend`, `tests/commands`).
- Superseded decisions are archived: cross-group switch relocation and the
  Agent-picker `<c-x>` kill. The Group/Anchor/View removal is itself superseded by
  [restore-per-client-views](2026-09-10-restore-per-client-views.md).
