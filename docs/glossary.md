# Glossary

One home per domain term. Code, docs, and Agent Notes use these terms exactly and honor each `_Avoid:`; add or rename a term only here. How these terms relate is [architecture.md](architecture.md).

## Group

A durable container of collaborating Agents, derived from them: it exists only because Agents are placed in it, and is never created or attached independently. Creating an Agent in a non-existent Group creates the Group.
_Avoid_: workspace, topic, 主题

## Anchor

The one persistent session in a Group that owns its Agents. Created with the Group and never auto-destroyed; it keeps the Group (and its Agents) alive even when every View has closed. Views are grouped sessions attached to it. Destroyed only by `kill <group>`.
_Avoid_: leader, base session

## Agent

A running coding-agent process (claude, codex, dsh, …) operating in a working directory (Cwd), shared across a Group's Views. An Agent lives until it is killed with `kill` or exits on its own; closing a Client never kills it.
_Avoid_: worker

## View

A transient session within a Group, giving a single Client an independent display of an Agent. Each attach creates a View; the Views of a Group share the same Agents but each shows its own active Agent. A View ends when its own client detaches (its terminal is closed) or the client re-targets into another Group — the driver destroys the abandoned View and creates a fresh one in the target Group — the Anchor and other Views survive. When all of a Group's Agents die, the Anchor and every View die with it. Views never accumulate.
_Avoid_: session, workspace

## Cwd

The working directory an Agent runs in. Resolved by the Frontend (the current window's local cwd, respecting `:lcd`/`:tcd`) and passed to the Backend explicitly; the Backend never infers it.
_Avoid_: repo, directory

## State

A transient status of an Agent (done, waiting-for-confirmation, …). Not yet surfaced; the plugin leaves room for it.
_Avoid_: status

## Backend

The plugin's Lua domain layer that owns all state and domain logic and drives a terminal multiplexer. It is a pluggable interface: a Driver such as `tmux` implements it, with room for `zellij` and others later. Every operation is explicit: the Backend never infers context from the caller's environment.
_Avoid_: api, server

## Driver

A concrete multiplexer implementation behind the Backend interface — `tmux` today, `zellij` later.
_Avoid_: adapter

## Frontend

The plugin's UI layer: the Picker and the single `:terminal` that is the Client. Backend and Frontend live in the same plugin.
_Avoid_: client, ui

## Client

A display surface attached to a View (backed by a tmux client). The Frontend operates exactly one: the single `:terminal`, re-targeted with each switch.
_Avoid_: terminal, screen

## Picker

The plugin's pluggable selection UI, rendering every Vantage selection — the Agent list, the kill list, the Agent-creation Group step, and `:Vantage prompt` — chosen via `setup { picker = … }`: `native` (vim.ui.select, following any global override by definition), `fzf-lua`, or `snacks`. Implementations render plain choices with their own engine (snacks' compact select layout, fzf-lua's ui_select shim) so a flow never mixes renderer families. Light Yes/No confirmations use Neovim's built-in confirm dialog, not the Picker.
_Avoid_: launcher

## Tool

A named launch command (`name` → `cmd` array) offered when creating an Agent. Configured under `cli.tools`.
_Avoid_: command, template

## Prompt

A named text template typed into a focused Agent's input. Two are built in — `{file}` and `{line}`, as identity templates — and user templates merge additively under `setup { prompts = { name = "…" } }` (a name you set overrides the built-in; unlisted defaults are kept). Rendered against the current context (`{file}`, `{line}`, `{function}`, `{class}`) or the accumulated Annotations (`{annotations}`) before being sent.
_Avoid_: snippet

## Annotation

A user-written note anchored to a line range in a normal file, collected across buffers and batched into a focused Agent's input through the `{annotations}` prompt placeholder. Stored only in memory (an extmark plus a per-buffer registry), so it is lost on buffer unload/reload or Neovim exit and never edits the file. Configured under `setup { annotations = { item = …, clear_on_send = … } }`.
_Avoid_: comment, note, remark, mark
