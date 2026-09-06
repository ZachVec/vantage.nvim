# Agent Note: Trust non-nil annotations over defensive nil guards

Status: implemented

## Problem

Several call sites re-checked nil/empty on values whose producer already
guaranteed non-nil — a non-nil `---@return`, or a table key built from
`pairs()` over a sanitized config table. These redundant guards obscured the
real seams (where external input can genuinely be nil) and invited drift between
an annotation and the code that guards it.

## Decision

Downstream code trusts non-nil LuaLS annotations unconditionally. A `?` is
dropped and its call-site guard removed only when the value's producer is
provably non-nil from within the repo: a non-nil return annotation plus a caller
chain whose every input is controlled. External inputs — vim API results, tmux
`-F` / window-option state, user config/args, picker cancel callbacks, buffer
unload — are the boundary: validated once at the seam, trusted after.

Shipped removals:

- `annotation.lua` `field()` returns `string` (its unknown-name fallthrough now
  returns `""`); `render_item` and `M.location` drop the dead `or ""`.
- `annotation.lua` `M.get` drops a dead `or nil` tail (keeps `and by_id`).
- `annotation.lua` `M.set_active` drops its `M.get()` re-check (keeps the
  `nvim_buf_is_valid` seam check).
- `backend/tmux.lua` `M.create` drops the `opts.tool == nil or == ""` guard;
  `M.attach` drops the `target and target ~= ""` guard; `M.list` drops the
  `tool ~= ""` empty-check — `tool` is always a non-empty `cli.tools` key.
- `client.lua` `open_win` drops the `width and` / `height and` re-checks (the
  `or 0` default already made them non-nil).
- `commands/agent.lua` `create_with_tool` drops `if not tool`; the name is a
  `sanitize_tools`-validated `cli.tools` key.
- `commands/prompt.lua` `send_prompt` drops `if template == nil`; the name comes
  from `pairs(Config.options.prompts)`.
- `picker/fzf_lua.lua` and `picker/snacks.lua` drop `and spec.scope` (the
  `scope_on` flag already implies non-nil).

Kept, deliberately:

- The CRUD re-checks in `M.edit` / `M.delete` / `M.get`'s `and by_id` defend the
  `BufUnload` autocmd race: a buffer unload between `collect()` and the action
  clears `registry[buf]` — an external event, not an interior re-check.
- Every other nil return stays nil. A sweep of the sentinel producers found no
  case where a default value both exists and reduces downstream code: "not
  found", "error", and picker "cancel" are semantics a default would falsify,
  and `pane_preview` → `{}` would not remove the consumers' `if not lines`
  guard (`spec.preview` itself is optional).

## Alternatives considered

### Why not keep every guard?

The re-checks cost little individually, but they erode the interior/seam
distinction: a future reader cannot tell which `if x == nil` is load-bearing.
Trusting annotations makes the contract the single source of truth.

### Why not give every sentinel a default (return `""`/`{}` instead of nil)?

Only `field()` qualified. The other nil returns are "not found / error / cancel
/ N/A", where a default would be semantically false and would not shorten any
consumer (`if not lines` still guards an optional `spec.preview`).

### Why not strip every `x and y or nil` tail?

Only the boolean-guard ones stay. `tool`'s `(tool ~= "" and tool) or nil` was
removed because `tool ~= ""` is provably always true — `@agent-tool` is written
once, at creation, from a sanitized non-empty `cli.tools` key, so the empty
branch is unreachable. `state`'s `(state ~= "" and state) or nil` stays:
`@agent-state` has an external writer (`scripts/vantage-status`) and an unset
state is a real, distinct value that `scripts/vantage-counts` treats as idle.
The remaining `and … or nil` sites (`select.lua` `focused`, `snacks.lua`
`terminal_win`) stay too: their condition is a boolean that can be false, and
`or nil` normalizes `false` to `nil` for the `T?` annotations.

## Consequences

- LuaLS annotations are now the contract for nilability; a future in-repo caller
  that violates a non-nil parameter fails with a nil-index error instead of a
  graceful guard. That is the accepted trade: the annotation, not the guard,
  documents "must be non-nil".
- `M.create` no longer warns on an empty tool; its sole caller always passes a
  sanitized `cli.tools` key, so the warning was unreachable.
- The `field()` contract tightened to `string`, so its two callers' `or ""`
  became dead and were removed.
