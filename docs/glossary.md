# Glossary

One home per domain term. Code, docs, and Agent Notes use these terms exactly and honor each `_Avoid:`; add or rename a term only here. How these terms relate is [architecture.md](architecture.md).

## Group

A durable container of collaborating Agents, derived from them: it exists only because Agents are placed in it, and is never created or attached independently. Creating an Agent in a non-existent Group creates the Group. A Group survives with nothing attached to it, and ends only when its last Agent dies or it is killed.
_Avoid_: workspace, topic, 主题

## Agent

A running coding-agent process (claude, codex, dsh, …) operating in a working directory (Cwd), shared across a Group. An Agent lives until it is killed or exits on its own; closing a Terminal never kills it.
_Avoid_: worker

## Cwd

The working directory an Agent runs in. Resolved by the Frontend from the global Neovim working directory (it follows `:cd`, not `:lcd`/`:tcd`) and passed to the Backend explicitly; the Backend never infers it.
_Avoid_: repo, directory

## State

A transient condition of an Agent drawn from a fixed vocabulary of five: `running`, `background`, `waiting`, `idle`, `error`. Written as `idle` by the Backend when an Agent is created, then replaced on each transition by the Agent's lifecycle scripts as a full-value option (never read-modify-write); the plugin aggregates States per Group read-only into the pane border's counts segment.
_Avoid_: status

## Backend

The plugin's Lua domain layer that owns all state and domain logic and drives a terminal multiplexer. It is a Bridge over a pluggable Driver — `tmux` implements the Driver today, with room for `zellij` later. Every operation is explicit: the Backend never infers context from the caller's environment.
_Avoid_: api, server

## Bridge

The Backend's public surface that the Frontend consumes: pure-data domain verbs (`agents`, `create`, `retarget`, `send`, `capture`, `attach_command`, `kill_agent`, `kill_group`, `status`) and the entity lists built above it. It holds no state and knows no UI; every multiplexer detail is left to the Driver.
_Avoid_: service, orchestrator

## Driver

A concrete multiplexer implementation behind the Bridge — `tmux` today, `zellij` later. The Driver is pure multiplexer mapping: it exposes the domain-shaped verb surface and outputs neutral records, and every tool-specific command syntax lives inside it.
_Avoid_: adapter

## Frontend

The plugin's UI layer: the Picker and the single `:terminal` that is the Terminal, plus the entry builders, the Review storage, and the note float. The Frontend imports the Backend through the Bridge; the Backend never imports the Frontend.
_Avoid_: client, ui

## Terminal

The plugin's one display surface: a single `:terminal` per Neovim instance, opened on an attach command produced by the Backend. Its existence is the attachment's existence — the terminal's job is the attached client, so when the job exits the terminal closes, and hiding it keeps the attachment alive.
_Avoid_: client, screen, window

## Picker

The plugin's pluggable selection UI, rendering every Vantage selection — the Agent list, the kill list, the Review list, the Agent-creation Group step, and the Prompt choice — chosen via `setup { picker = … }`: `native` (vim.ui.select, following any global override by definition), `fzf-lua`, or `snacks`. Implementations render plain choices with their own engine so a flow never mixes renderer families. Light Yes/No confirmations use Neovim's built-in confirm dialog, not the Picker.
_Avoid_: launcher

## Tool

A named launch command (`name` → `cmd` array) offered when creating an Agent. Configured under `cli.tools`.
_Avoid_: command, template

## Prompt

A named text template typed into a focused Agent's input. Two are built in — `{file}` and `{line}`, as identity templates — plus `{reviews}`, and user templates merge additively under `setup { prompts = { name = "…" } }` (a name you set overrides the built-in; unlisted defaults are kept). Rendered against the current context (`{file}`, `{line}`, `{function}`, `{class}`) or the accumulated Reviews (`{reviews}`) before being sent.
_Avoid_: snippet

## Review

A user-written note anchored to a line range in a normal file, collected across buffers and batched into a focused Agent's input through the `{reviews}` prompt placeholder. Stored only in memory (an extmark plus a per-buffer registry), so it is lost on buffer unload/reload or Neovim exit and never edits the file. Configured under `setup { reviews = { item = …, clear_on_send = … } }`.
_Avoid_: annotation, comment, note, remark, mark
