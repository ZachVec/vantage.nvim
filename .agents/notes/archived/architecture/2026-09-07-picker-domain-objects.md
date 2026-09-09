# Agent Note: Picker rows are domain objects, not an Entry layer

Status: implemented

Archived: 2026-09-09

## Problem

Preview-capable pickers wrapped their domain data in a separate presentation
layer — `vantage.PickerEntry` and five `*Entry` variants — whose rows exposed a
`value()` result channel and a `scope_group()` accessor. `select.lua` built
those rows, then supplied parallel `preview` and `on_delete` functions in the
`PickSpec`, so row shape and behavior lived in two places and the row protocol
was a presentation term (`Entry`) rather than a domain one.

## Decision

The picker items are the domain concepts themselves — `Agent`, `Tool`, `Group`,
and `Annotation` — built as plain-table value objects (not metatable classes),
each carrying its own protocol methods:

- `format()` returns the display string;
- `preview()` returns preview lines or nil;
- `delete()` removes the item and returns whether something was removed;
- `activate(after)` performs the selection action by invoking the
  flow-injected `after` on the item's domain object;
- `group()` returns the item's Group, or nil when it has none (Tool rows are
  creation actions, not Group members).

The `Entry` type and the `value()`/`scope_group()` methods are gone. `PickSpec`
shrinks to `prompt`, `items_provider`, `from_terminal`, and an optional `group`
filter; preview and in-place deletion are read straight off the item. The
Agent list's group filter asks `entry:group()` instead of branching on a `kind`
field. Selection is polymorphic: `pick_agent` and `pick_annotation` call
`item:activate(after)`, while `pick_kill` calls `item:delete()` — an Agent
kills itself, a Group kills the whole Group. Creating an Agent from a Tool row
moved into the Tool item's `activate` (it selects a Group then runs `after` on
the new Agent). A Group's `activate` (switch the client to that Group) is
defined in the domain model but not yet wired to a flow; it lands when the kill
picker is redesigned.

## Alternatives considered

### Why not keep a `PickerEntry` abstraction?

A single presentation supertype erases the domain distinction the flow needs
(an Agent is focused, a Tool creates, a Group kills). Naming the rows by their
domain concepts keeps "what the entity is" and "what the flow does with it" in
the right layers.

### Why not keep `value()` for the result channel?

`value()` was "whatever the flow wants back", which is flow-shaped, not
entity-shaped. The polymorphic `activate(after)`/`delete()` methods deliver the
selection result without the flow branching on a `kind` field.

### Why not expose the Group as a `scope_group()` method?

`group()` is the entity's own property (what Group it belongs to, nil when it
has none); `scope_group` was named after the flow's scope transform, which is
not the entity's concern.

## Consequences

- `select.lua` builds Agent, Tool, Group, and Annotation value objects, and now
  owns the Tool-row creation flow (`create_with_tool` and its helpers moved
  from `commands/agent.lua`).
- `native`, `fzf-lua`, and `snacks` format rows with `item:format()`, preview
  with `item:preview()`, delete in place with `item:delete()` (re-reading only
  when it reports a removal), and pass the chosen item to `on_choice`
  unchanged.
- `commands/agent.lua` and `commands/annotation.lua` inject the tail action and
  call `item:activate(after)` or `item:delete()`.
- Tests use `activate()`, `delete()`, `group()`, `format()`, and `preview()`
  rather than `value()`/`scope_group()`.
