# Glossary

One home per domain term. Code, docs, and Agent Notes use these terms exactly and honor each `_Avoid:`; add or rename a term only here. How these terms relate is [architecture.md](architecture.md).

## Group

A durable container of collaborating Agents, represented by one tmux session group: a persistent Anchor owns the Agent windows and transient Views provide each Terminal client an independent current window. Creating an Agent in a non-existent Group creates its Anchor. A Group survives with nothing attached to it, and ends only when its last Agent dies or it is killed.
_Avoid_: workspace, topic, 主题

## Anchor

The persistent session that owns a Group's Agent windows. It is named after the Group, is never attached directly by the plugin, and survives with no client attached so Agents remain headless.
_Avoid_: master session, base session

## View

A transient tmux session grouped with an Anchor and attached by exactly one Terminal client. A View's current window is independent from every other client's View; it is destroyed when its client detaches or moves to another Group.
_Avoid_: client session, workspace

## Agent

A running coding-agent process (claude, codex, dsh, …) operating in a working directory (Cwd), shared across a Group. An Agent lives until it is killed or exits on its own; closing a Terminal never kills it.
_Avoid_: worker

## Cwd

The working directory an Agent runs in. Resolved by the command flow from the global Neovim working directory (it follows `:cd`, not `:lcd`/`:tcd`) and passed to the Backend explicitly; the Backend never infers it.
_Avoid_: repo, directory

## State

A transient condition of an Agent drawn from a fixed vocabulary of five: `running`, `background`, `waiting`, `idle`, `error`. Written as `idle` by the Backend when an Agent is created, then replaced on each transition by the Agent's lifecycle scripts as a full-value option (never read-modify-write); the plugin aggregates States per Group read-only into the pane border's counts segment.
_Avoid_: status

## Backend

The plugin's Lua domain layer that owns Agent state and lifecycle logic and drives a terminal multiplexer. It is a Bridge over a pluggable Driver — `tmux` implements the Driver today, with room for `zellij` later. Every operation is explicit: the Backend never infers context from the caller's environment.
_Avoid_: api, server

## Bridge

The Backend's public surface that the Frontend consumes: domain verbs (`agents`, `create`, `retarget`, `send`, `capture`, `attach`, `kill_view`, `kill_agent`, `kill_group`, `status`) and the entity lists built above them. It holds no state, knows no UI, and passes Driver results/errors through; every multiplexer detail is left to the Driver.
_Avoid_: service, orchestrator

## Driver

A concrete multiplexer implementation behind the Bridge — `tmux` today, `zellij` later. The Driver is pure multiplexer mapping: it exposes the domain-shaped verb surface, outputs neutral records with an opaque Agent `id` and creation `seq`, creates/destroys Views for the Terminal attachment lifecycle, returns explicit operation errors instead of notifying, and keeps every tool-specific command syntax inside it.
_Avoid_: adapter

## Frontend

The plugin's UI layer: the Picker and the single `:terminal` that is the Terminal, plus display helpers, the Review storage, and the note float. The Frontend imports the Backend through the Bridge; the Backend never imports the Frontend.
_Avoid_: client, ui

## Terminal

The plugin's one display surface: a single `:terminal` per Neovim instance, opened on an attach command for a per-client View produced by the Backend. Its existence is the attachment's existence — the terminal's job is the attached client, so when the job exits the terminal closes and its View is destroyed, and hiding it keeps the attachment alive.
_Avoid_: client, screen, window

## Terminal action

A named action available only from a keymap inside the Terminal: `toggle`, `switch`, `prompt`, `files`, or `buffers`. The gather actions `files` and `buffers` pick rows through the Picker and type their file references into the focused Agent's input. Configured as the `rhs` string of a `cli.win.keys` entry; any other `rhs` value is installed as an ordinary keymap.
_Avoid_: action (unqualified), terminal key, shortcut

## Picker

The plugin's pluggable selection UI, rendering every Vantage selection — the Agent list, the kill list, the Review list, the Agent-creation Group step, the Prompt choice, and the references gathered by `files`/`buffers` — chosen via `setup { picker = … }`: `native` (vim.ui.select, following any global override by definition), `fzf-lua`, or `snacks`. The `vantage.frontend.picker` facade exposes `pick(spec, opts)`, `pick_multi(spec, opts)`, and `pick_plain(...)`; implementations declare exactly three capabilities, `preview`, `command`, and `multi`, and degrade optional capabilities explicitly — a picker without `multi` renders a multi-selection request as a single choice. Light Yes/No confirmations use Neovim's built-in confirm dialog, not the Picker.
_Avoid_: launcher

## Picker command

A keymap-shaped command supplied by a flow to a command-capable Picker: `{ lhs, rhs, desc? }`, where `rhs(ctx)` receives the neutral `{ item, items }` context and returns `true` when the item list may have changed. Delete and group-scope operations are ordinary Picker commands; the Picker knows no flow semantics.
_Avoid_: action, keybinding

## Tool

A named launch command (`name` → `cmd` array) offered when creating an Agent. Configured under `cli.tools`.
_Avoid_: command, template

## Prompt

A named text template typed into a focused Agent's input. Two are built in — `{file}` and `{line}`, as identity templates — plus `{reviews}`, and user templates merge additively under `setup { prompts = { name = "…" } }` (a name you set overrides the built-in; unlisted defaults are kept). Rendered against the current context (`{file}`, `{line}`) or the accumulated Reviews (`{reviews}`) before being sent.
_Avoid_: snippet

## Review

A user-written note anchored to a line range in a normal file, collected across buffers and batched into a focused Agent's input through the `{reviews}` prompt placeholder. Stored only in memory (an extmark plus a per-buffer registry), so it is lost on buffer unload/reload or Neovim exit and never edits the file. Configured under `setup { reviews = { item = …, clear_on_send = … } }`.
_Avoid_: annotation, comment, note, remark, mark
