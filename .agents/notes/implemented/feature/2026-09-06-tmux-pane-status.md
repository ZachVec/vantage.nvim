# Agent Note: Agent info in the tmux pane border

Status: implemented

## Problem

The only place the focused Agent's tool · cwd ever surfaced was the terminal
buffer's name (`retitle()` in `lua/vantage/frontend/terminal.lua`), which renders only
through tab labels and winbars — invisible on the default borderless float
(see the [full-terminal-layout
note](2026-09-03-full-terminal-layout.md) and the [float-terminal-layout-default
note](2026-09-05-float-terminal-layout-default.md)). The requirement became:
drop the Neovim-side title entirely and show the info through tmux, visible in
every layout, refreshing about once a second. Additionally, per-Group counts
of Agent States must stay correct under concurrent writers in different panes,
without a long-lived process and without shared mutable counters to corrupt.

## Decision

- **`retitle()` is removed** (definition and its three call sites in
  `focus()`/`retarget()`/attach path in `lua/vantage/frontend/terminal.lua`); the
  terminal buffer name is Neovim's default again. This supersedes the retitle
  part of the [full-terminal-layout note](2026-09-03-full-terminal-layout.md).
- **The pane's top tmux border carries the info.** The plugin owns the
  private server, so the border is applied unconditionally (no config
  option): `apply_global_config()` in `lua/vantage/backend/driver/tmux.lua` sets
  `status-interval 1`, `pane-border-status top`, and a global
  `pane-border-format`, padded with one leading and one trailing space:
  `Group · Tool · cwd` followed by the per-Group State counts. Group is
  `#{@agent-group}` — like Tool and Cwd, an
  explicit window option the Backend writes at `create()` time, so neither the
  border nor the data path derives the Group from tmux session topology (the
  `#{?#{session_group},…}` conditional is gone from window-scoped logic;
  session-level enumeration in `group_views()`/`retarget()` keeps the
  fallback, because it queries sessions, where a window option cannot apply).
  Tool is `#{@agent-tool}` and cwd shows
  `#{@agent-cwd-tilde}`, and both are required create-time fields, so the
  format carries no conditional at all: `create()` validates Tool non-empty
  (its only write site; the sole caller always passes a `cli.tools` key, so
  the only theoretical source was a pathological empty-string config key),
  and Cwd goes through `Util.cwd()` — even when `getcwd(0)` yields an empty
  string (a deleted `:lcd` directory), `fnamemodify("", ":p")` falls back to
  the process cwd, so the option is never empty. The cwd option itself is
  written once at `create()` time (`Util.tilde`, the spawn directory with the
  `$HOME` prefix shown as `~`; tmux formats have no home-collapsing modifier,
  so the folding happens in Lua, not at render time). The only dynamic part
  of the format is the counts `#()`; an Agent's working directory is
  static, so everything else is pure option data with no runtime process.
  `status off` is unchanged: pane borders render independently of the status
  line (verified).
- **State has a fixed vocabulary** adopted from tmux-agent-sidebar's closed
  enum: `running`, `background`, `waiting`, `idle`, `error`. `create()`
  writes `idle` on a fresh window and lifecycle-script transitions replace
  it; nothing else writes the option, so it stays non-empty (the counts
  script still treats any unset value — only possible via external
  tampering — as `idle`).
- **The write contract is full-value slot overwrites.** Each State writer
  overwrites only its own window's `@agent-state` on every transition — never
  read-modify-write. Writers on different windows cannot race (disjoint keys);
  two events in one window are sequential and last-writer-wins, which is the
  correct end state.
- **Counts are never stored.** the tmux Driver's `counts.sh` resource recomputes them per
  status tick from the live tmux state (read-only `list-windows -a`, group
  filter, unset → idle, only non-zero buckets, leading space, fixed order);
  tmux runs one `#()` process per distinct command string per tick, so one run
  per Group. There is no counter to drift or race; the aggregation is the
  display side's job, exactly as in
  [tmux-agent-sidebar](https://github.com/hiroppy/tmux-agent-sidebar)'s state
  management (per-pane `@pane_*` full-value writes + display-side read-only
  aggregation). The counts render in the border as a glyph + count per
  bucket: Nerd Font private-use glyphs chosen for semantics and
  distinctness — `\uf111` solid circle (running, nf-fa-circle), `\uf042`
  half circle (background, nf-fa-adjust), `\uf059` question circle (waiting,
  nf-fa-circle_question), `\uf10c` empty circle (idle, nf-fa-circle_o),
  `\uf05c` xmark circle (error, nf-fa-circle_xmark); the terminal font must
  cover the Nerd Font PUA (the plugin already assumes one — the picker
  prompt uses a glyph). Two earlier sets were rejected: the first nf-fa
  circle variants were indistinguishable at terminal size, and standard
  Unicode Geometric Shapes lacked the semantic signatures. The format
  appends `#("<driver-resource>/counts.sh" -L <socket> #{@agent-group})`, so
  each pane's border shows its own Group's buckets, zero buckets skipped,
  unset State as idle.
- **the tmux Driver's `status.sh` resource** is a manual, vocabulary-validating writer —
  the skeleton every future per-Agent lifecycle script will call. It takes
  `[-L <socket>] <window-id> <state>` and writes the full value. The socket
  defaults to `vantage` (the plugin's default `Config.options.socket`); the
  Lua side always passes the configured socket explicitly.
- The border's only `#()` is the counts command, called by absolute path
  (`resource_path()` resolves the driver's `resources/tmux/counts.sh` through
  the plugin runtimepath — tmux runs `#()` with the server environment, where
  the resource is not on `PATH`). The command string embeds the expanded
  `#{@agent-group}`, so tmux dedupes it to one run per Group per tick.

## Verification

On tmux 3.6a against a throwaway socket, with `status off` (the plugin's
setting): windows with `@agent-group` / `@agent-tool` / `@agent-cwd-tilde`
set and `status.sh` writes applied — the captured client render shows
the top border ` grpA · claude · ~/vantage <running-symbol> 1 <idle-symbol> 1 `
(padded; `$HOME`-rooted display path collapsed; per-Group counts rendered as
Nerd Font glyphs, glyph space count per bucket, zero buckets skipped, unset
State as idle — after the second window moved to `waiting` the line became
` <running-glyph> 1 <waiting-glyph> 1 `, i.e. the zeroed `idle` bucket
disappeared), ` grpB · codex · /tmp `
(non-home absolute path stays absolute; another Group's buckets never leak
in), and ` grpC · claude · ~ `
(cwd exactly `$HOME`). The counts machinery was probed directly: cross-group
isolation, empty output when all buckets are zero, and invalid-state
rejection (exit 2).

## Alternatives considered

### Why not a tmux status line (`status on`)?

A status line is client-scoped chrome rendered inside the client terminal; it
would force `status on` (the plugin deliberately sets `status off` so the
terminal is a raw agent prompt), and its content is global rather than
per-pane. The pane border is per-pane, draws with `status off`, and costs one
row inside the pane edge.

### Why not locks (flock / lock dirs / fds)?

tmux has no atomic increment primitive: `set-option` stores values literally
(arithmetic is not evaluated), so a cross-process read-modify-write of a
shared counter loses updates (demonstrated by probe: two concurrent writers
both read the old value and one update is lost). Locking a file or fd for
every transition is the classic answer but is exactly the machinery the slot
model removes: with full-value writes of disjoint per-window keys there is no
shared mutable state left to protect, and the aggregation is read-only.

### Why not a polling writer or a daemon?

The user explicitly rejected polling as inelegant; per-tick `#()` needs no
long-lived process, and the ~1s freshness bound is met by `status-interval 1`
alone.

### Why not keep a dynamic State vocabulary?

tmux-agent-sidebar's status set is a compile-time-fixed Rust enum — not
configurable — and the user's directive was: if it is fixed, adopt it. A
fixed vocabulary also makes the counts script and the writer validation
closed and testable. Extending the set is a deliberate act: edit
the driver's `status.sh` validation, `counts.sh`, and this note
in one change.

### Why not `pane-border-status bottom`?

The user explicitly chose the top border.

### Why not a config toggle (`pane_border = false`)?

The private server is fully plugin-owned, so a kill switch only adds config
surface without a requirement — the border costs one terminal row and its
content is the plugin's own data. The user dropped the toggle; re-introduce
it only when someone actually wants the border off.

### Why not render the live pane cwd (`pane_current_path`)?

`pane_current_path` is "if available" per the tmux man page, and the first
live observation showed an empty cwd segment. Since an Agent's working
directory does not change over its life, the create-time recorded path —
with the `~` folding done once in Lua — is authoritative and costs zero
runtime processes (the `vantage-tilde` script and the per-pane `#()`
substitution were removed on this basis).

### Why not have the State scripts store counts into `@vars`?

That path is what forces read-modify-write (compute new totals from a stale
snapshot, or serialize writers). Read-only per-tick aggregation keeps every
writer trivial and the display self-healing.

## Consequences

- The terminal buffer name no longer carries Agent info; `full`/split layout
  users lose the `<tool> · <cwd>` tab label (that info now lives in the pane
  border, which is visible in every layout).
- The private server ticks every second (the border re-renders per tick; the
  counts `#()` runs one small process per Group per tick, deduplicated by
  tmux — nothing else runs per pane, the identity segments are static
  options). The pane border consumes one terminal row.
- No config option: the border is applied unconditionally (a user toggle was
  considered and dropped — see Alternatives). Documentation added to
  README.md and doc/vantage.nvim.txt; the `State` glossary entry now records
  the surfaced vocabulary.
- The border and the Agent data path treat Group as explicit window data:
  `@agent-group` is written at `create()` like Tool and Cwd, and `list()`
  reads it directly — the `#{?#{session_group},…}` conditional survives only
  in session-level queries (`group_views()`, `retarget()`), where it is
  inherent to tmux session groups.
- Config-time validation: `setup()` drops invalid `cli.tools` entries (empty
  name, or a value without a non-empty `cmd` array) with a warning, keeping
  the Tool-required contract of `create()` and the border's unconditional
  `@agent-tool` honest; `:checkhealth` reports what was dropped.
- Migration: windows created by an earlier iteration of this uncommitted
  change lack `@agent-cwd-tilde` and show an empty cwd segment until
  recreated; the format deliberately carries no fallback (Cwd and Group are
  required create-time fields, so the options always exist on new windows)
  and no backfill was added — the feature is unreleased, so the only loss is
  on an existing dev server.
- The five-state vocabulary and the full-value write contract are load-bearing
  for the future per-Agent lifecycle scripts (a separate, later feature): they
  must emit these five values, full-value per window, and the plugin-side
  skeletons (`status.sh`) are their calling convention.
- The [full-terminal-layout note](2026-09-03-full-terminal-layout.md) keeps
  the `full`-layout flicker rationale; its retitle paragraphs were updated in
  place to point here, and the inbound link in the [single-Client-terminal
  note](../architecture/2026-08-31-single-terminal-frontend.md) was retargeted
  to this note for the title part.
