# Runtime: Codex CLI

This file maps the Claude Code tools spine-toolkit's skills name to Codex CLI (checked on 0.162.1).
The orchestrator and setup send you here from their Runtime paragraphs; every skill they load names the same
tools, so read this file once, before anything else, and apply it to all of them. The methodology
does not change: the same stages, the same artifacts, the same contract — only the tool that
carries each step.

`<runtime>` is `codex-cli`. Settings resolve with `--runtime codex-cli`, which selects
`runtimes/codex-cli.json`: any model name is accepted, and every role defaults to `session`.

## Tools

| A skill says | In Codex CLI |
|---|---|
| invoke / load a skill (`spine-toolkit:workflow-*`, `<platform>:manifest`, `<platform>:*-setup`, `spine-toolkit:stack-detect`) through the `Skill` tool | Read its `SKILL.md` — `<core root>/skills/<name>/SKILL.md` for a `spine-toolkit:` skill, `<platform root>/skills/<name>/SKILL.md` for a platform's — and follow it in this context. Skills the orchestrator drives are hidden from Codex's own skill list on purpose; they are still files you read. The `args` a skill would receive are the contract as text: keep the `key=value` lines in your context and treat them as that skill's input. |
| dispatch a stage to the agent its role resolved to (Task tool, `subagent_type=<plugin>:<agent>`) | `collaboration.spawn_agent` with `fork_turns: "none"`, `task_name: "<stage>_<task id>"` in lowercase letters, digits and underscores (`research_509`), and `message` = the stage brief `conventions/stage-dispatch.md` defines, opened by one line: ``Your role instructions are the body of `<platform root>/agents/<agent>.md` after its frontmatter; read that file first and follow it.`` — `<agent>` being the part of the resolved name after `<plugin>:`. Then `collaboration.wait_agent` with `timeout_ms: 3600000`, again after every update, until the agent has finished. Its final message is the stage report. |
| the dispatch's model and effort (`conventions/stage-dispatch.md` → Model and effort) | `session` → pass neither. Any other value → `model` and `reasoning_effort` on `spawn_agent` (Codex accepts them only with `fork_turns: "none"`, which every dispatch here uses). Unlike Claude Code, effort can be passed, so the "every stage runs at the session's effort" note does not apply. |
| `AskUserQuestion` / AUQ / structured question mechanism | `functions.request_user_input` when its description says it is available in Default mode (the user enabled `default_mode_request_user_input`) — the CLI shows it as a menu. One to three questions, each with two or three options from the same locale keys, the recommended one first; Codex adds the free-form answer itself, so leave out an "Other" option. Otherwise — its description names only Plan mode, a call fails with `request_user_input is unavailable in Default mode`, or a question has more than three options — a plain message: the question, then numbered options, the recommended one first, and one line saying the user may answer with its number or in their own words. Then end your turn and do nothing else until the answer comes. Every question a spine-toolkit skill asks — the manual-mode confirmations included — is a choice the methodology requires, not a permission request. Do not use `functions.request_user_input_async`: the CLI shows its options as an unnumbered list. |
| `Workflow` (Method A) | Absent. The orchestrator's choice already falls to Method B; `method_reason` is that the host has no `Workflow` tool. |
| the opening block (a `PreToolUse` hook) | No hook runs. The orchestrator's final report names the run: runtime `codex-cli`, Method B and why, once (see **What the user sees**). |
| `TaskStop`, the `watch` step, `agent-metrics.sh` | Do not apply: they belong to Method A or read Claude Code transcripts. |

`<core root>` and `<platform root>` are found by content (`conventions/agent-tooling.md` → Plugin
Roots). Codex installs a plugin as a copy under `$CODEX_HOME/plugins/cache/<marketplace>/<plugin>/<version>/`;
the skill Codex loaded from there tells you the root of its own plugin.

## What the user sees

The user reads the same reports as in Claude Code, and nothing about the plumbing:

- A stage report says what the stage found or changed, its artifact and its checks — nothing else.
- Runtime `codex-cli`, Method B, and a leftovers check skipped because `ps` is refused are named
  only in the final report, once each.
- A question is the question and its options. Never paraphrase this file, a `SKILL.md`, a locale
  key or a path to a skill to the user, and never explain how the question is being asked.

## Standing authorization

Codex allows spawning agents when the user or the applicable skill instructions ask for it. A
spine-toolkit skill the user invoked (`$spine-toolkit:orchestrator …`, `$spine-toolkit:setup`) is that
request for every stage of the task (`conventions/stage-dispatch.md` → Standing authorization).

## Scripts

`stage-leftovers.sh` and `long-run.sh` take the nearest `codex` process above them as the session.
They read the process table with `ps`, which Codex's `workspace-write` sandbox refuses
(`Operation not permitted`).

## Known limits

- **Stage leftovers in a sandbox.** When `stage-leftovers.sh snap` exits 2 with `ps is not permitted here`,
  leftovers cannot be measured in this run: skip `snap` and `diff` for the rest of it and say so once
  in the final report. Run without the sandbox, they work as in Claude Code.
- **Concurrency.** Codex runs at most four agents at once, the main one included. Spine dispatches
  stages one at a time, so this binds only a panel that fans out; dispatch such a panel in batches.
