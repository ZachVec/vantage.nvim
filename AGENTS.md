# AGENTS.md

Vantage is a Neovim plugin — a coding-agent manager over tmux. Read [docs/glossary.md](docs/glossary.md) for domain terms and [docs/architecture.md](docs/architecture.md) for structure before naming or changing either.

## Repository layout

```
lua/vantage/       the plugin: Backend (Lua domain layer) + Frontend (UI)
  init.lua         composition root: apply config, resolve seams, install runtime
  backend/         Bridge + pluggable Driver registry/tmux implementation
  frontend/        terminal, display, note, review, pluggable picker
  commands/        dispatch + actions, terminal_keys, attach, flows
  config.lua       defaults + shared LuaLS types
  health.lua       :checkhealth vantage
  util.lua         shared helpers
doc/               vim help docs (:h vantage.nvim)
docs/              architecture + glossary (developer docs)
.agents/notes/     Agent Notes (proposals and decision records)
scripts/           repo gates (verify-agent-notes.lua, verify-architecture.lua)
tests/             mini.test specs + test bootstrap
Makefile           check entrypoint
stylua.toml        Lua formatting
```

## Commands

```sh
make check            # Agent Notes + stylua + architecture + lua-language-server
make notes            # Agent Note gate only (needs only nvim)
make architecture     # module dependency-direction gate
make test             # mini.test + luassert suite (first run installs deps under .tests/)
stylua --check .      # Lua format check
```

Tests live in `tests/**/*_spec.lua` and run with `make test`; the tmux backend
specs require tmux and use a private per-run socket. `make check` runs
lua-language-server when installed; `make architecture` enforces the module
dependency directions documented in [docs/architecture.md](docs/architecture.md).

## Conventions

- Lua 5.1 / LuaJIT only — Neovim's runtime; no features newer than 5.1.
- Every module is `local M = {}` … `return M`; imports use `require("vantage.…")`.
- Public functions carry LuaLS annotations (`---@param`, `---@return`, `---@class`); shared types live in `config.lua`.
- The [domain glossary](docs/glossary.md) is authoritative — use each term and honor each `_Avoid:` exactly; add or rename a term only there.
- Keep the public docs current in the same change: if a change makes [README.md](./README.md) or [doc/vantage.nvim.txt](doc/vantage.nvim.txt) stale — user-visible commands, help text, defaults, install, or described behavior — update the affected file in that change.
- **User-facing docs say what, not why.** [README.md](./README.md) and [doc/vantage.nvim.txt](doc/vantage.nvim.txt) describe only what a user does or sees: commands, options, defaults, install, and any user-facing trade-off, compressed to what the user decides. Never implementation mechanics, Neovim/engine internals, or historical rationale in them — that belongs in the Agent Note, code comments, or [developer docs](docs/architecture.md).
- **Non-trivial changes MUST include an Agent Note in the same change;** only mechanical/local edits are exempt ([when to write](.agents/notes/README.md#when-to-write-one)).

## External-tool gotchas

See [docs/gotchas.md](docs/gotchas.md).

## Editing these instructions

Keep each rule self-contained while linking high-level docs; condense when clarity survives.
