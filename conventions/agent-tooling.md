# Agent Tooling Compatibility

Use these terms when a skill needs host capabilities. They keep the toolkit
portable across Claude Code, Codex, and other agent hosts.

## Structured Questions

`structured question mechanism` means the active host's UI for asking the user
one or more bounded questions with options.

- If the host exposes a native question tool, use it.
- In Claude Code compatibility mode this may be `AskUserQuestion`; if that tool
  is lazy-loaded, discover/load it using the host's documented mechanism.
- If no structured question tool is available, ask a numbered question in plain
  text and parse the user's reply.
- Locale keys with the `auq_` prefix are historical names. They mean "question
  prompt/options" and are not tied to a specific host tool.

## Subagent Dispatch

`subagent dispatch` means the active host's mechanism for running a unit of work in a separate
agent context — the Task tool with `subagent_type=<plugin>:<agent>` in Claude Code.

- Every `workflow-*` stage that names a role is dispatched this way, to the agent that role
  resolved to. The contract, including what to do when the host offers no such mechanism, is
  `conventions/stage-dispatch.md`.
- Some hosts carry a standing instruction not to spawn subagents unasked. A spine-toolkit command
  is the user asking; that skill's own text says so.

## File Access

`file-read mechanism`, `file-write mechanism`, and `file-edit mechanism` mean the
active host's approved way to read, create, or patch files.

- Follow the host's safety policy for writes and destructive operations.
- For template-based artifacts, preserve all bytes outside documented
  placeholders or insertion points.
- For Markdown artifacts parsed by the toolkit, preserve structural anchors from
  `conventions/i18n.md`.

## Plugin Roots And Templates

Two plugins ship `skills/` and `templates/`, so "the toolkit's directory" names nothing on its
own. Each root is identified by what only it carries:

- `core root` — the directory that contains `workflows/` and `skills/orchestrator/`.
- `platform root` — the directory that contains `agents/` and `skills/manifest/`.

A template belongs to exactly one plugin. Resolve it against that plugin's root, in this order:

1. `<root>/templates/...`, where `<root>` is the core root for a core template and the platform
   root for a platform one.
2. Installed plugin/cache paths exposed by the active host.
3. Claude Code compatibility paths such as `~/.claude/plugins/...`.

Host-specific paths are fallbacks, not the canonical source.
