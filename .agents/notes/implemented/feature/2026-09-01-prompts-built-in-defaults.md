# Agent Note: Prompts — built-in {file}/{line} defaults

Status: implemented

## Problem

[Prompts](2026-08-31-prompts.md) shipped with `prompts = {}` — "nothing built
in" — so a fresh install had no prompts at all and `:Vantage prompt` warned
"no prompts configured" until the user wrote their own templates. The one
capability every prompt depends on — dropping the focused file or line
reference into the Agent — should work out of the box, without setup.

## Decision

`prompts` ships with three built-in identity templates:

```lua
prompts = {
  ["{file}"] = "{file}",
  ["{line}"] = "{line}",
  ["{annotations}"] = "{annotations}",
}
```

Each is named by its own placeholder and expands to nothing but that
placeholder, so the raw location references and the accumulated Annotations are
always available. The `{annotations}` prompt is hidden from `:Vantage prompt`
while there are no Annotations, so a zero-config install with none sees only
`{file}` and `{line}`. Composed prompts (`review`, `fix`, `explain`, …) are
deliberately not built in — they are opinionated prose and belong in the user's
`setup`. User `prompts` merge additively (the existing
`vim.tbl_deep_extend("force", defaults, opts)`): a name the user sets overrides
the built-in, and names left unset are kept.

`{function}` and `{class}` are not built in either: they need the optional
nvim-treesitter-textobjects plugin, and shipping them would make every default
install without it report a `:checkhealth` warning and skip those prompts at
runtime. They remain available as placeholders in user templates.

Because `prompts` can no longer be empty, the "no prompts configured" warning
in `:Vantage prompt` and the "prompts: none configured" `:checkhealth` branch
became dead and were removed. `prompts` stays `table<string, string>` — there
is no per-name disable sentinel or whole-table opt-out.

## Alternatives considered

### Why not a composed default library (`review`, `fix`, `explain`)?

Composed prompts presume intent and phrasing; they are exactly what varies per
user. Identity templates are universal and carry no opinion, so they are the
only prompts that can be "correct" for everyone out of the box.

### Why not build in `{function}` and `{class}` too?

They require nvim-treesitter-textobjects. A built-in set should keep a minimal
install (Neovim + tmux) warning-free; a default that emits a `checkhealth`
warning for everyone without an optional plugin is noise. The placeholders stay
usable in user templates, which is where that dependency is expected.

### Why not replace-all merge?

`vim.tbl_deep_extend` already merges additively, and "add default options" is
the point: a user who sets `prompts = { review = "…" }` should keep the
built-ins, not silently drop them. Replace-all would make an empty or partial
`prompts` table erase the defaults.

### Why no disable/opt-out mechanism?

The two built-ins only appear when the user invokes `:Vantage prompt`, and a
name can already be overridden with the user's own template. "Zero prompts"
has no value for a pure-text, opt-in feature, so a `false` sentinel or a
`prompts = false` spelling would add config surface for nothing.

## Consequences

- The [prompts note](2026-08-31-prompts.md) recorded "built-in prompt library
  deliberately unsupported" as a scope choice; this note reverses that one
  point. The rest of that note (placeholders, `send_keys`, per-tool `format`)
  is unchanged and still authoritative.
- `prompts` is never empty, so `:Vantage prompt` always has entries and the
  empty-state warning/report are gone from `commands/prompt.lua` and `health.lua`.
- Defaults use only `{file}` and `{line}`, so a zero-config install reports a
  clean `:checkhealth` and never needs nvim-treesitter-textobjects.
