# Agent Note: The Agent list is global, and the Group is a creation-time prompt

Status: implemented

## Problem

The Agent picker's contents depended on the picker engine. `attach` seeded a
group scope from `Picker.capabilities().command` — with a command-capable
picker the list opened narrowed to the focused Agent's Group, with `<C-g>`
toggling it, and a picker that bound no keys simply showed everything with no
way to ask for the scope. The visible list therefore changed with a
configuration choice that has nothing to do with what the user is looking at,
and the flow carried a browsing context (`group_on`) beside the Focus's real
Group.

The Group was the same entanglement one step further in. Choosing a Tool entry
opened a second pick (`+ new group` among the existing names), a nested picker
whose close ordering interacts with the Terminal's mode on every engine
([the archived new-Group note](../../archived/bug-fix/2026-09-05-snacks-new-group-terminal-mode.md)),
and whose entry list had to be built (and its read failure reported) before
the Agent could be created.

## Decision

The Agent list always shows every Group's Agents plus the configured Tools,
with the Terminal's own Focus pinned first when it has one. The scope toggle,
its `<C-g>` command, the `+ new group` entry, and the `command` capability are
gone.

Choosing a Tool entry asks for a Group through one synchronous,
completion-backed `vim.fn.input` prompt:

- `completion = "customlist,v:lua.require'vantage.commands.attach'.complete_groups"`;
  `customlist` does no filtering of its own, so the exported
  `M.complete_groups(lead, …)` prefixes the live inventory's Group names.
- The default is empty; a confirmed name is `vim.trim`ed, and empty, cancelled
  (`cancelreturn = vim.NIL`, a userdata, checked explicitly), or interrupted
  (CTRL-C raises, so the call is `pcall`ed) all create nothing.
- The returned name is this creation's local argument to `Backend.create`; it
  is not stored anywhere, and there is no `create_group` verb.

The Picker facade no longer negotiates a capability table: `opts.commands` are
handed to the implementation verbatim, and one that binds no keys ignores
them.

## Alternatives considered

### Why not a current-Group state with its own picker or commands?

That is the duplicated context this change removes: a browsing scope beside
the Focus's real Group, with no rule for when one updates the other. A
creation-time string has one lifetime — the create call — and no state to go
stale.

### Why not keep the capability and open the list unscoped for engines that bind no keys?

Two different lists for one command, differing by an invisible engine
property. What the list shows is the user's question; which keys the engine can
bind is not.

### Why not keep the Group pick and only drop the scope toggle?

The nested pick is what made the Group step carry the engine's close ordering
(and the mode bug above), and it still needed the inventory to answer "no
Groups exist". A cmdline prompt has no window: nothing to close, nothing to
restore, and completion covers recall.

### Why not a `:Vantage group` command or a Group Terminal action?

A Group is a container derived from its Agents; the only operations the docs
promise are creating one by creating an Agent in it and ending one by killing
its members. Standalone Group management would be surface area with no
workflow behind it.

## Consequences

- `vantage.PickerCapabilities` and every implementation's `M.capabilities` are
  deleted; the facade always passes `opts.commands`, and `:checkhealth` reports
  only the configured picker name
  ([picker-two-interfaces](2026-09-18-picker-two-interfaces.md) is updated).
- `attach`'s spec no longer takes state; `build_items` is the list, and the
  exported `complete_groups` is the completion's only surface.
- README and `doc/vantage.nvim.txt` lose the `<c-g>` row and the "scoped to its
  Group" sentence, and describe the Group prompt with completion.
- `tests/commands/attach_spec.lua` stubs `vim.fn.input` (recording the dict it
  was handed) and covers the global list, the pin, the trimmed name, cancel,
  empty/blank, interruption, and prefix completion.
- The Focus is still pinned and still excluded from the sorted tail; the list
  is otherwise engine-independent.

## Verification

`tests/commands/attach_spec.lua` drives the flow with a stubbed `vim.fn.input`
and covers the list, the pin, the Group prompt's options, trimming, cancel,
empty/blank, interruption, and prefix completion; `picker_spec.lua` covers the
facade handing commands through with no capability table. The interactive
behavior a headless suite cannot observe — a real `native`/`fzf-lua`/`snacks`
window and the Terminal's mode after the picker closes and the Group cmdline
closes (`docs/gotchas.md`: the harness cannot see modes) — still needs the
hand check the repo uses for mode behavior, and `native` in particular is only
verified through whatever global `vim.ui.select` the user has.
