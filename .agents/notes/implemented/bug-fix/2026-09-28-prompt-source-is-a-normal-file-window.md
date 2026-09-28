# Agent Note: The Prompt's source window is a named normal file

Status: implemented

## Problem

Prompt context resolution took the most-recently-visited window that was not
the vantage Terminal (`filetype ~= "vantage_terminal"`). The Review editor's
note float is a named-less scratch buffer, and help, other `:terminal`s, and
other plugin buffers are not files either, so a `{file}`/`{line}` template
could resolve against a buffer the user never meant — or against nothing,
producing a nil line instead of a clear "this placeholder has no answer".

## Decision

A context window's buffer must be a normal file: `buftype == ""` and a
non-empty name. That excludes help, the Terminal, any other `:terminal`, the
Review float, and every other special buffer in one rule. The window is still
chosen by the most recent `WinEnter` visit stamp, so the file the user was
reading wins over the picker's own window.

With no such window the current window stands in; its empty name makes
`{file}`/`{line}` resolve to no reference (the prompt is skipped with the
placeholder named), while a template that only uses `{reviews}` or plain text
still sends.

## Alternatives considered

### Why not keep the filetype filter and add cases?

An exclusion list of filetypes misses every special buffer nobody enumerated
(the note float has no special filetype at all). `buftype` is the property
that decides whether a buffer is a file.

### Why not require `filereadable()`?

A new, unsaved file is a legitimate context: `{file}` should name it, and the
Agent's Cwd is where it will be written.

### Why not refuse the whole prompt when no file window exists?

Templates that do not name a file have no reason to be blocked by one; only
the placeholder that needs a file fails.

## Consequences

- `Prompt.render` interpolates the whole template in one pass (the per-line
  split/interpolate/join was mechanically equivalent), so the failing
  placeholder and the literal handling stay one implementation.
- `tests/commands/prompt_spec.lua` asserts the named file window is chosen
  while a later scratch float is skipped, and that a resolved value is not
  re-scanned for placeholders.
