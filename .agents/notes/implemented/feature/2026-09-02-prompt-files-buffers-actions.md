# Agent Note: Prompts — built-in files/buffers Actions

Status: implemented

## Problem

[Prompts](2026-08-31-prompts.md) only cover canned prose: every Prompt is a
string Template rendered against the cursor's location. There was no way to
gather context from a *set* of files or buffers — the "drop every file I touched
into the Agent" flow sidekick.nvim solves with its `<c-f>` / `<c-b>` picker
keymaps. A user working across several files had to type each `@path` reference
by hand.

## Decision

`files` and `buffers` are built-in **Actions**, the second kind of Prompt
alongside the string **Template** (see the glossary). An Action opens a picker,
multi-selects, and types the selected references; a Template renders a string.
`:Vantage prompt` lists both kinds, sorted together; Actions appear only when
the configured Picker implements them (`fzf-lua` and `snacks` — not `native`).

- `PickerImpl` gains `pick_files(cb)` / `pick_buffers(cb)` (`fun(paths: string[])`,
  absolute paths), implemented only by `fzf-lua` and `snacks`. Each delegates to
  its backend's own source — `snacks.picker` `files` / `buffers`, `fzf-lua`
  `files` / `buffers` — and recovers absolute paths (snacks
  `snacks.picker.util.path(item)` / `item.buf`; fzf-lua
  `fzf-lua.path.entry_to_file(sel, opts)`). Multi-select is the backend's native
  selection; no enumeration lives in Vantage.
- Buffer selections are filtered in the confirm callback through
  `picker/items.buffer_file_path(buf)` — real files only (empty `buftype`, named,
  `filereadable`); the file list needs no filter.
- `prompt.lua` exports `M.relativize(cwd, path)` (the former local `loc_file`)
  and `M.render_paths(agent, paths)`, which joins selected paths as `@<relpath>`
  (absolute when a path escapes `agent.cwd`) with newlines. `M.actions = {
  files = true, buffers = true }` is the built-in Action registry.
- `commands.lua` `send_prompt` branches: an Action runs `send_action` (schedules
  the picker so the name selector can close, then sends the joined text); a
  Template renders as before. Both share `send_text` (the `tool.format` hook +
  `send_keys`). The `:Vantage prompt` name list adds the Actions only when
  `Picker.get().pick_files` is a function, so `native` — and a configured picker
  that falls back to `native` — hides them silently.

## Alternatives considered

### Why not a separate `:Vantage files` / `:Vantage buffers` subcommand?

Every `:Vantage` subcommand is a verb (switch, kill, toggle, detach, prompt,
status) that reads as an action on Vantage's own objects. `:Vantage files` is
opaque — it does not say "gather files into the focused Agent". Surfacing the
Actions inside `:Vantage prompt` keeps one Prompt vocabulary and one entry point.

### Why not root the files picker at the Agent's cwd?

The picker backend's `files` source defaults to the nvim cwd; passing
`cwd = agent.cwd` would make enumeration and relativization agree exactly. But
the Agent and nvim usually share a cwd, and when they differ the references
still come out correct (relative when under `agent.cwd`, absolute otherwise).
Delegating verbatim (no `cwd` override) matches sidekick and keeps the files and
buffers paths unified — both relativize against `agent.cwd`.

### Why not filter buffers at picker launch?

Excluding unnamed / non-file buffers from the *list* would be cleaner UX, but no
source option does it uniformly: snacks' `buffers` source has only coarse flags
(`nofile`, `hidden`, …), and fzf-lua's only coarse opts too. A uniform
launch-time filter would need either backend-specific hooks or re-enumerating
buffers ourselves (abandoning delegation). Filtering the selection in the
confirm callback is one backend-agnostic check (`buffer_file_path`); the only
cost is that `[No Name]`-style entries still appear, and they are silently
dropped.

### Why not offer the Actions under `native`?

`native` is `vim.ui.select`: single-select and no file/buffer source. Degrading
the Actions to one-file-at-a-time would defeat the "select a set" purpose, and
building a custom multi-select TUI contradicts the "no custom TUI" baseline. So
the Actions exist only where the Picker can express them, and `:Vantage prompt`
hides them otherwise.

### Why not enumerate files/buffers once in shared code?

That is the existing `picker/items.lua` pattern (build items once, let each
implementation render), and it is what `native` would need. It loses the backend
sources' own behavior (`.gitignore` handling, fuzzy matching, MRU buffer order),
so the picker-specific value would have to be re-implemented. Delegating verbatim
keeps each backend's source and preview for free; `native` simply opts out.

## Consequences

- `PickerImpl` now has four methods on `fzf-lua` / `snacks` and two on `native`;
  the file/buffer pickers add no shared item construction (they are delegation,
  not the `items.lua` pattern).
- `:Vantage prompt` is now the single Prompt entry point, offering Templates and
  Actions together; `native` users see only Templates.
- The location-reference dialect (`@path`, relative to `agent.cwd`, absolute on
  escape) is now shared by Templates and Actions through one `M.relativize`.
- The [pluggable-picker note](../architecture/2026-08-31-pluggable-picker-frontend.md)
  and [plain-selection note](../architecture/2026-09-02-plain-selection-via-ui-select.md)
  are updated in this change: the Picker is no longer "the Agent list and the
  kill list" only.
