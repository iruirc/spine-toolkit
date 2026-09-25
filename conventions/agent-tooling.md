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
- The model and effort a dispatch runs with come from
  `conventions/stage-dispatch.md` → Model and effort. In Claude Code the model travels as the
  dispatch's `model` parameter; the dispatch has no effort parameter.
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
- `platform root` — the directory that contains a `manifest` skill. (Not "and an `agents`
  folder": a platform that declares all nine roles absent legally ships none.)

A template belongs to exactly one plugin. Resolve it against that plugin's root, in this order:

1. `<root>/templates/...`, where `<root>` is the core root for a core template and the platform
   root for a platform one.
2. Installed plugin/cache paths exposed by the active host.
3. Claude Code compatibility paths such as `~/.claude/plugins/...`.

Host-specific paths are fallbacks, not the canonical source.

## Finding files

A file a stage needs is looked for only under the roots its brief's `Search roots:` line names —
the project root, every checkout `## Paths` lists under `External packages`, every folder it lists
under `Roots` — the core root, and the base directory of a skill you loaded. Never search from `/`,
from `~`, or from a folder above those roots. A file under none of them is missing: stop, and
report the file and the roots you searched instead of widening the search.

## Long-running commands

A command that can run longer than a minute — a build, a full test run, a UI test run — starts
through `scripts/long-run.sh start`, never in the foreground. Do not silence its output
(`-quiet`, `-q`): a quiet build is indistinguishable from a hung one. Then call `wait` until
it returns something other than `running`. On `done`, read the exit code and the tail. On
`stalled` or `timeout`, capture what shows why — the tail, the process tree, the platform's own
state — then `stop`, and report the command as hung or over budget, not as failed. Pass
`--stall` and `--max` exactly as your brief gives them. Give each `wait` call a tool timeout
above its `--for`, or pass a `--for` your tool's limit allows. `start` also records the job
for the orchestrator, which shows the user every job still running after the stage: `stop` what
you started.
