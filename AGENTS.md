# AGENTS.md

Vantage is a Neovim plugin — a coding-agent manager over tmux. Read [docs/glossary.md](docs/glossary.md) for domain terms and [docs/architecture.md](docs/architecture.md) for structure before naming or changing either.

## Repository layout

```
lua/vantage/       the plugin: Backend (Lua domain layer) + Frontend (UI)
  backend/         Backend interface + tmux driver (the seam for future drivers)
  client.lua       the single :terminal that is the tmux client
  commands.lua     :Vantage subcommand dispatch
  config.lua       defaults + shared LuaLS types
  picker.lua       vim.ui.select selection UI
  health.lua       :checkhealth vantage
  util.lua         shared helpers
doc/               vim help docs (:h vantage.nvim)
docs/              architecture + glossary (developer docs)
.agents/notes/     Agent Notes (proposals and decision records)
scripts/           repo gates (verify-agent-notes.lua)
Makefile           check entrypoint
stylua.toml        Lua formatting
```

## Commands

```sh
make check            # Agent Note gate + stylua --check when installed
make notes            # Agent Note gate only (needs only nvim)
stylua --check .      # Lua format check
```

There is no test suite or standalone linter wired yet; add one (and its `make` target) before claiming coverage.

## Conventions

- Lua 5.1 / LuaJIT only — Neovim's runtime; no features newer than 5.1.
- Every module is `local M = {}` … `return M`; imports use `require("vantage.…")`.
- Public functions carry LuaLS annotations (`---@param`, `---@return`, `---@class`); shared types live in `config.lua`.
- The [domain glossary](docs/glossary.md) is authoritative — use each term and honor each `_Avoid:` exactly; add or rename a term only there.
- Keep user-visible commands, help text, and defaults in sync in [doc/vantage.nvim.txt](doc/vantage.nvim.txt).
- **Non-trivial changes MUST include an Agent Note in the same change;** only mechanical/local edits are exempt ([when to write](.agents/notes/README.md#when-to-write-one)).

## Editing these instructions

Keep each rule self-contained while linking high-level docs; condense when clarity survives.
