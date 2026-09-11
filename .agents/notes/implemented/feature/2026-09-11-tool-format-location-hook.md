# Agent Note: Tool format hooks spell location references

Status: implemented

## Problem

Location references were written in the Claude dialect by the placeholders
themselves (`{file}` → `@<relpath>`, `{line}` → `@<relpath> :L<row>`), and a
Tool's `format(text)` hook rewrote the whole composed message. That works one
way only: *removing* the `@` marker is exact, but *adding* it is guesswork. A
template like `prompts = { review = "Review {file} for bugs." }` composes prose
around a path, and no whole-text hook can tell a path from an ordinary word, so
a tool whose dialect wants `@` had to invent a heuristic. The gather flow made
the mismatch concrete: its rows are lone paths, where per-row application is
exact — two shapes, one hook.

## Decision

The Tool's hook is `format(file, loc)`, the reference formatter:

- `file` is the path, relative to the focused Agent's cwd (absolute when it
  escapes), and is always a string.
- `loc` is the position suffix (`:L42`, `:L42:C3`, `:L2-4`), or nil for a
  whole-file reference.
- The return is the reference text; nil or "" gives up on that reference.

Vantage composes everything around the hook — template prose, the
`function foo ` prefix, Review notes — and spells every location through it:

- `{file}`, `{line}`, `{function}`, and `{class}`, with `loc` nil, `:L<row>`,
  and `:L<row>:C<col>` respectively;
- each Review's `{lines}` and `{file}` inside `reviews.item`;
- every gathered `files`/`buffers` row (path only, `loc` nil), joined with
  `setup { gather = { join = … } }`.

Without a hook, `Util.reference` spells `file` and, when there is a position,
`file .. " " .. loc` (`src/a.lua :L42`), so no dialect is baked in, and the
Claude dialect becomes one line of user config:

```lua
format = function(file, loc)
  return "@" .. file .. (loc and (" " .. loc) or "")
end
```

The review picker's previews and note titles resolve the focused Agent's
formatter when there is one, so they read what a send would produce.

## Alternatives considered

### Why not keep the Claude dialect as the base?

The marker makes translation *away* exact (`text:gsub("@(%S+)", "%1")`), but it
forces every tool to speak Claude first and made gather strip a marker it had
just carried. A bare base with the hook as the dialect layer leaves each tool
one function to write, whatever its syntax.

### Why not bare references with the whole-text hook?

Then a Claude hook has to find paths inside prose. A lone-token test misses
`{line}` (its bare form contains a space) and `{function}`; a path-shaped
`gsub` cannot tell `Makefile` from an ordinary word. Handing the hook `file` and
`loc` parts removes the guesswork.

### Why not a separate `format_refs` hook for gathered rows?

One hook per dialect is the point: a second function doubles the config surface
for every tool, and the reference-shaped signature already serves prompts,
Reviews, and gather alike.

### Why not pass a structured position (`row`, `col`, `end_row`)?

The hook's job is re-spelling the suffix a dialect wants; the token string
carries everything that needs, and a table would invite callers to build
location syntax Vantage then has to serialize anyway.

## Consequences

- `format(text)` is replaced by `format(file, loc)`: existing hooks must be
  rewritten, and a hook no longer sees the whole prompt — prose templates never
  call it.
- Placeholders keep their names and identity templates; only the rendered
  spelling changes (`{file}` no longer prefixes `@`).
- Supersedes the location-syntax parts of
  [the prompts note](2026-08-31-prompts.md) and
  [the annotations note](2026-09-01-annotations.md); the
  [gather note](2026-09-11-file-buffer-references.md) records the flows that
  feed the hook.
