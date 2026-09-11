---
name: workflow-refactor
description: |
  REFACTOR profile workflow: Analyze → Plan → Refactor → Validation → Review → Done. Activated by spine-toolkit:orchestrator; not invoked by the user directly.
  Use when (en): orchestrator dispatches a task with [TASK_TYPE]=REFACTOR
  Use when (ru): оркестратор диспетчеризует задачу с [TASK_TYPE]=REFACTOR
stack_axes_envelope: { may: all, never: [] }
---

# Workflow Refactor

This skill is **Method B** for the REFACTOR profile: it runs the stages when the host has no Workflow tool. `workflows/profile-refactor.js` is Method A and runs the same stages as code. The orchestrator picks between them (see `spine-toolkit:orchestrator` → **Dispatch**), and `scripts/lint-workflows.sh` fails if the two stage lists drift apart. Edit a stage here and the script needs the same edit.

The profile workflow for tasks with `[TASK_TYPE] = REFACTOR`. Implements the sequence of stages; the result of each stage is an artifact file inside the task folder. The skill receives an already-resolved contract from the orchestrator and does not try to re-resolve any parameter on its own.

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

The field structure is documented in `spine-toolkit:orchestrator` (section **Outbound Contract**). Workflow-refactor accepts every field already filled — invariant.

If a required field arrives empty — workflow-refactor does not try to recover. It returns `{status: error, reason: status_error_empty_required_field}` (the `reason` value is taken from the locale key in `locales/<lang>.md`) back to the orchestrator.

The fields that directly drive this workflow's behavior:
- `start_stage`, `end_stage`, `stage_scope` — determine which stages run.
- `start_phase` — entry point inside a stage (e.g. `Refactor:phase=2.3`).
- `task_dir` — the resolved task folder; every artifact this profile writes lands there.
- `mode` — `manual` / `auto` (see sections 3 and 4).
- `stack` — passed to subagents as context.
- `lang` — project language for artifact prose + the final report; artifact structure (headings, field labels, status enums) stays EN. See `conventions/i18n.md` → "Artifact authoring rule". Passed through to every subagent.
- `need_test`, `need_review` — gate the inclusion of `[tester]` and `[reviewer]`.
- `archive_paths` — paths to backups already created (the orchestrator made them BEFORE the call; workflow-refactor does not create them).

**Execution range.** Stages run in the order Analyze → Plan → Refactor → Validation → Review → Done, starting at `start_stage` and continuing through `end_stage` inclusive. If `end_stage=null` — through the end of the profile. If `end_stage` is set but precedes `start_stage` in order, that is a contract error: return `{status: error, reason: "end_stage before start_stage"}`.

**Scope.** `stage_scope` controls execution width:
- `single` — only `start_stage` runs; afterwards the workflow returns `{status: ok, last_completed_stage: <start_stage>, next_recommended_action: stop}`. Used for `action=redo`.
- `forward` — `start_stage` plus every subsequent stage up to `end_stage` (or to the end of the profile). Used for `action=run`/`continue`/`restart`.
- `all` — equivalent to `forward` with `start_stage = first stage of the profile`. Used for `action=restart-full`.

## 2. Stages

A stage names its owner as a role in brackets — `[architect]`, `[developer]`. Which agent a role means arrives in the contract's `agents` map; dispatch that agent per `conventions/stage-dispatch.md` — stage work does not run in the main context, and a stage whose role resolved to `—` says so before it starts.

- **Analyze** — `[architect]`. Artifact: `Research.md` describing the current state (what is bad, why, what risks the refactor carries), a map of affected components, and the target state. Goal: refactor **without changing external behavior** — only structure, readability, maintainability, type/module boundaries, naming, and dependency isolation change. The public API/behavior contract is preserved as an invariant.

  The architect MUST apply the `feature-landscape` skill **twice**: once to draw the **current** entity graph + layer map + integration points (the as-is landscape), and once to draw the **target** landscape after refactor. `Research.md` gets two sections: `## Landscape (current)` and `## Landscape (target)`. The diff between them IS the refactor scope; per-phase work items in `Plan.md` are derived from this diff.

- **Plan** — `[architect]`. Artifact: `Plan.md` with **two layers of progress tracking**:
  1. **Top-level phase progress table** (see `State Detection` in orchestrator: statuses ✅/🔄/⬜/⏸/🚫/⊘) — one row per phase, captures coarse-grained completion.
  2. **Per-phase detail section** for each phase — actionable items rendered as **markdown checkboxes** `- [ ] <item>`. Granularity: one checkbox per file to edit, per acceptance criterion, per test to add, per verification command to run. The checkboxes MUST be granular enough that they can be ticked individually as work progresses inside the phase (the Refactor stage will tick them — see Refactor below). Static prose inside per-phase sections (rationale, rollback markers, decisions) stays as plain bullets/text — only **action items** become checkboxes.

  Each phase MUST be **independently buildable, test-passing, AND physically committed by the Refactor stage** — that is the requirement of incremental refactoring. "Commit-ready" is NOT enough — an interrupt or rollback destroys all uncommitted work. The Refactor stage produces one git commit per green phase (see Refactor below).

  Every phase's detail section opens with a `**Verification:**` line and one checkbox per check it names; the rung comes from the `phase-verification` skill, which holds the rungs, the questions that pick one, and when the line says `full`. The full regression belongs to Validation — a phase checks what it can break, and a phase repeating the whole suite at `proportional` is a defect of the plan.

  The architect MUST also add a `## Manual acceptance` section: one line per check this task's automation will not be able to make, stated as what must be true rather than what to press. Nothing qualifies — the single line `Fully automatable.` It is the input Validation turns into `ManualChecks.md`; the `manual-checks` skill holds both halves.

- **Refactor** — `[refactorer]`, or `[tester]` for a phase that only adds or changes tests. Applies the refactor phase by phase from `Plan.md`, updating both progress layers as work proceeds. **MUST create one git commit per green phase** — autonomously, without a user prompt.

  Per-item flow inside a phase: complete one actionable item → tick its checkbox `- [ ]` → `- [x]` in the per-phase detail section of Plan.md. Per-phase flow: when all the phase's checkboxes are `- [x]` → build → run the checks the phase's `**Verification:**` line names — a missing line is written, and a line the diff outgrew is raised, by the `phase-verification` skill first; a rung is never lowered → flip the phase's row in the top-level progress table ⬜→✅ → `git add` the phase's files (including the Plan.md updates — both checkboxes and table) → `git commit`. Commit message format: **Conventional Commits** — `<type>(<scope>): <imperative subject>` followed by an optional body explaining WHY. For Refactor-stage commits the type is usually `refactor` (use `test` for a test-only phase, `chore` for build/config-only). **NEVER include the task ID, step ID, or phase number** — provenance lives in `Plan.md`, the branch name, and the PR description. Full spec + anti-examples in `conventions/commit-messages.md`. Example:

  ```
  refactor(MediaPlayer): migrate manual observers to scoped subscriptions

  Hand-paired register/unregister calls are fragile — unregistering twice
  faults and missing one leaks the observer. Scoped subscription tokens held
  in an array make teardown deterministic.
  ```

  If `git log` shows the project uses a different convention for similar tasks, follow that convention instead.

  **A phase is not "done" (✅ in the top table) until ALL its granular checkboxes are `- [x]` AND the phase is committed.** Partial completion stays at 🔄 in the top table with the un-ticked checkboxes still `- [ ]`. The stage's artifact is the source-code changes + the resulting commit history; Refactor does not produce a dedicated `.md`. **No external behavior changes** — that invariant is verified in Validation.

  **Comment hygiene during refactor (hard rule, enforced by the `refactorer` agent):** NEVER embed task/phase/EPIC references in production code comments (`// EPIC X §Y Phase Z — …`, `// Task N phase M — …`, `// Bug123 fix`). Phase provenance lives in (a) the Plan.md per-phase checkbox + table row and (b) the per-phase git commit message — duplicating it inline rots and crowds out evergreen WHY-comments. See the `refactorer` agent's `## Comment Policy` for the full rule and acceptable shapes. This applies to file headers too — no `// Created for EPIC X / Phase Y` lines.

  If `start_phase=<phase_id>` was passed in args — `[refactorer]` receives that phase as the start point in the Task-tool prompt. Already-completed phases (status `✅` in `Plan.md`) are skipped, not redone. The progress table is updated only for new / changed phases.

  When the stage's phases are done, apply `spine-toolkit:task-walkthrough` and write `Walkthrough.md` — the human-facing account of what actually landed, readable before anything has been validated or reviewed. Governed by `[WALKTHROUGH]` in `Task.md`, else `off` when this run's `scale` is `lite` (§2a), else `## Reporting` → `walkthrough` in `CLAUDE-spine-toolkit.md`, else `deep`. The value is the depth the contract carries — `brief` or `deep` — and `task-walkthrough` `## The switch` says what each one changes. Written by `[refactorer]`.

- **Validation** — `[validator]`. Artifact: `Validation.md`, **first line is required** to be `[VALIDATION_STATUS] = PASSED | FAILED | FLAKY` (the shared contract between the `validator`, every `workflow-*`, and the orchestrator; analogous to `[REVIEW_STATUS]`). For the REFACTOR profile, the validator runs a full test run mandatorily as a regression check (every pre-existing test must pass **without modification** — touching a test during a refactor is itself a finding), a build on its own is optional, and a running instance of the app is driven only when the refactor touched a UI layer (views, screens, or navigation) — purely domain/infrastructure refactors skip it. Detailed behavior lives with the `validator` agent. Driving is suppressed by any of four causes, and they are handed over identically: `drive_app` resolving to `off` (`Task.md [DRIVE_APP]` first, then `CLAUDE-spine-toolkit.md ## Validation`), no driver resolving at all, a driver that cannot be reached for this run's surface — its server not connected, the module for that surface not installed, or that surface absent from this machine — or a driver that drives none of the surfaces this platform produces. The second of those reaches only a platform that takes part in the driver contract: a platform whose manifest declares no `## Driver` block drives with its own tooling exactly as it did before this contract existed, and that cause fires for it only when it has no tooling to drive a running instance at all, which its validator announces as a declared deviation. In every one of them the check is **deferred, not dropped**: the validator writes the cases a human must run into a separate `ManualChecks.md`, marks the matching `OpsChecklist.md` items Pending, and returns the case titles in `manual_checks` — surface that list with the stage report. Which driver condition applied comes back in `driver_status` — no driver, one that cannot be reached, or a mismatched one — because the user's next action differs in each; `drive_app: off` is the project's own setting rather than a driver condition, and needs no such report. The vocabulary and the consequences are `conventions/driver-contract.md`. None of these lowers the verdict on its own. `manual_checks: always` in the same two sources produces that artifact even on a run the validator drove itself.

  The validator MUST apply the `ops-checklist` skill in **regression mode**: only items that were Applicable for the affected area pre-refactor are re-checked. Output: `OpsChecklist.md` in the task folder. A previously-Applicable item that no longer has verifiable evidence after the refactor is itself a finding — a violation of the refactor invariant (the refactor changed observable behavior). Pure additive items (new ops concerns introduced by the refactor) are flagged but do not block PASSED. The `manual-checks` skill governs `ManualChecks.md`'s shape — its structure, the required fields of a case, and the two rules that make a case executable — and reads `Plan.md ## Manual acceptance` as its input.

- **Review** — `[reviewer]` (if `need_review=true` in args). Artifact: `Review.md`, **first line is required** to be `[REVIEW_STATUS] = APPROVED | CHANGES_REQUESTED | DISCUSSION` (this field is the shared contract between workflow-* and the orchestrator; it is also used by `spine-toolkit:workflow-review` for auto-move into DONE/). On a redo after `CHANGES_REQUESTED`, the reviewer finds its own prior `Review.md` in the task folder and narrows scope to the commits landed since its `[REVIEWED_COMMIT]` line instead of re-reviewing the whole task from scratch — see the `reviewer` agent → "1. Identify Scope". When the task produced a `ManualChecks.md`, the reviewer reads it as well: a case a person cannot execute as written is an ordinary finding, by the two rules in the `manual-checks` skill. The plan's half of that contract is checked here too: `Plan.md` is required to carry a `## Manual acceptance` section — the single line `Fully automatable.` when nothing qualifies — and a plan with neither is a finding, since the artifact clause above fires only when an artifact was written at all.

- **Done** — final report `Done.md`: what was refactored, why it is now better (readability, separation of concerns, reduced coupling), measurable metrics where available (file size, cyclomatic complexity of key functions, dependency count), validation status (build/test result), and objections (if the user insisted on a contested decision).

  Refresh `Walkthrough.md` here when the Refactor stage did not run in this invocation — an entry at Review or Done means commits landed after it was written. `task-walkthrough` owns the refresh rules; its `[COVERS]` line decides whether there is anything to do.

## 2a. Scale

`scale` arrives in the contract as `lite` or `full`, never empty. `full` runs the stages above
exactly as written. The axis itself — the three levers, the floor, the ratchet and its four
criteria — is `conventions/task-scale.md`; what follows is only what is specific to REFACTOR.

At `lite`:

- **Analyze does not get its own stage.** No agent is dispatched for it and no `Research.md` is
  written. `Plan.md` opens with a `## Analysis` section carrying what that stage would have found:
  what is wrong now, the target shape, the components affected, and the risk the move carries. The
  behaviour-preservation invariant is stated there, because it is what Validation checks against.
- **`OpsChecklist.md` is not written.** The regression check that matters on this profile is the
  pre-existing test suite passing unmodified, and that is Validation's, not the checklist's.
- **`Walkthrough.md` is not written** unless `[WALKTHROUGH]` in `Task.md` says so.
- Every artifact the table in `scripts/lint-artifact-budget.sh` names carries a line ceiling, and
  `Validation.md` links to build and test output rather than pasting it. Read the ceilings from
  that table, pass each one to the agent writing that artifact, and expect the orchestrator to
  measure against the same table when the stage returns.

Unchanged at `lite`: one commit per green phase with the phase's tests run before it, `Validation`
as a full regression run by its own agent — with the rule that touching a pre-existing test is
itself a finding — and `Review` by an independent agent.

**The ratchet.** Both points collapse into the planner's first act, `lite` having folded Analyze
into Plan. Criterion 2 does most of the work on this profile: a refactor that moves a public API
other code depends on is a `full` task whatever its line count.

## 2b. Documentation

`workflows/profile-*.js` carries this in its shared prelude; here it is the same three points,
because the two methods run the same profile.

A change set is matched against the components the project declares in its registry —
`conventions/docs-components.md` for the format, `scripts/docs-route.sh` for the matching.
Whether a rule actually moved is not computed: it is answered per component in the task's
`Docs.md`, in the vocabulary `ops-checklist` already uses, by applying `spine-toolkit:docs-route`.

Every path is relative to the project root, which in a multi-repository project is the container
the checkouts sit in. A diff is not: pipe each checkout's through `reorigin <checkout>` and feed
the concatenation. A phase changing code in one repository and its documentation in another is
the ordinary case here, not the exception.

- **Plan** — run `route` with the paths the plan intends to touch; the components it names go
  into the phase rows, so the obligation hangs on a phase and not on the task.
- **End of the implementing stage, per phase** — run `route` with that phase's
  `git diff --name-status`, answer every row it opens, then run `check` with the same change set
  before committing. Exit 1 means a `blocking` question is still open and the phase does not
  close; exit 2 means the registry or the `Docs.md` table itself is malformed — fix that, it is
  not a question anyone can answer.
- **Done** — run `audit`, then `progress`. `audit` names components living away from their
  coverage and files created outside every `covers`; both are advisory and neither stops
  anything. `progress` regenerates the step table of every declared progress component
  between its markers, leaving everything outside them alone; a progress file whose markers
  are malformed is refused rather than reshaped, and named.
- **Review** — run `check` with the task's whole change set and no `--phase`. It names every row
  still open across all phases; report them, do not enforce them.

All of it is skipped by a stage that changes no files, by a task whose `Task.md` carries `[DOCS] =
[off]`, by a project whose `## Docs` block carries `enabled: off`, and by a project that declares
no components at all — neither in the map named by `## Docs` → `map`, `DocsMap.md` by default —
nor in any package it holds, so a project that declares nothing is served by silence.
Review reads `Docs.md` the way it reads
`OpsChecklist.md`: a row left `Pending` is surfaced for an explicit accept or defer.

## 3. Manual mode

After each completed stage the orchestrator asks the user via the structured question mechanism using the `stage_done_prompt` key from `locales/<lang>.md`, with placeholder `{stage}`.

Workflow-refactor **does NOT ask the user itself** — it returns control to the orchestrator after a stage completes (see section 5, Output Contract) with `next_recommended_action`. The decision to pause, continue, or capture discussions in `Questions.md` is the orchestrator's responsibility.

If the active host has no structured question tool, the orchestrator uses a textual fallback (numbered options + reply parsing). That is the orchestrator's responsibility, not workflow-refactor's.

## 4. Auto mode

No pauses between stages. Workflow-refactor runs the stages sequentially within `stage_scope` and returns the final result to the orchestrator in a single output.

**Per-phase commits inside the Refactor stage are autonomous** — created without a user prompt, in both manual and auto modes. The only commit that always requires confirmation regardless of mode is a flow-level wrap commit (squash, merge, push) when the orchestrator initiates one. That confirmation is the orchestrator's responsibility, not workflow-refactor's.

## 5. Output Contract

After each stage (in `manual` mode) or after a full pass (in `auto` mode), workflow-refactor returns a JSON-like structure to the orchestrator:

```
{
  status: ok | error | cancelled | interrupted,
  last_completed_stage: Analyze | Plan | Refactor | Validation | Review | Done,
  artifact_path: <path to the key artifact, e.g. Tasks/ACTIVE/001-refactor/Done.md>,
  next_recommended_action: continue | stop | ask_user,
  notes: <free-form text, optional>
}
```

Field semantics:
- `status=ok` — the stage finished correctly.
- `status=error` — an error occurred (including reasons such as the locale key `status_error_empty_required_field`, an invalid contract, a fatal subagent failure, or a required behavior change being detected — see section 6).
- `status=cancelled` — the user explicitly declined to continue (the orchestrator forwarded a `No` from its AUQ; rendered to the user via locale key `status_cancelled_user_no`). A normal outcome, not an error.
- `status=interrupted` — execution was interrupted by a technical fault or external signal (not by user decision): subagent disconnect, timeout, tool unavailable. Requires diagnostics on the orchestrator side.
- `last_completed_stage` — the last stage that actually finished (not the one execution stopped on with an error).
- `artifact_path` — path to the key artifact of the last stage: `Research.md` (after Analyze), `Plan.md` (after Plan and after Refactor — Refactor has no dedicated `.md` artifact), `Validation.md`, `Review.md`, `Done.md`.
- `next_recommended_action=continue` — the next stage may start immediately; `stop` — natural finish (Done) or a fatal error; `ask_user` — confirmation is needed before continuing (e.g. after a Validation with `[VALIDATION_STATUS] = FAILED | FLAKY`, or after a Review with `[REVIEW_STATUS] = CHANGES_REQUESTED`).
- `notes` — short free-form description (e.g. the example in locale key `notes_test_failed_example`).

Based on this, the orchestrator decides: continue, abort, or ask the user.

## 6. What workflow-refactor does NOT do

- **Does NOT change external behavior — that is the refactor invariant.** If during the work a bug is discovered whose remediation requires a change in observable behavior (logic fix, API contract fix, UX change), workflow-refactor returns `{status: error, reason: behavior_change_required}` and the user decides whether to create a separate BUG task.
- Does NOT route — profile selection happens in the orchestrator before the call.
- Does NOT read `Task.md` to determine stack/mode — everything arrives in `args`.
- Does NOT trigger `task-new` or `task-move` — that is not its scope.
- Does NOT decide to skip stages — the orchestrator already passed `start_stage`, `end_stage`, `stage_scope`.
- Does NOT create backups in `_archive/` — the orchestrator did so before handing off control; the paths are already in `archive_paths`.
- Does NOT ask the user — the orchestrator does that between stages in `manual` mode.
- Does NOT **ask** the user before per-phase commits — workflow-refactor creates them autonomously after each green phase, with no user prompt. The orchestrator handles user-facing commit confirmation only for any flow-level wrap commit it initiates (squash, merge, push). **"Does NOT confirm with user" means "does not interrupt to ask", NOT "does not commit".** Failing to commit per phase violates the Refactor invariant — an interrupt loses everything since the last commit, defeating the point of phase-by-phase decomposition.
