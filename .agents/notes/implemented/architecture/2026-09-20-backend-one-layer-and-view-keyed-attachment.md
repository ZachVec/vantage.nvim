# Agent Note: One Backend layer, and the Attachment is the View's handle

Status: implemented

## Problem

Two Backend shapes had outlived their reasons.

The plugin's door to the Backend and the Driver seam were two files —
`backend/init.lua` and `backend/driver/init.lua`. The split was residue: the
layered refactor created `backend/bridge.lua` beside `backend/driver/`, and the
bridge was later renamed into place
([backend-surface-at-init-lua](2026-09-13-backend-surface-at-init-lua.md)). The
architecture gate files every `backend/**` module in one layer, so nothing
enforced the split: it only made a Driver author read one file for the contract
and another for the registry, and made the Backend's own door a different file
from the contract it used.

The plugin also identified its own client by the **process pid** of the
Terminal's job. `focus(pid)` and `retarget(pid, agent)` scanned `list-clients`
for `client_pid == pid`; `attach(agent)` returned the raw View name and argv,
and the command layer held that View name only long enough to hand it back to
`kill_view(view)` when the Terminal could not start. That made an OS-level
coincidence load-bearing — the multiplexer's client pid equals the pid Neovim
spawned — and put the Driver's own handle (a tmux session name) on the Backend's
interface.

## Decision

`backend/` is one layer. `backend/init.lua` is both the Backend's surface and
the `vantage.Driver` seam — types, `REGISTRY`, `REQUIRED`, `setup`/`get`/`reset`
— and `backend/tmux.lua` implements the seam, with the tmux resources under
`backend/resources/tmux/`. The composition root and `health.lua` go through
`vantage.backend` alone; there is no `backend/driver/` module.

The attachment is identified by its **View**, not by a pid:

- `attach(agent, launch)` creates the View, calls `launch(argv)` to start the
  Terminal's client on it, and destroys the View again when the client cannot
  start. The View itself never leaves the Driver.
- It returns a `vantage.Attachment` whose `focus()` reads the View's current
  window and that window's Agent fields in one session-targeted query, and
  whose `retarget(agent)` selects a window in the same View or moves the client
  into a fresh View of another Group and adopts that one.
- The Terminal holds the handle (`Terminal.hold`) and clears it with the job.
  `Terminal.pid()`, `Backend.focus`, `Backend.retarget`, `Backend.kill_view`,
  `Config.FOCUS_NO_TERMINAL`, and `Config.FOCUS_NO_CLIENT` are gone;
  `FOCUS_NO_FOCUS` stays, because a client on a window without Agent metadata
  is still a real answer.

The Attachment carries identity only. It never caches an Agent, Group, or View:
each call answers from live state, and a cross-Group `retarget` adopts the new
View *before* cleaning the old one up, so a failed cleanup cannot leave the
handle pointing where the client no longer is. Caching would repeat the
`last_agent` mistake retired by
[focused-agent-owned-by-backend](2026-09-07-focused-agent-owned-by-backend.md).

## Alternatives considered

**Keep the two-file Backend.** The split is residue, not a seam: `REQUIRED` and
the type it validates were already in one file, and the facade's forwards were
the same verb list again. One layer means the module callers import, the
contract implementations satisfy, and the types they share are the same file.

**Keep the pid as the attachment's identity.** The pid is borrowed from the OS
and holds only while the multiplexer's client is our direct child — an
assumption a second Driver need not satisfy. It also costs more: every
`retarget` paid a full `list-clients` scan plus `session_group` and `is_view`
probes, and every `focus` scanned all clients. A View is created by `attach`,
is 1:1 with its client by construction, and answers a Focus read on its own.

**Identify the client by its tty.** A tty is where a client is *addressable*
(`switch-client -c <tty>`), not who it is: Neovim exposes no pty path for a
terminal job, so getting one would mean reading `/proc` or shelling out to `ps`
on top of the pid we already have. The tty stays what it always was — the
address the cross-Group move looks up from the View when it needs one.

**Derive the View's name instead of holding a handle.** A derived name cannot
survive a cross-Group move: the client must be put on a fresh View while it is
still sitting on the old one, so the move would have to end in a rename dance.
A handle can change View; a derived name cannot.

**Turn `kill_view` into `detach`.** The View's normal destroyer is the
`client-detached` hook, which covers detach and crash alike; the only View the
plugin must clean up itself is one whose client never arrived, and that cleanup
belongs inside `attach`, where the View was born. `detach` already names the
user-facing act of ending the Terminal, whose mechanism is stopping the job and
letting the hook collect the View — two mechanisms do not want one name.

## Consequences

- The Driver contract names 9 verbs; `focus`, `retarget`, and `kill_view` are
  gone, the first two as `vantage.Attachment` methods. No verb above the seam
  takes a process pid.
- A same-Group switch costs one `select-window` instead of a client scan plus
  two probes, and a Focus read is one `display` against the View.
- `tests/backend/tmux_spec.lua` (renamed from `driver_tmux_spec.lua`) pins the
  Attachment's contract, the client-free Focus read, the cross-Group handle
  adoption, and the failed-start rollback through `Backend.attach` — the
  rollback pin moves off the command layer.
- The composition root resolves through `Backend.setup()`/`reset()` and
  `health.lua` reads `Backend.health()`, so `vantage.backend` is the only door
  and the only contract file.
- Supersedes the pid-keyed half of
  [focus-is-one-driver-read](2026-09-13-focus-is-one-driver-read.md) and the
  `attach`/`kill_view`/pid facts of
  [restore-per-client-views](2026-09-10-restore-per-client-views.md). The
  read split, the reference-spelling owner, and
  [seam-types-live-with-their-seam](2026-09-13-seam-types-live-with-their-seam.md)'s
  principle stand; their paths move with the files.
- The flows' own deferred simplifications — the second inventory read, the
  pinned entry's no-op scope command in `show` — are unchanged here.
