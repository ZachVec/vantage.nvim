# Agent Note: Agent picker group scope — default-on, `<C-g>`-toggled

Status: implemented

## Problem

The Agent picker could refresh in place, but nothing scoped the list to the
Group containing the focused Agent. A user with many Agents had to search the
whole inventory for collaborators in the current Group.

## Decision

The Agent picker opens scoped to the focused Agent's Group by default.
`commands/attach.lua` owns the scope state and passes a normal Picker
command:

```lua
{
  "<C-g>",
  function()
    state.group_on = not state.group_on
    return true
  end,
  desc = "toggle group scope",
}
```

The flow's `items_provider` reads the live snapshot on every refresh and
applies the filter when `state.group_on` is true. Tool rows always remain
visible; with no focused Agent, the whole list shows. Because the scope is a
normal `command`, a renderer without the `command` capability simply omits
the toggle and shows the unscoped list.

## Alternatives considered

### Why not a special `PickSpec.group`/`scope` field?

That made the Picker interface grow with a flow concept. The current Picker
knows only `preview` and `command`; the flow owns both the filter state and
the command that toggles it.

### Why not derive the scope Group from the pinned row?

The pin and the filter are both derived from the same live snapshot, but the
filter needs a stable `state.group_on` value across refreshes. The flow owns
that boolean explicitly.

### Why not scope native too?

native has no `command` capability, so it cannot bind `<C-g>`. It degrades to
the full list, which is the same explicit-capability policy used for Review's
in-place delete.

## Consequences

- fzf-lua and snacks support the scope command; native shows the full list.
- `<C-g>` is no longer a Picker concept, only an Agent-picker command.
- Deleting the last visible row and changing scope both re-read
  `items_provider`; an empty result closes the picker.
- The current Picker command contract is owned by
  [composition-root-and-neutral-seams](../architecture/2026-09-10-composition-root-and-neutral-seams.md).
