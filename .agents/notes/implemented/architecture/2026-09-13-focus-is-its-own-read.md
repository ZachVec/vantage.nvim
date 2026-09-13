# Agent Note: Focus is its own read

Status: implemented

## Problem

`Bridge.agents(pid)` answered two different questions with one return value:
the live Agent inventory, and which Agent the Terminal's client is showing. The
pid was therefore optional, and each caller had to know which half it wanted:

- `commands/attach.lua` and `commands/kill.lua` passed `nil` for the inventory;
- `commands/attach.lua`'s pick spec and `commands/send.lua` passed the Terminal's
  pid for the Focus;
- every caller that wanted the Focus checked `snapshot.focused` itself and
  carried its own copy of the "no focused agent — use :Vantage toggle first"
  message. Four call sites resolved the same fact three different ways.

`commands/send.lua` had also accumulated three unrelated jobs — resolve the
Focus, hand out a Tool's reference spelling, and shape gathered references —
even though `commands/` is where flows live. Its reference-spelling half
duplicated what `Config` already owned (`vantage.Tool.format` had exactly one
reader, and `frontend/review.lua` defaulted to `Util.reference` on its own).

## Decision

**One read per question.** The Driver exposes `agents()` (the inventory, in
creation order; a missing server reads as empty) and `client_window(pid)` (the
window that client displays, as the Driver's own opaque id; no client with that
pid is `nil, nil`, a missing server is `nil` plus the reason). `snapshot(pid)`
is gone. The Bridge composes them:

- `Bridge.inventory()` → `{ agents, groups }`: Groups derived from the Agents,
  each once, in the Agents' order. It never reads clients, so the kill flow and
  the Group prompt do not pay for a client query.
- `Bridge.focus(pid?)` → `Agent?, string?`: the Focus. `nil` comes with the
  reason — `Config.FOCUS_NO_TERMINAL`, `FOCUS_NO_CLIENT`, `FOCUS_NO_FOCUS`, or
  the Driver's own error. Callers report that string as-is; nothing branches on
  which reason it is, so the reasons stay messages rather than a cause
  vocabulary.
- `Bridge.client_window(pid)` passes the window read through for callers that
  need the raw fact.

The command layer passes the pid in (`Terminal.pid()`); the Backend never
reaches for it, which keeps `frontend → backend` one-way.

**Reference spelling is configuration.** `Config.apply()` gives every surviving
`cli.tools` entry a `format` (default `Util.reference`), and
`Config.tool_format(name)` is the only reader — it falls back to
`Util.reference` for a Tool name that is no longer configured, so an Agent
created under a since-dropped Tool still renders. No caller carries the
"user configured no hook" case any more.

**`commands/send.lua` is deleted.** `commands/` holds `init.lua` and flows:
`commands/gather.lua` owns its own loop (spell each chosen path, join with
`setup { gather = { join = … } }`, paste with a trailing space, drop the whole
send when the hook drops one reference), and the other flows read the Focus and
the Tool spelling through the Bridge and `Config`.

**Focus is a term.** `docs/glossary.md` defines it: the Agent this Neovim
instance's Terminal is showing, derived on every read, never stored.

**The dependency categories are written down.** `docs/architecture.md` names
all six categories the gate enforces (`composition`, `commands`, `frontend`,
`backend`, `shared`, `health`) and their directions, and states that `shared`
is a dependency-checking category rather than a domain term.

### Why the picker's row protocol changed with it

Choosing an Agent-list row used to run flow code from inside the row
(`target(done)`), which made a Tool row start a second picker and create the
Agent itself, and made a cancelled Group choice end the whole flow silently.
Rows are now data: `select()` returns `{ kind = "focused" | "agent" | "new" }`,
and the flow — which owns creation, `retarget`, and opening the Terminal —
applies it. This is the shape
[layered-frontend-backend-refactor](2026-09-09-layered-frontend-backend-refactor.md)
already called for ("no callback is injected into entries"); the code had
drifted back.

## Alternatives considered

### Why not keep one combined `snapshot(pid)` read?

It was one fork instead of two, and it guaranteed the inventory and the Focus
came from the same instant — the reasoning in
[shared-interpolation-and-backend-snapshot](../../archived/architecture/2026-09-07-shared-interpolation-and-backend-snapshot.md).
What it cost was an interface where the pid was optional and the return value
mixed two answers, so every caller re-derived its own half. The split is
cheaper for the inventory-only callers (`kill`, the Group prompt), and the two
reads a Focus costs are the same two queries the combined read ran. The
caller-side simplification is worth the lost instant-coherence: the Focus and
the row list are already a live view that can change under the picker.

### Why not return a cause constant instead of a message?

Because no caller branches. All three current consumers warn the reason and
return, or (in `commands/review.lua`) ignore it and fall back to the plain
spelling. A four-value enum with no branching consumer is documentation-only
vocabulary; a message is what the callers actually need. If a future flow wants
to act on "no Terminal" differently from "Terminal's client is gone", that
change can promote the reasons to a typed shape.

### Why not put the Focus read in the Frontend rather than the Backend?

The fact being read — which tmux window a client displays — is multiplexer
state, and the Backend already owns every other read of it. A Frontend module
composing `Terminal.pid()` with two Bridge calls would move the matching rule
out of the Backend and give the Frontend a reason to know about window ids.

### Why not give `Config.apply` a `formatter` concept instead of defaulting `format`?

A second name would keep the two-case lookup ("is a hook configured?") that the
default removes. The default is also what makes the invariant checkable:
`format` exists on every surviving Tool, and `Config.tool_format` is its only
reader.

## Consequences

- One Focus read for every flow; no flow carries its own "no focused agent"
  check or message.
- `commands/` contains only `init.lua` and flows; the shared send path is gone.
- The reference-spelling default is configuration, resolved once at setup.
- `vantage.Driver` has 12 verbs; the conformance list in
  `tests/backend/driver_tmux_spec.lua`, `driver/init.lua`'s `REQUIRED`, and
  `config.lua`'s `vantage.Driver` type must stay in step (a known duplication,
  owned by the record-shape work in `docs/architecture.md`).
- `README.md` and `doc/vantage.nvim.txt` are unchanged: no user-visible
  command, option, default, or behavior moved.
- The Focus read's reasons live in `config.lua` next to
  `PROMPT_PLACEHOLDERS`, since both are contracts shared across layers.
