# Agent Note: note editor extracted as a pure UI module

Status: implemented

## Problem

The annotation note editor (`open_note_float`, ~80 lines) lived in
`commands/annotation.lua` and coupled UI to domain: it read `annotations.keys`
and `annotations.float.style` from config, and hardcoded the "Delete
annotation?" confirmation and the empty-note-deletes policy. It was also
over-keyed — `keys.exit` committed-and-closed, `keys.delete` deleted — with a
user-configurable `keys` that earned its complexity.

## Decision

- New pure-UI module `vantage/ui/note.lua` (`Note.open(opts)`), depending on
  nothing but the Neovim runtime. Its single action is Esc → read buffer →
  close → `on_commit(text)` (save on exit): no delete key, no confirmation, no
  empty-note policy — the caller owns every policy.
- `commands/annotation.lua` wires the editor: it passes `style`
  (`annotations.float.style == "minimal" and "minimal" or nil`), footer, and
  callbacks. Its `on_commit` treats an empty note as delete (after a built-in
  confirm) for `annotate list`, and as discard for `annotate`.
- `annotations.keys` config is removed (Esc is fixed); `annotations.float.style`
  stays.

## Alternatives considered

### Why not keep a separate `:w` save + Esc exit?

Splitting save from exit added an interaction without removing policy: the
editor still needs one commit channel plus a close channel. Save-on-exit keeps
one action and one callback.

### Why not keep the delete/empty policy inside the editor?

Those are annotation domain rules (empty annotation = delete), not editor
mechanics; keeping them in the UI would couple the generic editor to the
annotation domain.

### Why `ui/` rather than an `annotation/` directory?

The editor is a generic buffer editor — its annotation-specificity is entirely
in the callbacks — so it belongs in the UI layer beside `client.lua` and
`picker/`. An `annotation/` directory would mix the domain (extmarks/registry)
with UI.

## Consequences

- `annotations.keys` is gone — a breaking config change; README/help describe
  Esc-save and empty-deletes instead.
- The note editor is reusable by any future caller needing "edit text, Esc to
  commit".
