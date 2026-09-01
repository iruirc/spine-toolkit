# spine-toolkit

A task lifecycle orchestrator for Claude Code: stages, the artifacts that travel between them, and
the rules for moving from one to the next. It knows nothing about any programming language or
framework — stack knowledge arrives from a **platform plugin** it invokes across the plugin
boundary.

Install it alone to see the process on its own — commands, artifacts, dispatch — with no ecosystem
baked in. Configuring an actual project still needs at least one platform plugin installed alongside
it; `/setup` stops and says so if none is found.

## Install

```
/plugin marketplace add iruirc/claude-marketplace
/plugin install spine-toolkit
```

Then, in a project:

```
/setup
```

`setup` writes `CLAUDE-spine-toolkit.md` in the project root, inserts an
`@./CLAUDE-spine-toolkit.md` import into your `CLAUDE.md`, and offers to create `Tasks/` and
`Docs/` — it asks before creating either, and never touches an existing one. It asks which
platform plugin serves this project — the candidates are the installed plugins that expose a
`manifest` skill, and with one installed it asks you to confirm that one — and writes the answer
into `## Platform`. Nothing is inferred from the repository, and no block is left for you to fill
in by hand.

From there, tasks are managed with `/spine-toolkit:task-new`, `:task-run`, `:task-continue`,
`:task-redo`, `:task-restart`, `:task-move`, `:task-status`, or the equivalent natural-language
phrases ("create task: …", "run 001", "status 001").

Write the `spine-toolkit:` prefix and you are always right. The short `/task-new`, `/task-move`,
`/task-status`, `/setup`, `/lang` and `/agent-status` also work, because each has a skill of the
same name to catch them;
`/task-run`, `/task-continue`, `/task-redo` and `/task-restart` are commands with no matching skill,
and bare they resolve to nothing — verified in both an interactive and a headless session.

## How a task runs

A task lives in `Tasks/<STATUS>/<id>-<slug>/`. Its `Task.md` names a `[TASK_TYPE]`, which selects one
of seven profiles:

| Profile | Stages |
|---|---|
| FEATURE | Research → Plan → Execute → Validation → Review → Done |
| BUG | Reproduce → Diagnose → Plan → Fix → Validation → Review → Done |
| REFACTOR | Analyze → Plan → Refactor → Validation → Review → Done |
| TEST | Analyze → Plan → Write → Validation → Review → Done |
| EPIC | Research → Plan → Execute → Done — Execute is one nested profile run per `.step/`, and each step carries its own Validation and Review |
| RESEARCH | Research → Review → Done |
| REVIEW | Review — single stage, then an auto-move driven by `[REVIEW_STATUS]` |

`skills/orchestrator/SKILL.md` resolves everything a profile needs — profile, mode, progress
verbosity, per-axis stack, start stage, and the role→agent map — then hands a filled contract to the
profile. Each profile ships twice: as a `workflow-*` skill (a procedure a model follows) and as a
script under `workflows/` (the same stages as code the runtime executes).
`scripts/lint-workflows.sh` fails the build if the two drift apart.

Every stage names its owner as a **role**, never as an agent: `[reviewer]`, `[developer]`,
`[architect]`. Which agent a role means is resolved once per run, from the platform's manifest.
The dispatch rules are in `conventions/stage-dispatch.md`.

## The platform contract

spine-toolkit names nine roles and one stack axis (`ecosystem`). Everything else — which agent owns a
role, which axes exist, how to read them off a repository, which skills cover which topic — is
declared by the platform plugin, in a single skill the orchestrator **invokes**:

```
<plugin>/skills/manifest/SKILL.md      →  invoked as  <plugin>:manifest
```

That skill is data, not instructions: five H2 tables (`## Roles`, `## Axes`, `## Heuristics`,
`## Topics`, `## Entrypoints`) and no procedure. Invoking a skill is the only channel between the two
plugins — core never reads the host's plugin cache from disk.

Two things to read, in this order:

- **`conventions/platform-contract.md`** — the contract: every table, every cell, what core does with
  it, and what a platform is free to choose.
- **`tests/fixtures/fixture-platform/`** — a complete, minimal platform plugin. Core's own test suite
  binds against it, so it cannot go stale without the build going red. Copy it and fill it in.

Check your manifest with:

```
scripts/lint-manifest.sh <path-to-your-plugin>
```

— pointed at your plugin's checkout, not its installed copy.

A platform plugin declares `"dependencies": ["spine-toolkit"]` in its `plugin.json` and imports
nothing from here: the two plugins share no code. The lints it needs travel as **adapted forks** —
each recording the core file it came from and that file's sha256, so drift is visible rather than
silent. They are not copies to be restored to match core.

## Project configuration

`CLAUDE-spine-toolkit.md` is toolkit-owned; `setup` writes it and `/lang` updates one block of
it. Your own project instructions stay in `CLAUDE.md`, which the toolkit only ever touches to insert
the import line. The blocks the toolkit reads:

`## Language`, `## Platform`, `## Agents` (per-role overrides of the manifest), `## Stack`,
`## Mode`, `## Progress`, `## Validation`, `## Reporting`, `## Modules` (per-module stack
overrides), `## EstimationDeltas`, `## DeliveryMode`, `## AILeverage`, `## Paths`.

The template writes three more — `## Persona`, `## Rules` and `## Orchestration`. Those are for the
agents reading the file as context, not blocks the toolkit parses.

The template is `templates/claude-toolkit-md/en.md`.

## Internationalization

English is the source of truth. User-facing strings live in `skills/<name>/locales/en.md` with a
key-for-key `ru.md` beside it, and are referenced from skill bodies by key, never inlined. The active language is `## Language` in the
project config; `/lang en|ru` switches it. Skill triggers are bilingual regardless of the
setting — only the response language changes. Convention: `conventions/i18n.md`.

## Development

```
bats tests/foundation/lib
scripts/lint-i18n.sh
scripts/lint-locales.sh
scripts/lint-workflows.sh
scripts/lint-manifest.sh tests/fixtures/fixture-platform
```
