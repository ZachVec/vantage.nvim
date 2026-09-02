# AGENTS.md

Vantage is a Neovim plugin — a coding-agent manager over tmux. Read [docs/glossary.md](docs/glossary.md) for domain terms and [docs/architecture.md](docs/architecture.md) for structure before naming or changing either.

## Repository layout

```
lua/vantage/       the plugin: Backend (Lua domain layer) + Frontend (UI)
  backend/         Backend interface + tmux driver (the seam for future drivers)
  client.lua       the single :terminal that is the tmux client
  commands.lua     :Vantage subcommand dispatch
  config.lua       defaults + shared LuaLS types
  picker/          pluggable selection UI (native / fzf-lua / snacks)
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
- Keep the public docs current in the same change: if a change makes [README.md](./README.md) or [doc/vantage.nvim.txt](doc/vantage.nvim.txt) stale — user-visible commands, help text, defaults, install, or described behavior — update the affected file in that change.
- **Non-trivial changes MUST include an Agent Note in the same change;** only mechanical/local edits are exempt ([when to write](.agents/notes/README.md#when-to-write-one)).

## External-tool gotchas

Read [docs/gotchas.md](docs/gotchas.md) before building anything that touches
tmux, claude/codex, fzf-lua, snacks, or cursor/insert-mode behavior. Highlights:

- `tmux send-keys -l` collapses newlines in claude — use bracketed paste
  (`set-buffer` + `paste-buffer -p`) and do NOT append a trailing `\n`.
- fzf-lua `fzf_exec` function contents writes one item per callback (call
  `cb(item)` per item, then `cb(nil)`); in-place reload is `{ fn, reload = true }`.
- snacks finder is `fun(opts, ctx): result`; keymaps live in `win.<pane>.keys`
  (not `keymaps`); `picker:refresh()` re-runs the finder.
- `<cmd>` mappings keep Visual mode active, so `'<`/`'>` marks aren't set yet;
  `normal! \27` first, then read them.

## Editing these instructions

Keep each rule self-contained while linking high-level docs; condense when clarity survives.
