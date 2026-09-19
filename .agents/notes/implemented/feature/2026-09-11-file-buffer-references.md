# Agent Note: Files and buffers gathered into the Agent input

Status: implemented

## Problem

Getting a set of files into a focused Agent meant one prompt per file
(`{file}`) or typing `@path` by hand. sidekick.nvim binds `<c-f>`/`<c-b>` to
its picker engines' own file and buffer sources and sends the selected entries as
`@path` references, but that model — engines owning enumeration, previews, and
selection — is the coupling Vantage's Picker seam rejects: renderers stay pure
and flows own their items. Vantage also picked through a single-choice contract
(`pick`, `pick_plain`) while gathering wants several entries at once.

## Decision

Two Terminal actions, `files` and `buffers`, owned by `commands/gather.lua`.
Each lists candidates under Neovim's global cwd and renders them relative to
that tree (the listing root is Neovim's, not the Focus's — see
[the listing-root note](../bug-fix/2026-09-19-files-listing-root-is-neovim-cwd.md)),
then types each chosen entry's `<relpath>` reference into the Agent's input
through the Backend — bracketed paste, no auto-submit, references joined with
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
  opts)` returns every confirmed entry through `on_choices`: snacks confirms
  `picker:selected({ fallback = true })`, fzf-lua runs `fzf_exec` with
  `fzf_opts = { ["--multi"] = true }` and maps every returned entry back
  through the numeric-prefix round-trip, and native — which has no
  multi-select — degrades to a single choice, so `on_choices` always receives
  a list.
- **The pick's close belongs to the implementation**, not to the flow: gather
  passes no close callback, because the snacks Picker's own close handler
  already returns focus to the terminal the pick was invoked from (see
  [the pick-close note](../simplification/2026-09-13-pick-close-is-the-implementations.md)).
- **References are spelled by the Tool's `format(file, loc)` hook, applied per
  entry**: a gathered entry has no position, so `loc` is nil, and the results are
  joined with `gather.join`. A hook returning nil or "" drops the send, so each
  dialect keeps defining one formatter — see
  [the Tool format hook note](2026-09-11-tool-format-location-hook.md).

## Alternatives considered

### Why not add Files/Buffers entries to the prompt picker?

The prompt list is `prompts`, a `table<string, string>` of templates, and
"Prompt" is a named text template. An entry that opens a picker is neither, so a
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
(`file`, `loc`). Applying it per entry keeps one formatter per dialect.

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
  and inherit the Picker's capability degradation: several entries under
  `fzf-lua`/`snacks`, one entry at a time under `native`.
- The Picker contract now declares three capabilities; glossary and
  architecture describe `preview`/`command`/`multi` and the single-choice
  degradation.
- Gathered references are bare paths; the Tool's `format` hook owns their
  dialect decoration and has to tell a rendered prompt from a lone reference.
- Gathered references are joined and pasted by `commands/gather.lua` itself;
  a Tool's reference spelling is spelled through `Config.tool_reference`, the
  single owner of the defaulted `format` hook (see
  [focus-is-its-own-read](../architecture/2026-09-13-focus-is-its-own-read.md)).
