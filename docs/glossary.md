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

A transient session within a Group, giving a single Client an independent display of an Agent. Each attach creates a View; the Views of a Group share the same Agents but each shows its own active Agent. A View ends when its own client detaches (its terminal is closed) — the Anchor and other Views survive. When all of a Group's Agents die, the Anchor and every View die with it. Views never accumulate.
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

The plugin's pluggable selection UI for choices with something to preview — the Agent list, the kill list, and the `files` / `buffers` Actions — chosen via `setup { picker = … }`: `native` (vim.ui.select), `fzf-lua`, or `snacks`. The Actions are available only under `fzf-lua` / `snacks`. Selections with nothing to preview (the Tool and Group choice during Agent creation, and the `:Vantage prompt` name list) use `vim.ui.select` directly, not the Picker.
_Avoid_: launcher

## Tool

A named launch command (`name` → `cmd` array) offered when creating an Agent. Configured under `cli.tools`.
_Avoid_: command, template

## Prompt

## Prompt

A named entry typed into a focused Agent's input, chosen via `:Vantage prompt`. Two kinds: a Template (a string rendered against the current context) and an Action (a built-in `files` / `buffers` that opens a picker and types the selected references).
_Avoid_: snippet

## Template

The string kind of a Prompt: a text template with placeholders (`{file}`, `{line}`, `{function}`, `{class}`), rendered against the focused Agent's cwd before being sent; `{annotations}` renders the accumulated Annotations. Three are built in — `{file}`, `{line}`, and `{annotations}`, as identity templates — and user templates merge additively under `setup { prompts = { name = "…" } }` (a name you set overrides the built-in; unlisted defaults are kept).
_Avoid_: snippet

## Action

The picker kind of a Prompt: a built-in `files` or `buffers` that opens a picker, lets the user select several files or buffers, and types the resulting location references into the focused Agent. Available only with the `fzf-lua` or `snacks` Picker.
_Avoid_: dynamic prompt, picker prompt, interactive prompt

## Annotation

A user-written note anchored to a line range in a normal file, collected across buffers and batched into a focused Agent's input through the `{annotations}` prompt placeholder. Stored only in memory (an extmark plus a per-buffer registry), so it is lost on buffer unload/reload or Neovim exit and never edits the file. Configured under `setup { annotations = { item = …, clear_on_send = … } }`.
_Avoid_: comment, note, remark, mark
