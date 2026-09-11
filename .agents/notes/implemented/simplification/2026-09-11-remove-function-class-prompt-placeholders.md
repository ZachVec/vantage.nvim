# Agent Note: Drop the {function}/{class} prompt placeholders

Status: implemented

## Problem

Prompts shipped four context placeholders: `{file}` and `{line}` read plain
buffer state, while `{function}` and `{class}` resolved the enclosing
nvim-treesitter-textobjects `@function.outer` / `@class.outer` node at the
cursor. Only the function/class pair carried any of that weight — an optional
plugin dependency, a per-language `textobjects` query, and a node-name
heuristic — and when the plugin, the query, or an enclosing node was missing,
the whole prompt was skipped with a warning. No built-in prompt used them, so a
user template was the only way to reach them.

They were also the only placeholders whose value embedded prose
(`function foo ` / `class Foo `) rather than a location, so they composed
poorly: the Tool's `format(file, loc)` hook could re-spell the path but not the
prefix, which baked a prose shape into the reference itself.

## Decision

The Prompt vocabulary is `{file}`, `{line}`, and `{reviews}`
(`config.PROMPT_PLACEHOLDERS`).

- `commands/prompt.lua` drops `node_name`, `textobject`, and `resolve_symbol`,
  along with the two resolver entries. `vantage.PromptCtx` loses its `col`
  field, which only function/class resolution read.
- `health.lua` drops the function/class branch and its
  nvim-treesitter-textobjects probe.
- A template that still writes `{function}` or `{class}` is treated as an
  unknown placeholder: left literal at render time and flagged by
  `:checkhealth vantage`.

## Alternatives considered

**Keep the pair and report the plugin only through `:checkhealth`.** That was
the shipped shape — a warning instead of a skip was the most it could promise —
and it still carried the plugin probe, the textobject call, the name heuristic,
and the runtime skip path for placeholders no built-in prompt used. Deleting
them removes the one optional dependency Vantage's requirements listed.

**Replace both with a single `{symbol}` (innermost wins).** That still needs
treesitter and the `textobjects` query, and it trades two explicit questions
for one guessed answer; the [prompts note](../feature/2026-08-31-prompts.md)
rejected it for that reason, and it solves none of the composition problem.

**Resolve the enclosing node with `vim.treesitter` directly, without the
plugin.** Then Vantage owns a per-language query registry and the fallbacks for
languages without one — new surface area in a simplification, and one more
thing to keep current as parsers change.

## Consequences

- Vantage's requirements drop to Neovim and tmux: no prompt needs an optional
  plugin.
- Removing the placeholders is user-visible. A template that used them types
  the literal token instead of failing the prompt, and `:checkhealth vantage`
  reports the token as unknown until the template is edited.
- No reference carries a `:C<col>` suffix anymore: a Tool's `format(file, loc)`
  hook sees `:L<row>` (Prompts) or `:L<start>-<end>` (Reviews), or nil for a
  whole file.
- Partially supersedes the [prompts note](../feature/2026-08-31-prompts.md),
  which introduced the pair, and the
  [built-in defaults note](../feature/2026-09-01-prompts-built-in-defaults.md),
  which explained why they were not built in; both notes stay active for their
  other decisions.
