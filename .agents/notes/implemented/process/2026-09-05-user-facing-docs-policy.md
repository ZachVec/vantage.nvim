# Agent Note: User-facing docs say what, not why

Status: implemented

## Problem

README.md (and doc/vantage.nvim.txt) repeatedly carried implementation
rationale next to user-facing text — the `'laststatus'` layout mechanics and
Neovim float-close/redraw internals behind the terminal window layouts, the
float cursor-flicker mechanism, engine teardown detail. The reader of the
user-facing docs is a user who wants commands, defaults, options, and at most
a one-line trade-off to decide something ("which layout"): the mechanics
lesson sat in their way, the "keep public docs current" rule only said *when*
to update the docs, never *what belongs* there, and the rationale already had
a home (Agent Notes, code comments, developer docs) — so nothing marked where
the boundary is and the drift repeated.

## Decision

AGENTS.md's Conventions now carries the rule: user-facing docs say **what, not
why** — README.md and doc/vantage.nvim.txt describe only what a user does or
sees (commands, options, defaults, install, user-facing trade-offs compressed
to what the user decides); implementation mechanics, Neovim/engine internals,
and historical rationale go in the Agent Note, code comments, or developer
docs. The float layout texts in README.md and doc/vantage.nvim.txt were
rewritten to the behavior ("borderless, full-editor-size float, no
statusline/winbar; use `full` if the cursor flickers; width/height are
fractions of the editor area") with the mechanism left where the rationale
belongs — the float-layout Agent Notes and the `config.lua` comments.

## Alternatives considered

### Why not just lean on the existing "keep public docs current" rule?

It governs *whether* stale docs get updated, not *what content type* belongs:
the drift was a content-type problem, and the rule's silence is what let the
rationale into the README repeatedly. The new rule closes the specific gap.

### Why not put the boundary in docs/architecture.md instead?

Architecture.md describes the shipped structure, not writing policy. The
rule is a convention about documentation (a process decision), and
AGENTS.md's Conventions section is where the repo's writing rules live and
where every subsequent author reads them.

### Why not append the rationale to the README as an "under the hood" section?

A user-facing doc with an internals appendix invites the same drift division
back into the file (and a section that grows with each mechanism). The rule
says *where* the rationale goes, with no shelf in the user docs at all.

## Consequences

- The rule applies to README.md and doc/vantage.nvim.txt from now on; a
  change that wants to explain *why* carries it in the Agent Note, a code
  comment, or docs/ (architecture/gotchas/glossary).
- docs/gotchas.md remains the developer-facing home for engine gotchas
  (snacks/fzf-lua close semantics etc.) — it is not a user-facing file and is
  outside the rule.
- The float-layout rationale stays in the feature notes
  ([float default](../feature/2026-09-05-float-terminal-layout-default.md),
  [opt-in](../feature/2026-09-05-float-terminal-layout-opt-in.md),
  [full layout](2026-09-03-full-terminal-layout.md)) and the `config.lua`
  comments, unchanged.
