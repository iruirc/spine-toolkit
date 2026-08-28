# CLAUDE-spine-toolkit.md — Toolkit Configuration

> Toolkit-owned configuration. Created and updated by `spine-toolkit:setup`.
> **Do not edit by hand unless you know what you're doing** — running `/setup` again may overwrite your changes (after backup).
> User-owned project instructions live in `CLAUDE.md`. This file is auto-imported into Claude's context via `@./CLAUDE-spine-toolkit.md`.
> Task-orchestration logic is in the `spine-toolkit:*` skills (see "Orchestration" below).

## Language

en

## Persona

- Communication language: <Communication Language>
- **I have the right to disagree** with the user's decisions. If a decision leads to a hack, a security hole, or technical debt — I MUST object and propose an alternative.
- **Quality and security > speed.** Do not accept "we'll fix it later", "good enough for MVP", "this is temporary".
- **Long-term value > quick wins.** Pick solutions that scale and remain maintainable.
- If the user insists on a hacky solution, clearly outline the risks and record them in `Done.md → Objections`.

## Rules

### Comments

- **Default to writing no comments.** Code with descriptive names says WHAT. Only add a comment when the WHY is non-obvious: hidden constraint, subtle invariant, workaround for a specific bug, behavior that would surprise a reader.
- **Comments must be evergreen** — encode an invariant that will still be true in two years.
- **NEVER reference the current task, phase, EPIC, ticket, fix, PR, or caller** in production code comments. Forbidden examples: `// EPIC 145 §1.6 Phase 5 — …`, `// Task 042 phase 2`, `// Bug123 fix`, `// Used by Y flow`, `// §1.7 follow-up will replace this`, `// Was X before refactor`. Provenance lives in `git log` / commit message / PR description / `Tasks/` — duplicating it in code rots and crowds out the WHY.
- **WHAT-comments are forbidden** (e.g. `// increment counter` over `counter += 1`). Decorative preludes, history-only notes, and forward-promise comments are also forbidden.
- **File headers** carry an evergreen description of the file's role only — no `// Created for EPIC X / Phase Y` lines.
- The same rule applies to test code: no phase/EPIC refs in test comments OR in `XCTAssert*` / `XCTFail` / `XCTSkip` message strings (those are read in failure output and must be self-explanatory).

### Commits & provenance

- Commit message + PR description carry the WHY of the change.
- `git log` / `git blame` / `Tasks/<status>/<task_id>/` folder carry the timeline.
- Production code carries the *current* invariants and constraints — not the journey that led to them.

## Platform

<platform-plugin>

(the platform plugin that serves this project. spine-toolkit invokes it as `<name>:manifest` to
learn which agent owns each role, which stack axes exist and how to read them off the repository.
Exactly one name, on its own line — nothing is inferred from the repository.)

## Agents

(optional: per-role overrides of the platform manifest's `## Roles`, same row grammar —
`<role> = <plugin>:<agent>`, or `<role>[<axis>=<value>] = <plugin>:<agent>` to override only one
axis value. A role named here replaces the manifest's rows for that role entirely. This block
normally holds no row at all: the platform's manifest is the source of truth, and an override is
the exception. Placeholders in angle brackets are not rows — only a line that names a real role is.)

## Stack

<one `- <Axis>: <value>` line per axis the platform's manifest declares under `## Axes`>

(axis names and values are proper nouns from that catalog — never translated, since they are matched
back against it.)

## Mode

manual

## Progress

normal

(how much the orchestrator narrates a profile run: `quiet` — the final report only;
`normal` — the stage-to-agent plan once, then a report after every stage; `live` — everything
from `normal` plus each stage's token cost, a totals line when the run finishes, and the
command for a live agent panel you can run in a second terminal pane.
This setting governs reporting only — the between-stage confirmations of `manual` mode are
unaffected by it.)

## Validation

mobile_mcp: auto
manual_checks: auto

(`mobile_mcp` — whether the Validation stage may drive the running app through mobile MCP: `auto` — the profile
decides (FEATURE: when the feature has a UI layer; BUG: always, to replay the reproduction;
REFACTOR: when UI code was touched; TEST: only for UI tests); `off` — never, because this project
has no mobile MCP configured or no simulator to drive.
`off` does not delete the check: the validator writes the cases a human has to run into a separate
`ManualChecks.md` in the task folder and marks the matching `OpsChecklist.md` items Pending.
For BUG the deferred check is the reproduction replay itself.
`manual_checks` — when the validator writes `ManualChecks.md`, the hand-run script for a human:
`auto` — only for checks it was told not to run itself; `always` — every time, so a UI-bearing task
ships a manual pass even when mobile MCP drove the app and covered the happy path.

A single task overrides both with `[MOBILE_MCP] = [auto|off]` and `[MANUAL_CHECKS] = [auto|always]`
in its `Task.md`.)

## Reporting

walkthrough: on

(whether a task writes `Walkthrough.md` — the human-facing account of what actually landed:
summary, plan-vs-outcome divergences with their trigger, a commit-by-commit log, diagrams where
they help, follow-ups. Written at the end of the implementing stage, so it is readable before
Validation and Review, and refreshed afterwards if later commits moved past it.
`on` — write it; `off` — never. Not applicable to RESEARCH and REVIEW, whose deliverable is the
artifact itself. A single task overrides with `[WALKTHROUGH] = [on|off]` in its `Task.md`.)

## Modules

(optional: list of modules with a per-module stack overriding `## Stack` for the paths it names, e.g.: "- Core: /Packages/Core — <axis>: <value>, <axis>: <value>")

## EstimationDeltas

(optional: project-specific overrides for `feature-estimation`; leave empty until the calibration log `Tasks/_calibration/estimation-log.md` shows repeatable data across ≥3–5 finished features. Updates are proposed from that log, never written silently.)

## DeliveryMode

manual

(optional: keep `manual` by default; change this value only when the project should produce the additional estimation range documented by `feature-estimation`)

## AILeverage

(optional: project-specific overrides for AI leverage classes used by `feature-estimation`; leave empty until the calibration log `Tasks/_calibration/estimation-log.md` shows repeatable per-class observed divisors across ≥3–5 finished AI-assisted features. Updates are proposed from that log, never written silently.)

## Paths

(optional: "- Sources: /Sources", "- Tests: /Tests")

## Orchestration

The full skill map and dependencies between skill groups — see the spine-toolkit README ("Skills as a system").

Task routing, profile, and stage logic lives in skills:

- `spine-toolkit:orchestrator` — picks the profile by `TASK_TYPE`, determines the start point, dispatches stages
- `spine-toolkit:workflow-feature|bug|refactor|test|review|research|epic` — profile procedures
- `spine-toolkit:task-new|task-move|task-status` — task management
- `spine-toolkit:setup` — configures spine-toolkit in an existing project (creates `CLAUDE-spine-toolkit.md` from template, inserts the `@./CLAUDE-spine-toolkit.md` import into `CLAUDE.md`, creates `Tasks/`)
- `spine-toolkit:swift-lang` — switches the project's prompt language

Each profile also has a workflow script (`workflows/profile-*.js`) running the same stages as code; the orchestrator uses it where the host has the `Workflow` tool and falls back to the skill where it does not. Two consequences worth knowing: agents inside a workflow run in `acceptEdits`, so their file edits apply without a prompt whatever permission mode the session is in, and on the Pro plan workflows stay off until enabled in `/config`.

Slash commands:
- task management: `/task-new`, `/task-run`, `/task-continue`, `/task-redo`, `/task-restart`, `/task-move`, `/task-status`
- toolkit setup: `/setup` (attach the toolkit to an existing project); a project from scratch is the platform plugin's own command
- language: `/swift-lang <code>` (switch between `en` and `ru`)

NL phrases continue to work: `create task: ...`, `run 001`, `continue 001`, `move 001 to DONE`, `status 001`, `redo plan for 001`, `set up spine-toolkit`, etc. — the matching skill activates via triggers in its `description`.
