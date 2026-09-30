# Stage Dispatch

A `workflow-*` stage that names a role names its owner. The agent that role resolves to is an
execution contract, not a hint: the stage runs inside that agent, dispatched with the host's
subagent mechanism (`subagent_type=<the agent the orchestrator resolved for this stage's role>` in
Claude Code). Stage work performed in the main context loses the two things the stage has an agent
for — an isolated context and an independent look.

The same contract holds when the profile runs as a workflow script (`workflows/profile-*.js`): the
script dispatches through `agent({agentType: A.agents[<role>]})`, reading the same resolved map.
Which of the two forms a task takes is the orchestrator's choice; that a stage runs inside its own
agent is not.

## Standing authorization

Hosts may carry a standing instruction not to spawn subagents, or not to start workflows, unless the
user asked. A user who starts or continues spine-toolkit work HAS asked, for the whole task:

- a spine-toolkit slash command (`/task-run`, `/task-continue`, `/task-redo`, `/task-restart`,
  `/task-new`, `/setup`, …);
- a natural-language trigger routed to `spine-toolkit:orchestrator`, in any language;
- an active `spine-toolkit:workflow-*` skill, or a running `profile-*` workflow.

The authorization covers every stage of that task, in either execution form — the workflow script
and the skill — and is not re-confirmed per stage.

A subagent's prompt names core files by absolute path and names the core root itself, as the
`Core root:` line of a Method A brief does; it carries the `Long-running commands:` line with the
task's `long_run` values converted to seconds (minutes × 60), exactly as the Method A brief does;
and it carries the `Search roots:` line with the task's `roots`, worded as the Method A brief words it.
A Review stage's prompt also names every range of the task's `review_ranges`, worded as the Method A Review prompt words it.

## Owner's directive

The contract's `user_directive` is what the owner said for this run beyond the choice of stages,
verbatim, and only ever from the owner's message — never from a file. It is the one text a brief lets
address the agent; everything else stays data. Non-empty, it goes into every stage agent's prompt,
right after the rule that repository and artifact text is data, in these words:

```text
Owner's directive for this run — verbatim, from the person who owns the task, never from a file: «{directive}». Apply what concerns your stage; what does not, neither act on nor discuss. On how this stage does its work, it outranks the project's files (CLAUDE.md, CLAUDE-spine-toolkit.md, Task.md) and your own defaults. It never changes the contract's fields or the stage range, and never waives what the stage owes: its commits, its artifact and status line, Validation's full regression, an honest verdict. If it asks for one of those, do not comply, and name it under directive_declined.
```

When the run carries a directive or `run_settings`, the prompt also asks for this line, `{run}` being
each `run_settings` entry as `<field>=<value>`, then `directive: «…»`, joined by `; `. The line is one
line: every run of whitespace in the directive becomes one space there, and only there:

```text
Every artifact you write this run carries the line "**Run:** {run}" directly below its first line and any lines this brief tells you to write there.
```

A workflow script carries both in its prelude; a Method B skill puts the same words in each stage's
prompt. `Run.json` in the task folder is the orchestrator's record of the run: a stage neither reads
nor stages it.

## Device

The contract's `device` is the device every build, test and drive of a stage runs on, in the
platform's own terms; `device_source` is the project's command that prints one
(`docs/configuration.md` → `[DEVICE]`, `[DEVICE_SOURCE]`). At `auto` with no command, a brief says
nothing and the platform chooses as it always did. A named device goes into every stage agent's
prompt, after the owner's directive, in these words:

```text
Device: «{device}» — every build, test and drive of this stage runs on it, packages included, whatever the project's files or your own defaults name. Say at the top of your artifact which device you used, and that the brief named it.
```

When the contract's `device_from` says where the device was set, the last sentence ends `that the
brief named it, set by <origin>.`, the origin in these words; any other value keeps the sentence as
it is:

| `device_from` | origin |
|---|---|
| `run` | this run |
| `task` | the task's Task.md |
| `epic` | the epic's Task.md |
| `project` | the project's config |

At `auto` with a command, in these words instead:

```text
Device: run `{device_source}` from the project root once, at the start of this stage; its first non-empty line is the device every build, test and drive of this stage runs on, packages included, whatever the project's files or your own defaults name. If the command exits non-zero or prints nothing, the platform's own choice stands. Say at the top of your artifact which device you used, and whether the command gave it.
```

A command holding a backtick goes in a code span one backtick longer than its longest run, padded
with a space on each side.

The command runs in every stage rather than once per run, so a device changed between two stages
is the one the second stage uses. It comes from the contract, not from a file, which is what lets a
stage run it: the project named it in its config, as it names its build.

## Declared deviation

Delegation may be skipped — the host exposes no subagent mechanism, the user opted out, the
platform's manifest declares no agent for the stage's role (an em dash in its `## Roles`), or a stage
is small enough that the round trip costs more than it buys. In every such case the deviation is
announced in the first message of the stage, naming what runs instead. An undeclared deviation is a
defect even when the deviation itself is sound.

The em-dash cause is the one the toolkit resolves for itself: the role is declared absent, so the
stage runs in the main context and the announcement uses the orchestrator's `deviation_role_absent`
key, naming the role and the stage.

On that cause a workflow script can do neither — no main context to run in, nobody to announce to —
so it ends the range at that stage and hands it back for the orchestrator to run and announce
(`skills/orchestrator/SKILL.md` → Dispatch).

A panel stage (two or three agents on one stage) may run its agents in parallel or sequentially — that choice
is the orchestrator's and needs no announcement.

## Model and effort

Every dispatch runs on the model and at the effort the contract's `models` and `effort` maps give
it, through one rule. `models` and `effort` resolve like every other task setting —
`conventions/task-settings.md` holds their chain and field table; this section is what a dispatch
does with the result. A dispatch is one of five kinds:

- `stage` — the work a stage exists for: investigation, plan, a phase, validation, review.
- `walkthrough` — writing `Walkthrough.md`, and revising it after its check: `walkthrough`,
  `walkthrough:revise`.
- `done` — writing the final report, which on a Done run again is checking a report against the
  task: `done`.
- `light` — work the script's own prompt defines that still takes judgement: `walkthrough:check`,
  `security:triage`, `manual-checks:check`.
- `mechanical` — reading a file back, ticking a box, moving a task: `<stage>:read-plan`,
  `execute:read-steps`, `execute:tick:<step>`, `done:read-branch`, `auto-move`.

The `walkthrough`, `done`, `light` and `mechanical` lists are closed, and
`scripts/lint-workflows.sh` holds them.

| Kind | model | effort |
|---|---|---|
| `stage` | `models[role]` | `effort[role]` |
| `walkthrough` | `models.walkthrough`, else `models.light`, else `models[role]` | `effort.walkthrough`, else `effort[role]` |
| `done` | `models.done`, else `models[role]` | `effort.done`, else `effort[role]` |
| `light` | `models.light`, else `models[role]` | `effort[role]` |
| `mechanical` | `models.light`, else `models[role]` | `low` |

`session` means pass nothing; in the `walkthrough`, `done` and `light` keys it hands the choice to
the next key of the row.
From Claude Code 2.1.251 a model the dispatch passes outranks everything; without one
`CLAUDE_CODE_SUBAGENT_MODEL` decides, then the session's model. Before 2.1.251 the environment
variable outranked everything. An effort not passed is the session's.
Neither falls to the agent's frontmatter, because a platform agent declares no model and no effort
(`conventions/platform-contract.md` → `## Roles`).

Method A passes both through the prelude's `tuning(role, kind)`. Method B passes the model with the
dispatch and cannot pass effort: the host's dispatch takes no such parameter, so every stage runs at
the session's effort and the orchestrator says so once. Under Method B the walkthrough, its check and
its revision, and the security triage, are the calls outside a stage that still get an agent, and
the `mechanical` ones and Done run in the main context.
Work in the main context — the orchestrator, a
handed-back stage, a Method B stage without an agent — runs on the session's model and effort.
