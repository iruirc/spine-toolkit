---
name: workflow-feature
description: |
  FEATURE profile workflow: Research → Plan → Execute → Validation → Review → Done. Activated by spine-toolkit:orchestrator; not invoked by the user directly.
  Use when (en): orchestrator dispatches a task with [TASK_TYPE]=FEATURE
  Use when (ru): оркестратор диспетчеризует задачу с [TASK_TYPE]=FEATURE
stack_axes_envelope: { may: all, never: [] }
---

# Workflow Feature

This skill is **Method B** for the FEATURE profile: it runs the stages when the host has no Workflow tool. `workflows/profile-feature.js` is Method A and runs the same stages as code. The orchestrator picks between them (see `spine-toolkit:orchestrator` → **Dispatch**), and `scripts/lint-workflows.sh` fails if the two stage lists drift apart. Edit a stage here and the script needs the same edit.

The profile workflow for tasks with `[TASK_TYPE] = FEATURE`. Implements the sequence of stages; the result of each stage is an artifact file inside the task folder. The skill receives an already-resolved contract from the orchestrator and does not try to re-resolve any parameter on its own.

## Language Resolution

Before producing any user-facing string:

1. Read `CLAUDE-spine-toolkit.md` from the project root.
2. Find the `## Language` section.
3. Take the first non-empty line in that section, lowercase and trim it. That is `<lang>`.
4. If `<lang>` is `en` or `ru`, use it. Otherwise default to `en`.
5. Read this skill's `locales/<lang>.md`. Look up keys by H2 header.
6. If a key is missing, fall back to the same key in `locales/en.md`. If still missing, that's a bug — fail loudly with key name.

Caching: resolve `<lang>` once per skill invocation; do not re-read CLAUDE-spine-toolkit.md per string.

## 1. Input Contract

The skill is invoked by `spine-toolkit:orchestrator` via the `Skill` tool with structured `args` in `key=value` form, separated only by newlines.

The field structure is documented in `spine-toolkit:orchestrator` (section **Outbound Contract**). Workflow-feature accepts every field already filled — invariant.

If a required field arrives empty — workflow-feature does not try to recover. It returns `{status: error, reason: status_error_empty_required_field}` (the `reason` value is taken from the locale key in `locales/<lang>.md`) back to the orchestrator.

The fields that directly drive this workflow's behavior:
- `start_stage`, `end_stage`, `stage_scope` — determine which stages run.
- `start_phase` — entry point inside a stage (e.g. `Execute:phase=2.3`).
- `task_dir` — the resolved task folder; every artifact this profile writes lands there.
- `mode` — `manual` / `auto` (see sections 3 and 4).
- `stack` — passed to subagents as context.
- `lang` — project language for artifact prose + the final report; artifact structure (headings, field labels, status enums) stays EN. See `conventions/i18n.md` → "Artifact authoring rule". Passed through to every subagent.
- `need_test`, `need_review` — gate the inclusion of `[tester]` and `[reviewer]`.
- `archive_paths` — paths to backups already created (the orchestrator made them BEFORE the call; workflow-feature does not create them).

**Execution range.** Stages run in the order Research → Plan → Execute → Validation → Review → Done, starting at `start_stage` and continuing through `end_stage` inclusive. If `end_stage=null` — through the end of the profile. If `end_stage` is set but precedes `start_stage` in order, that is a contract error: return `{status: error, reason: "end_stage before start_stage"}`.

**Scope.** `stage_scope` controls execution width:
- `single` — only `start_stage` runs; afterwards the workflow returns `{status: ok, last_completed_stage: <start_stage>, next_recommended_action: stop}`. Used for `action=redo`.
- `forward` — `start_stage` plus every subsequent stage up to `end_stage` (or to the end of the profile). Used for `action=run`/`continue`/`restart`.
- `all` — equivalent to `forward` with `start_stage = first stage of the profile`. Used for `action=restart-full`.

## 2. Stages

A stage names its owner as a role in brackets — `[architect]`, `[developer]`. Which agent a role means arrives in the contract's `agents` map; dispatch that agent per `conventions/stage-dispatch.md` — stage work does not run in the main context, and a stage whose role resolved to `—` says so before it starts.

- **Research** — a panel: `[architect]` + `[security]` (via the Task tool, in parallel or sequentially as the orchestrator decides). Artifact: `Research.md` in the task folder. Goal: investigate the domain, surface risks, propose architectural options.

  The architect MUST apply the `feature-requirements` skill and then the `feature-landscape` skill, producing two H2 sections inside `Research.md`: `## Requirements` (Primary / Secondary / Designer questions / Backend questions / Known unknowns) and `## Landscape` (Entity graph / Layer map / Integration points / Work items / Implementation sequence). The `## Architectural Analysis` and other architect-output sections are appended after these two.

- **Plan** — `[architect]`. Artifact: `Plan.md` with **two layers of progress tracking**:
  1. **Top-level phase progress table** (see `State Detection` in orchestrator: statuses ✅/🔄/⬜/⏸/🚫/⊘) — one row per phase, coarse-grained completion.
  2. **Per-phase detail section** for each phase — actionable items rendered as **markdown checkboxes** `- [ ] <item>`. Granularity: one checkbox per file to edit, per acceptance criterion, per test to add, per verification step. Granular enough to be ticked individually as the Execute stage progresses. Static prose (rationale, decisions, design notes) stays as plain bullets — only **action items** become checkboxes.

  The plan decomposes the feature into concrete phases and steps. Per-phase action items are seeded from the work-items list in `Research.md ## Landscape ### Work items`.

  The architect MUST also add a `## Manual acceptance` section: one line per check this task's automation will not be able to make, stated as what must be true rather than what to press. Nothing qualifies — the single line `Fully automatable.` It is the input Validation turns into `ManualChecks.md`; the `manual-checks` skill holds both halves.

  The architect MUST apply the `feature-estimation` skill to produce an additional `## Estimation` section in `Plan.md`. Scale the depth to the feature's risk per the skill's *Estimation depth* table: the minimum viable estimate is feature type (one line) + baseline table + engineering range + confidence; PERT, scope-aware risk deltas, estimate maturity, estimation conditions, delivery-calendar, store buffer, known unknowns, and self-check are added only when their triggers fire. The estimation range is a hard-prerequisite for entering Execute. If `## Estimation` is missing/malformed, a triggered section is absent, `### Estimate maturity` is `Draft`, the maturity is `Conditional` and `### Estimation conditions` is missing or contains any `pending_user` row, or a Known Unknown trips the skill's load-bearing-unknown rule without a required spike/resolution, Plan stays open and the workflow returns `ask_user`. When the project is AI-assisted, `## Estimation` also carries the AI-assisted range; it is informational and does not change the gate — the gate evaluates the human estimate.

- **Execute** — `[developer]` + `[tester]` (if `need_test=true` in args). Implements the phases from `Plan.md` step by step, updating both progress layers as work proceeds. **MUST create one git commit per green phase** — autonomously, without a user prompt.

  Per-item flow inside a phase: complete one actionable item → tick its checkbox `- [ ]` → `- [x]` in the per-phase detail section of Plan.md. Per-phase flow: when all the phase's checkboxes are `- [x]` → build → run tests for the touched scope → flip the phase's row in the top-level progress table ⬜→✅ → `git add` the phase's files (including the Plan.md updates — both checkboxes and table) → `git commit`. Commit message format: **Conventional Commits** — `<type>(<scope>): <imperative subject>` followed by an optional body explaining WHY. For Execute-stage commits the type is usually `feat` (use `test` for a test-only phase, `chore` for build/config-only, `refactor` for an interim structural step). **NEVER include the task ID, step ID, or phase number** — provenance lives in `Plan.md`, the branch name, and the PR description. Full spec + anti-examples in `conventions/commit-messages.md`. Example:

  ```
  feat(domain): add ProjectListUseCase

  Encapsulates pagination + filtering that previously lived in the
  Presenter. Lets the ViewModel observe a single async stream instead
  of orchestrating three repositories.
  ```

  If `git log` shows the project uses a different convention for similar tasks, follow that convention instead.

  **A phase is not "done" (✅ in the top table) until ALL its granular checkboxes are `- [x]` AND the phase is committed.** Partial completion stays at 🔄 in the top table with the un-ticked checkboxes still `- [ ]`. Artifacts: source code in the project + tests + the resulting commit history.

  **Comment hygiene (hard rule, enforced by the `developer` agent):** NEVER embed task/phase/EPIC references in production code comments (`// EPIC X §Y Phase Z — …`, `// Task N phase M — …`, `// Bug123 fix`, `// Created for EPIC X`). Phase provenance lives in (a) the Plan.md per-phase checkbox + table row and (b) the per-phase git commit message — duplicating it inline rots and crowds out the evergreen WHY. See the `developer` agent's `## Comment Policy`.

  If `start_phase=<phase_id>` was passed in args — `[developer]` receives that phase as the start point in the Task-tool prompt. Already-completed phases (status `✅` in `Plan.md`) are skipped, not redone. The progress table is updated only for new / changed phases.

  When the stage's phases are done, apply `spine-toolkit:task-walkthrough` and write `Walkthrough.md` — the human-facing account of what actually landed, readable before anything has been validated or reviewed. Governed by `[WALKTHROUGH]` in `Task.md`, else `## Reporting` → `walkthrough` in `CLAUDE-spine-toolkit.md`, else the default this run's `scale` sets (§2a). Written by the same agent that writes `Done.md` — `[architect]`.

- **Validation** — `[validator]`. Artifact: `Validation.md`, **first line is required** to be `[VALIDATION_STATUS] = PASSED | FAILED | FLAKY` (the shared contract between the `validator`, every `workflow-*`, and the orchestrator; analogous to `[REVIEW_STATUS]`). For the FEATURE profile, the validator runs a build and a full test run mandatorily, through the platform's own build and test tooling, and drives a running instance of the app mandatorily when there is a UI layer (views, screens, navigation); driving is skipped for purely domain/infrastructure features. Detailed per-profile behavior (mandatory vs. optional driving steps, log capture, return-digest format) lives with the `validator` agent. When `drive_app` resolves to `off` (`Task.md [DRIVE_APP]` first, then `CLAUDE-spine-toolkit.md ## Validation`), or the platform has no tooling to drive a running instance and its validator declares the deviation, no driving happens at all: the validator writes the UI cases a human must run into a separate `ManualChecks.md`, marks the matching `OpsChecklist.md` items Pending, and returns the case titles in `manual_checks` — surface that list with the stage report. The `manual_checks` key of the same two sources decides when that artifact appears: `auto` only for deferred checks, `always` on every UI-bearing run, including one the validator drove itself.

  In addition to `Validation.md`, the validator MUST produce a separate `OpsChecklist.md` artifact in the task folder by applying the `ops-checklist` skill. Each checklist item is marked **Applicable** (with verification evidence: file path, test name, commit ref), **N/A** (with reason), or **Pending**. A single Pending item is NOT itself a FAILED verdict — Pending items are surfaced to the Review stage, which decides whether they block APPROVED. The `manual-checks` skill governs that artifact's shape — its structure, the required fields of a case, and the two rules that make a case executable — and reads `Plan.md ## Manual acceptance` as its input.

- **Review** — `[reviewer]` (if `need_review=true` in args). Artifact: `Review.md`, **first line is required** to be `[REVIEW_STATUS] = APPROVED | CHANGES_REQUESTED | DISCUSSION` (this field is the shared contract between workflow-* and the orchestrator; it is also used by `spine-toolkit:workflow-review` for auto-move into DONE/). On a redo after `CHANGES_REQUESTED`, the reviewer finds its own prior `Review.md` in the task folder and narrows scope to the commits landed since its `[REVIEWED_COMMIT]` line instead of re-reviewing the whole task from scratch — see the `reviewer` agent → "1. Identify Scope".

  The reviewer cross-checks `OpsChecklist.md` from the Validation stage: every item marked **Applicable** must have implementation evidence visible in the diff or in test results. Applicable items without evidence are findings (severity per the `reviewer` agent) and typically yield `CHANGES_REQUESTED`. Pending items in `OpsChecklist.md` are surfaced as a `## Outstanding ops items` section in `Review.md` for explicit user-side accept/defer.

- **Done** — final report `Done.md`: what was done, which artifacts were produced, validation status (build/test result), a mandatory `## Estimate retrospective` section when `Plan.md ## Estimation` exists, and objections (if the user insisted on a contested decision). The retrospective MUST capture actual effort via the hybrid model defined in `feature-estimation` (`## Estimate retrospective`): record the auto git proxy (commit-span of the task's phase commits + phase/rework count, labelled `proxy` — never presented as human-days) **always**, plus the user-provided human effort when offered, and use `human ?? proxy` for the in-range verdict; only when neither is available write `unknown` with the missing signal named. In AI-assisted mode, break actual down per leverage class so the calibration loop can narrow the divisors. The same section appends the feature's data point to the calibration log (`feature-estimation` Calibration over time).

  Refresh `Walkthrough.md` here when the Execute stage did not run in this invocation — an entry at Review or Done means commits landed after it was written. `task-walkthrough` owns the refresh rules; its `[COVERS]` line decides whether there is anything to do.

## 2a. Scale

`scale` arrives in the contract as `lite` or `full`, never empty. `full` runs the stages above
exactly as written. The axis itself — the three levers, the floor, the ratchet and its four
criteria — is `conventions/task-scale.md`; what follows is only what is specific to FEATURE.

At `lite`:

- **Research does not get its own stage.** No agent is dispatched for it and no `Research.md` is
  written. `Plan.md` opens with a `## Research` section carrying what that stage would have found:
  the Primary and Secondary requirements, the work-item list, and the integration points a phase
  will cross. The investigation still happens — it stops being a separate agent and a separate file
  that every later stage re-reads.
- **`## Estimation` is not produced and the estimation gate does not run.** An engineering-day range
  nobody consumes is the paperwork this axis exists to stop; `Done.md`'s `## Estimate retrospective`
  is already conditional on the section existing, so it drops out with it.
- **`OpsChecklist.md` is not written**, and Review has no ops cross-check to perform.
- **`Walkthrough.md` is not written** unless `[WALKTHROUGH]` in `Task.md` says so.
- Every artifact the table in `scripts/lint-artifact-budget.sh` names carries a line ceiling, and
  `Validation.md` links to build and test output rather than pasting it. Read the ceilings from
  that table, pass each one to the agent writing that artifact, and expect the orchestrator to
  measure against the same table when the stage returns.

Unchanged at `lite`: one commit per green phase, tests run before each, `Validation` with its own
agent, and `Review` with an independent one.

**The ratchet.** Both of its points collapse into the planner's first act here, because `lite`
folded Research into Plan and nothing before Plan has measured the perimeter. The `[architect]`
raises the scale by returning `scale_escalation` and then writing `Plan.md` at full depth — with
`## Estimation` and its gate — in the same pass.

## 3. Manual mode

After each completed stage the orchestrator asks the user via the structured question mechanism using the `stage_done_prompt` key from `locales/<lang>.md`, with placeholder `{stage}`.

Workflow-feature **does NOT ask the user itself** — it returns control to the orchestrator after a stage completes (see section 5, Output Contract) with `next_recommended_action`. The decision to pause, continue, or capture discussions in `Questions.md` is the orchestrator's responsibility.

If the active host has no structured question tool, the orchestrator uses a textual fallback (numbered options + reply parsing). That is the orchestrator's responsibility, not workflow-feature's.

## 4. Auto mode

No pauses between stages. Workflow-feature runs the stages sequentially within `stage_scope` and returns the final result to the orchestrator in a single output.

**Per-phase commits inside the Execute stage are autonomous** — created without a user prompt, in both manual and auto modes. The only commit that always requires confirmation regardless of mode is a flow-level wrap commit (squash, merge, push) when the orchestrator initiates one. That confirmation is the orchestrator's responsibility, not workflow-feature's.

## 5. Output Contract

After each stage (in `manual` mode) or after a full pass (in `auto` mode), workflow-feature returns a JSON-like structure to the orchestrator:

```
{
  status: ok | error | cancelled | interrupted,
  last_completed_stage: Research | Plan | Execute | Validation | Review | Done,
  artifact_path: <path to the final artifact, e.g. Tasks/ACTIVE/001-feature/Done.md>,
  next_recommended_action: continue | stop | ask_user,
  notes: <free-form text, optional>
}
```

Field semantics:
- `status=ok` — the stage finished correctly.
- `status=error` — an error occurred (including reasons such as the locale key `status_error_empty_required_field`, an invalid contract, or a fatal subagent failure).
- `status=cancelled` — the user explicitly declined to continue (the orchestrator forwarded a `No` from its AUQ; rendered to the user via locale key `status_cancelled_user_no`). A normal outcome, not an error.
- `status=interrupted` — execution was interrupted by a technical fault or external signal (not by user decision): subagent disconnect, timeout, tool unavailable. Requires diagnostics on the orchestrator side.
- `last_completed_stage` — the last stage that actually finished (not the one execution stopped on with an error).
- `artifact_path` — path to the key artifact of the last stage (`Research.md`, `Plan.md`, `Validation.md`, `Review.md`, `Done.md`).
- `next_recommended_action=continue` — the next stage may start immediately; `stop` — natural finish (Done) or a fatal error; `ask_user` — confirmation is needed before continuing (e.g. after a Validation with `[VALIDATION_STATUS] = FAILED | FLAKY`, or after a Review with `[REVIEW_STATUS] = CHANGES_REQUESTED`).
- `notes` — short free-form description (e.g. the example in locale key `notes_build_failed_example`).

Based on this, the orchestrator decides: continue, abort, or ask the user.

## 6. What workflow-feature does NOT do

- Does NOT route — profile selection happens in the orchestrator before the call.
- Does NOT read `Task.md` to determine stack/mode — everything arrives in `args`.
- Does NOT trigger `task-new` or `task-move` — that is not its scope.
- Does NOT decide to skip stages — the orchestrator already passed `start_stage`, `end_stage`, `stage_scope`.
- Does NOT create backups in `_archive/` — the orchestrator did so before handing off control; the paths are already in `archive_paths`.
- Does NOT ask the user — the orchestrator does that between stages in `manual` mode.
- Does NOT **ask** the user before per-phase commits — workflow-feature creates them autonomously after each green phase, with no user prompt. The orchestrator handles user-facing commit confirmation only for any flow-level wrap commit it initiates (squash, merge, push). **"Does NOT confirm with user" means "does not interrupt to ask", NOT "does not commit".** Failing to commit per phase loses incremental progress on interrupt and forces a re-do of the whole Execute stage.
