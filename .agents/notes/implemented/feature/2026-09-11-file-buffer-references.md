# Agent Note: Files and buffers gathered into the Agent input

Status: implemented

## Problem

Getting a set of files into a focused Agent meant one prompt per file
(`{file}`) or typing `@path` by hand. sidekick.nvim binds `<c-f>`/`<c-b>` to
its picker engines' own file and buffer sources and sends the selected rows as
`@path` references, but that model — engines owning enumeration, previews, and
selection — is the coupling Vantage's Picker seam rejects: renderers stay pure
and flows own their items. Vantage also picked through a single-choice contract
(`pick`, `pick_plain`) while gathering wants several rows at once.

## Decision

Two Terminal actions, `files` and `buffers`, owned by `commands/gather.lua`.
Each lists candidates for the focused Agent's cwd, renders them as
`<relpath>` references, and types them into the Agent's input through
`commands/send.lua` — bracketed paste, no auto-submit, references joined with
`setup { gather = { join = … } }` (default one per line), a trailing space
after the last one, and no trailing newline.

- **Enumeration belongs to the flow.** `files` runs `fd --type f --type l
  --color never -E .git`, then `rg --files --no-messages --color never -g
  '!.git'`, then a pure-Lua walk that always skips `.git` (no ignore
  semantics — the documented cost of a minimal install). An empty successful
  listing is an answer, not a reason to fall through. `buffers` lists buffers
  that are `buflisted`, of buftype `""`, named, and readable on disk, most
  recently used first; a modified buffer is displayed with a `[+]` marker
  because the Agent reads the on-disk content, while the sent reference stays
  a bare `<path>`.
- **The Picker gained a third capability, `multi`.** `Picker.pick_multi(spec,
  opts)` returns every confirmed row through `on_choices`: snacks confirms
  `picker:selected({ fallback = true })`, fzf-lua runs `fzf_exec` with
  `fzf_opts = { ["--multi"] = true }` and maps every returned entry back
  through the numeric-prefix round-trip, and native — which has no
  multi-select — degrades to a single choice, so `on_choices` always receives
  a list.
- **`PickOpts`/`PickMultiOpts` carry an optional `on_close`**, run whenever the
  picker closes, on confirm or cancel, so gather can restore the invoking
  window after the engine's own teardown.
- **References are spelled by the Tool's `format(file, loc)` hook, applied per
  row**: a gathered row has no position, so `loc` is nil, and the results are
  joined with `gather.join`. A hook returning nil or "" drops the send, so each
  dialect keeps defining one formatter — see
  [the Tool format hook note](2026-09-11-tool-format-location-hook.md).

## Alternatives considered

### Why not add Files/Buffers rows to the prompt picker?

The prompt list is `prompts`, a `table<string, string>` of templates, and
"Prompt" is a named text template. A row that opens a picker is neither, so a
union type would leak into config merging, placeholder validation, the
synchronous renderer, and the `{reviews}` hiding rule — all to save one
keypress from a terminal keymap. sidekick's `{buffers}` prompt exists because
its prompts *are* context functions; Vantage deliberately kept prompts as
strings.

### Why not let the picker engines enumerate (sidekick's model)?

It is less code and gives ignore-aware listings for free, but it moves domain
assembly back into the renderers, leaves `native` with no file source at all,
and makes every implementation learn the `files`/`buffers` vocabulary.

### Why not `git ls-files` first?

It lists tracked and untracked-but-not-ignored files but also index entries
deleted from the worktree, which need a filter. It also diverges from what the
ecosystem shows: sidekick delegates to snacks, whose file source is fd →
ripgrep → find. Matching that chain keeps the candidates the same list users
already see in their file picker.

### Why not a separate `format_refs` hook?

A second per-Tool hook doubles the per-dialect surface — every tool that
translates the Claude dialect would define both functions — for a transform the
existing one already expresses once it receives the reference's parts
(`file`, `loc`). Applying it per row keeps one formatter per dialect.

### Why not bake `@` into the gathered reference?

The decoration is dialect, not domain: Claude wants `@path`, another tool may
want the bare path, and the Tool's `format` is where that choice already lives.
The cost is a reference-shaped hook instead of a text-shaped one: the Tool
decides the spelling from `file`/`loc`, and prose never reaches it.

### Why not send file contents instead of references?

The Agent's CLI already resolves `@file`; inlining duplicates that with no
size bound, no binary handling, and an ambiguous reading for buffers whose
unsaved edits are not on disk. Where content is genuinely wanted, Reviews'
`{code}` already inlines a chosen range.

## Consequences

- `files`/`buffers` work on a minimal install (the Lua walk is the fallback)
  and inherit the Picker's capability degradation: several rows under
  `fzf-lua`/`snacks`, one row at a time under `native`.
- The Picker contract now declares three capabilities; glossary and
  architecture describe `preview`/`command`/`multi` and the single-choice
  degradation.
- Gathered references are bare paths; the Tool's `format` hook owns their
  dialect decoration and has to tell a rendered prompt from a lone reference.
- The prompt and gather flows share `commands/send.lua`, the one place that
  decides what a Tool sees and how text is shaped before `Bridge.send`.
