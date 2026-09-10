# Agent Note: Shell-quote tool argv before launching an Agent

Status: implemented

## Problem

`cli.tools.<name>.cmd` is typed as `string[]`, but the create flow joined
it with plain spaces and handed the result to tmux as a shell command. An
argument containing spaces, quotes, or shell metacharacters therefore lost its
argv boundary. For example, a tool command like `{ "sh", "-c", "echo hi" }`
became the shell string `sh -c echo hi`, which runs `echo` with the wrong
arguments.

## Decision

`vantage.util` now owns `shell_quote(arg)` and `shell_join(args)`. They produce
POSIX `sh -c` single-quoted arguments:

- an ordinary argument becomes `'arg'`;
- an empty argument becomes `''`;
- an embedded single quote is escaped as `'\''`.

`backend/bridge.lua` builds the Agent command with
`Util.shell_join(tool.cmd)` before passing it to the Backend. The Backend still
receives a shell-command string, so no tmux-driver contract changes.

README and the vim help now describe `cmd` as an argv array whose elements are
shell-quoted, rather than "run verbatim".

## Alternatives considered

### Why not change `cli.tools.cmd` from `string[]` to a shell string?

That would abandon the safer typed configuration surface and force users to
write shell quoting by hand.

### Why not pass argv directly to tmux?

tmux's `new-session` and `new-window` shell-command field expects one command
string, not an argv vector. There is no direct argv execution seam in the
current driver without wrapping the command in another process.

### Why not add a full POSIX shell parser?

The command is executed by the Agent's shell; Vantage only needs to preserve
argument boundaries. Single-quote escaping is the standard minimal solution.

## Consequences

- Tool commands with spaces, empty arguments, and single quotes now retain
  their argv semantics.
- The stored `@agent-cmd` value is the shell-quoted string; list/status output
  may show quoting where it previously showed the raw joined string.
- `Util.shell_join` is reusable by any future Backend command construction that
  must go through a shell.
