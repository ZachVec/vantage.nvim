# Agent Note: Picker has two interfaces — a streaming fancy pick, a static naive pick

Status: implemented

## Problem

`vantage.PickerImpl` carried three selection methods (`pick`, `pick_multi?`,
`pick_plain`) and declared three capabilities. Two of the methods were one
interface written twice: `pick_multi` subsumed `pick` — a picker without the
`multi` capability degraded it to a single choice — so every implementation
carried both paths and the facade carried a degrade branch whose only job was to
keep the callback shape stable.

The item source was the deeper cost. `PickSpec.items_provider` was a synchronous
pull that every implementation read *before* it opened anything. That read was
where `empty, err` came from
([a failed read is part of the pick's answer](2026-09-13-a-failed-read-is-part-of-the-picks-answer.md)),
and it was why `commands/gather.lua`'s `files` froze the editor on `Util.run`
(`vim.system(...):wait()`) until `fd`/`rg` had printed its last line: no picker
could open, let alone show anything, until the list was final. Both target
engines stream natively — fzf-lua's function contents writes one item per
`on_write_nl` call and takes `nil` as end of input, over a pipe that stays open
until then, and snacks' finder may return `fun(cb)` that pushes one item at a
time inside its own async task — so the seam could not express what the one flow
with a genuinely large list needed.

## Decision

The Picker has two interfaces:

- `Picker.pick_fancy(spec, opts)` — a streaming pick: the flow's `spec.items`
  emits entries as it produces them, and the implementation renders each batch
  as it arrives.
- `Picker.pick_naive(items, opts, on_choice)` — the static plain-list form,
  `vim.ui.select` shaped: no preview, no stream, no commands.

`vantage.PickerImpl` implements both, which is what makes a picker symmetric:
`native` implements `pick_fancy` by draining the stream and rendering the final
list through its own `pick_naive`, so the naive path is that engine's fallback
rather than a third method the facade negotiates.

### The seam

```lua
--- A pick's item stream: `emit` appends a batch as it is produced, `done` ends
--- the run, and the optional return stops a run the picker outlived.
---@alias vantage.picker.Source fun(emit: fun(entries: Entry[]), done: fun()): (fun()?)

---@class vantage.PickSpec
---@field prompt string
---@field many boolean                             -- the flow acts on several entries
---@field preview? fun(entry: Entry): string[]?    -- present = a preview pane
---@field items vantage.picker.Source

---@class vantage.PickOpts
---@field on_choices fun(entries: Entry[])         -- at least one entry
---@field commands? vantage.PickerCommand[]

---@class vantage.PickerImpl
---@field capabilities { command: boolean }
---@field pick_fancy fun(spec: vantage.PickSpec, opts: vantage.PickOpts)
---@field pick_naive fun(items: any[], opts: NaiveOpts, on_choice: fun(item: any?, index?: integer))
```

An implementation starts `spec.items` once per engine run — the opening run, and
a fresh run whenever a command reports that the list may have changed — and
calls the cancel function a source returned when the picker closes or the run is
replaced. A source that finishes within that call is a static list, which is how
an implementation keeps the cheap path cheap.

`on_choices` is the one selection callback and always receives at least one
entry: a flow that acts on a single entry reads `entries[1]`, and the kill flow
acts on every entry it is given. `many` states which the flow wants; native
degrades it to one choice because `vim.ui.select` has no marking.

`preview`, when the flow sets it, is `Entries.preview` — the one preview
function, which answers the highlighted entry's lines by kind and nil for a kind
with nothing to show. An implementation that can show a pane shows one and
leaves it empty for that nil answer; without the function there is no pane.
Entries are plain data: the earlier design bound a preview function to each
entry.

`capabilities` is down to `command`. Preview and multi are per-pick requests
that an implementation degrades when it cannot honor them, while `command` must
be declared because the Agent picker decides its default Group scope *before* it
opens ([agent picker group scope](../feature/2026-09-05-agent-picker-group-scope.md)).

A pick that has nothing to show opens empty and stays open until the user
cancels it. The `empty, err` answer went with the read-before-opening design; a
flow reports a failed read from inside its own source, which is also where its
knowledge of that read lives.

### Adapters

**native** — `capabilities = { command = false }`. `pick_fancy` starts the
stream, waits for it with `vim.wait` (which pumps the event loop, so a source
that ends asynchronously ends the wait), then renders the final list through
`pick_naive` with `format_item = entry.text` and answers `on_choices` with the
one choice.

**fzf-lua** — function contents: each emitted batch becomes prefixed lines in
fzf's stdin, and `done` calls `on_write_nl(nil)`. `many` adds `--multi`; a
present `preview` sets fzf's preview callback and its absence leaves `preview`
unset, which fzf-lua renders hidden. A command's `reload` re-enters contents,
which starts a fresh run when the command reported a change and re-emits the
snapshot otherwise. `winopts.on_close` cancels the run.

**snacks** — the finder returns the items table when the source finished within
the call, and otherwise an async finder that drains a queue from inside snacks'
own task (queue plus suspend/resume, the shape `snacks.picker.source.proc`
uses). `many` confirms `picker:selected({ fallback = true })` instead of the
entry under the cursor; `preview` sets the pane callback and its absence sets
`layout = { preview = false }`; a changed command calls `picker:refresh()`, and
closing the picker (snacks aborts the finder task) or the task's own abort
cancels the run.

### Flows

`attach`, `kill`, `review`, and `gather` keep their reads and hand them over as
one-shot sources; the Agent-creation Group step and `:Vantage prompt` call
`pick_naive`. `attach` and `review` ask for one entry, `kill` and `gather` for
several, and all four ask for the standard preview. The `files` listing is still
synchronous: making the lister a live stream, so entries appear while `fd`/`rg`
runs and closing the picker stops the child, is the next step this seam exists
for and is recorded in
[the file-listing note](../feature/2026-09-19-streaming-file-listing.md).

## Alternatives considered

### Why not keep `pick` and `pick_multi`?

They differ only in how many entries the flow acts on, and `pick_multi` already
subsumed `pick` through the capability degrade. One callback that always
receives a list carries both, with `many` saying which the flow wants.

### Why not keep `items_provider` and add a streaming source beside it?

Two list shapes for one fact: every implementation would carry both, and the
empty-list policy would need a rule for which is authoritative. A stream that
ends within the call is a static list, so one shape expresses both.

### Why not keep the `empty, err` answer?

It required a read before opening, which is exactly the thing being streamed,
and it made the flow's read failure a facade concern. A pick that shows nothing
is the honest rendering of a stream that produced nothing, and the flow reports
its own read failure from inside its source. The known gap is unchanged: a
stream that fails after the picker opened has no channel back to the flow.

### Why not keep the preview function on the Entry?

The Entry is the pick's data, and a preview is presentation the flow asks for.
Moving it to the spec makes the pane a per-pick decision while keeping one
preview vocabulary: `Entries.preview` is still the only preview function, keyed
by kind, so no pick can drift into its own preview. The alternative that
[the entries-are-data note](2026-09-13-picker-entries-are-data.md) rejected —
a spec-level preview — is what this adopts.

### Why not a `preview = true` boolean, resolved by the facade into two specs?

One spec is what makes a pick legible: the table the flow writes is the table
the implementation renders. The flows already build their entries, so handing
the pick `Entries.preview` costs them nothing and removes a rule ("true means
the standard function") plus a second type from the seam.

### Why not keep `preview` and `multi` in `capabilities`?

Nothing negotiates them any more: a pick asks for a pane or several choices and
an implementation that cannot deliver degrades. `command` survives because the
flow must know *before* it opens whether its keys will be bound.

### Why not let native re-open `vim.ui.select` as batches arrive?

`vim.ui.select` takes a fixed list; re-opening it per batch would flicker, drop
the cursor, and re-ask the question. Waiting for the final list is the honest
degradation for an engine with no stream surface.

### Why not put native's drain in the facade?

That would make the fallback a facade policy for an engine the facade cannot
know, and it would break the symmetry this change is about: every
implementation answers both interfaces in its own terms.

## Consequences

- `Picker.pick_fancy` and `Picker.pick_naive` are the facade's only entries;
  `vantage.PickerImpl` requires both methods and declares `{ command }`.
- `vantage.picker.Entry` carries `text`, `kind`, and the flow's own fields — no
  preview. `Entries.preview` is the one preview function, and a flow that wants
  a pane hands it to the pick.
- An empty pick opens and stays open: "no agents and no tools configured",
  "nothing to kill", "no reviews", and "no files"/"no buffers" are gone. A
  failed read still reaches the user, now from the flow's own stream, and an
  empty re-read no longer closes the picker.
- The kill list acts on several marked entries under fzf-lua and snacks
  (`<Tab>` marks): it is the first flow that gains from the multi-only callback.
  README and `doc/vantage.nvim.txt` say so.
- Implementations still `require` nothing but their engine — the preview
  function arrives through the spec, so the entries vocabulary stays out of the
  adapters — and `native` keeps delegating to the live global `vim.ui.select`.
- `:checkhealth` reports `picker: <name> (command=…)`; whether a picker shows
  previews lives in the user-facing picker table.
- The engine mechanics this design leans on — fzf-lua's pipe staying open across
  pushes, `--preview-window=hidden:right:0` for no preview, snacks' async finder
  and `layout = { preview = false }` — are recorded in `docs/gotchas.md`.
- `tests/helpers.lua` gains `entries(spec)`, the test-side opening run, and the
  three picker specs pin the mapping: batches become lines or items, `many` and
  `preview` reach the engine, a changed command restarts the stream, and a close
  cancels it.
- `make check` and `make test` pass with the new shape.

This supersedes the contract parts of
[the pluggable picker note](2026-08-31-pluggable-picker-frontend.md),
[the pure-renderers note](2026-09-05-picker-pure-renderers.md),
[the plain-selections note](2026-09-03-picker-owns-plain-selections.md) (the
method is now `pick_naive`),
[the failed-read note](2026-09-13-a-failed-read-is-part-of-the-picks-answer.md),
and the preview half of
[the entries-are-data note](2026-09-13-picker-entries-are-data.md).
