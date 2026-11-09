---
name: workflow-test
description: |
  TEST profile workflow: Analyze → Plan → Write → Validation → Review → Done. Activated by spine-toolkit:orchestrator; not invoked by the user directly.
  Use when (en): orchestrator dispatches a task with [TASK_TYPE]=TEST
  Use when (ru): оркестратор диспетчеризует задачу с [TASK_TYPE]=TEST
stack_axes_envelope: { may: all, never: [] }
---

# Workflow Test

This skill is **Method B** for the TEST profile: it runs the stages when the host has no Workflow tool. `workflows/profile-test.js` is Method A and runs the same stages as code. The orchestrator picks between them (see `spine-toolkit:orchestrator` → **Dispatch**), and `scripts/lint-workflows.sh` fails if the two stage lists drift apart. Edit a stage here and the script needs the same edit.

The profile workflow for tasks with `[TASK_TYPE] = TEST` — used when writing tests is the primary goal of the task (not part of FEATURE/BUG, where tests ship alongside the implementation). Implements the sequence of stages; the result of each stage is an artifact file inside the task folder. The skill receives an already-resolved contract from the orchestrator and does not try to re-resolve any parameter on its own.

## Language Resolution

Before producing any user-facing string:

1. Read the project config from the project root (core's `conventions/task-settings.md` → Project config).
2. Find the `[LANG]` field.
3. Take the field's value, lowercase and trim it. That is `<lang>`.
4. If `<lang>` is `en` or `ru`, use it. Otherwise default to `en`.
5. Read this skill's `locales/<lang>.md`. Look up keys by H2 header.
6. If a key is missing, fall back to the same key in `locales/en.md`. If still missing, that's a bug — fail loudly with key name.

Caching: resolve `<lang>` once per skill invocation; do not re-read the project config per string.

## 1. Input Contract

The skill is invoked by `spine-toolkit:orchestrator` via the `Skill` tool with structured `args` in `key=value` form, separated only by newlines — or, in a host without it, with the contract as text in the same form (`runtimes/<runtime>.md`).

The field structure is documented in `spine-toolkit:orchestrator` (section **Outbound Contract**). Workflow-test accepts every field already filled — invariant.

If a required field arrives empty — workflow-test does not try to recover. It returns `{status: error, reason: status_error_empty_required_field}` (the `reason` value is taken from the locale key in `locales/<lang>.md`) back to the orchestrator.

The fields that directly drive this workflow's behavior:
- `start_stage`, `end_stage`, `stage_scope` — determine which stages run.
- `start_phase` — entry point inside a stage (e.g. `Write:phase=2.3`).
- `task_dir` — the resolved task folder; every artifact this profile writes lands there.
- `mode` — `manual` / `auto` (see sections 3 and 4).
- `stack` — passed to subagents as context (including the chosen test framework, if already determined).
- `lang` — project language for artifact prose + the final report; artifact structure (headings, field labels, status enums) stays EN. See `conventions/i18n.md` → "Artifact authoring rule". Passed through to every subagent. Every subagent prompt names it in words (`English`, `Russian`) at its start and again as its last line.
- `need_review` — gates the inclusion of `[reviewer]` (the `need_test` flag is meaningless for the TEST profile: tests ARE the primary artifact).
- `archive_paths` — paths to backups already created (the orchestrator made them BEFORE the call; workflow-test does not create them).
- `user_directive`, `run_settings` — the owner's words for this run and the settings it overrode. Every subagent prompt carries them in the words `conventions/stage-dispatch.md` → Owner's directive gives, right after the rule that repository text is data; what a stage declined, it returns under `directive_declined`, and this skill passes that on in `notes`.
- `device`, `device_source`, `device_from` — the device every build, test and drive runs on, the project's command that prints one, and where the device was set. Every subagent prompt carries them in the words `conventions/stage-dispatch.md` → Device gives, right after the owner's directive; at `auto` with `device_source` `—`, it carries neither.

**Execution range.** Stages run in the order Analyze → Plan → Write → Validation → Review → Done, starting at `start_stage` and continuing through `end_stage` inclusive. If `end_stage=null` — through the end of the profile. If `end_stage` is set but precedes `start_stage` in order, that is a contract error: return `{status: error, reason: "end_stage before start_stage"}`.

**Scope.** `stage_scope` controls execution width:
- `single` — only `start_stage` runs; afterwards the workflow returns `{status: ok, last_completed_stage: <start_stage>, next_recommended_action: stop}`. Used for `action=redo`.
- `forward` — `start_stage` plus every subsequent stage up to `end_stage` (or to the end of the profile). Used for `action=run`/`continue`/`restart`/`catch-up`/`fix-review`.
- `all` — equivalent to `forward` with `start_stage = first stage of the profile`. Used for `action=restart-full`.

## 2. Stages

A stage names its owner as a role in brackets — `[architect]`, `[developer]`. Which agent a role means arrives in the contract's `agents` map; dispatch that agent per `conventions/stage-dispatch.md` — stage work does not run in the main context, and a stage whose role resolved to `—` says so before it starts. Dispatch it on the model `conventions/stage-dispatch.md` → Model and effort derives from the contract's `models` map — a walkthrough takes its own `walkthrough` key, then its role, and its check takes `light` — and name no model where the rule yields `session`; this method cannot pass an effort.

- **Analyze** — a panel: `[architect]` + `[tester]` (in sequence: `[architect]` first, as the testability lens, then `[tester]` writes `Research.md` from it). Artifact: `Research.md`. Goal: determine **what to test** (uncovered code, critical paths, regression scenarios), **what test level** (unit / integration / UI / snapshot), **which frameworks** (whichever the platform provides for unit, mocking and snapshot work). Additionally, `[architect]` evaluates the testability of existing code: whether dependency injection, mocks, or protocols for abstracting external dependencies are required.

  Every agent of this stage applies the `task-documents` skill, its `Research.md` section — it holds what the document carries, which outcomes it lists, and what it leaves to `Task.md` and `Plan.md` — and writes in the style of the `artifact-reader` skill. `Research.md` opens with `## Short answer`; what to test, at which level and with which frameworks follow it. Last, run scripts/lint-artifact-readability.sh on the file once, with `--words-per-sentence` taken from the contract's `budgets`; fix each finding once and name what is left in the stage summary.

- **Plan** — `[tester]`. Artifact: `Plan.md` with **two layers of progress tracking**:
  1. **Top-level phase progress table** (see `State Detection` in orchestrator: statuses ✅/🔄/⬜/⏸/🚫/⊘) — one row per phase with a `P0`/`P1`/`P2` priority column, coarse-grained completion. It stays a top-level table, in the `## For the owner` part.
  2. **Per-phase detail section** for each phase — actionable items rendered as **markdown checkboxes** `- [ ] <item>`. Granularity: one checkbox per test case to add, per fixture/mock to create, per assertion-cluster to verify. Granular enough to be ticked individually as the Write stage progresses. Static prose (test-strategy notes, framework choices) stays as plain bullets — only **action items** become checkboxes.

  The plan decomposes tests into phases — usually by groups (one phase per testable component / module / use case). Each phase is assigned a priority `P0` (critical, blocks release) / `P1` (important) / `P2` (nice-to-have).

  The plan applies the `task-documents` skill, its `Plan.md` section — it holds how a step or phase is described, how a risk is written, and what the plan leaves out. It is written in two parts, `## For the owner` and then `## For the implementer`, in the style of the `artifact-reader` skill. Last, run scripts/lint-artifact-readability.sh on the file once, with `--words-per-sentence` taken from the contract's `budgets`; fix each finding once and name what is left in the stage summary. When the contract's `artifact_check` is `on`, a fresh reader checks `Plan.md` after this stage; the Done bullet says how.

  Unless the contract's `report` is `off`, apply the `task-report` skill's `## When`, `## Where` and `## The decision` and write `[REPORT_DECISION]` and `[REPORT_PATH]`.

  Every phase's detail section opens with a `**Verification:**` line and one checkbox per check it names; the rung comes from the `phase-verification` skill, which holds the rungs, the questions that pick one, and when the line says `full`. The full regression belongs to Validation — a phase checks what it can break, and a phase repeating the whole suite at `proportional` is a defect of the plan.

  The tester MUST also add a `## Manual acceptance` section: one line per check that needs a person — a device action, a visual judgment or an external service — stated as what must be true and what changed to make it so, rather than what to press, and ending with `needs:` and which of the three. A check a machine could make is not listed: it is work for a phase, a script or a test named in its `**Verification:**` line, or a line with its reason in `## Not automated`. Nothing qualifies — the single line `Fully automatable.` It is the input Validation turns into `ManualChecks.md`; the `manual-checks` skill holds both halves.

- **Write** — `[tester]`. Implements the phases from `Plan.md` step by step, updating both progress layers as work proceeds. **MUST create one git commit per green phase** — autonomously, without a user prompt. Under `fix-review` it runs the single "Review fixes <n>" phase built from `fix_findings` instead of `Plan.md`'s phases (see Done). The stage writes no `Write.md`: the tester's report is its return.

  Per-item flow inside a phase: complete one actionable item → tick its checkbox `- [ ]` → `- [x]` in the per-phase detail section of Plan.md. Per-phase flow: when all the phase's checkboxes except its verification checks are `- [x]` → build → run the checks the phase's `**Verification:**` line names, ticking each one as it passes — a missing line is written, and a line the diff outgrew is raised, by the `phase-verification` skill first; a rung is never lowered → flip the phase's row in the top-level progress table ⬜→✅ → `git add` the phase's files (including the Plan.md updates — both checkboxes and table) → `git commit`. Commit message format: **Conventional Commits** — `<type>(<scope>): <imperative subject>` followed by an optional body explaining WHY. For Write-stage commits the type is `test` (use `chore` for test-infrastructure-only phases — fixtures/helpers without test logic). **NEVER include the task ID, step ID, or phase number** — provenance lives in `Plan.md`, the branch name, and the PR description. Full spec + anti-examples in `conventions/commit-messages.md`. Example:

  ```
  test(PaginationCalculator): cover boundary and overflow inputs

  Locks in the expected page-range output for empty / single-page / max-page
  inputs — guards against regressions when the calculator is refactored.
  ```

  If `git log` shows the project uses a different convention for similar tasks, follow that convention instead.

  **A phase is not "done" (✅ in the top table) until ALL its granular checkboxes are `- [x]` AND the phase is committed.** Partial completion stays at 🔄 in the top table with the un-ticked checkboxes still `- [ ]`. Artifacts: test code in the project + test helpers/fixtures/mocks where needed + the resulting commit history. **Does NOT modify production code.** If the code under test turns out to be untestable without refactoring (tight coupling, singletons, missing protocols for mocking) — returns `{status: error, reason: refactor_required, notes: "<what specifically blocks, which component>"}` so the orchestrator/user can decide to create a separate REFACTOR task.

  **Comment hygiene (hard rule, enforced by the `tester` agent):** NEVER embed task/phase/EPIC references in test code comments or in assertion/failure message strings (`// §1.6 Phase 7: identity-preservation invariant`, `fail("not used in §1.5 tests")`, `// EPIC X / Phase Y — stub for …`). Assertion messages are read in test-failure output and must be self-explanatory without phase context. Provenance lives in the per-phase git commit message + the test name itself. See the `developer` agent's `## Comment Policy` — same rule applies to tests.

  If `start_phase=<phase_id>` was passed in args — `[tester]` receives that phase as the start point in the Task-tool prompt. Already-completed phases (status `✅` in `Plan.md`) are skipped, not redone. The progress table is updated only for new / changed phases.

  When `[REPORT_DECISION]` is `needed` or `update`, dispatch an agent of this stage's role to write the report by `task-report` → `## The document` and `## Updating`, per `conventions/stage-dispatch.md`.

  When the stage's phases are done, apply `spine-toolkit:task-walkthrough` and write `Walkthrough.md` — the human-facing account of what actually landed, readable before anything has been validated or reviewed. The value arrives in the contract as `walkthrough`; `conventions/task-settings.md` holds the chain it was resolved along. It is the depth the contract carries — `brief` or `deep` — and `task-walkthrough` `## The switch` says what each one changes. Written by `[tester]`. When the contract's `walkthrough_check` is `on` and the write changed the file, `task-walkthrough` → `## Check` follows it: a fresh agent of the writer's role reads the file alone, and the writer revises from what that reader could not follow — and, when that first read named more than three places, once more from a second fresh read, never a third.

- **Validation** — `[validator]`. Artifact: `Validation.md`, **first line is required** to be `[VALIDATION_STATUS] = PASSED | FAILED | FLAKY` (the shared contract between the `validator`, every `workflow-*`, and the orchestrator; analogous to `[REVIEW_STATUS]`). For the TEST profile, the validator runs a full test run mandatorily, through the platform's own test tooling (every newly added test must pass on first run / green); on a first-run failure the validator re-runs the failing test up to 3 times and, if results flap, returns `[VALIDATION_STATUS] = FLAKY` with the test name, fail rate, and a hypothesized cause recorded in `Validation.md`. driving a running instance of the app is optional — only for UI tests requiring visual verification. Driving is suppressed by any of four causes, and they are handed over identically: the contract's `drive_app` resolving to `off`, no driver resolving at all, a driver that cannot be reached for this run's surface — its server not connected, the module for that surface not installed, or that surface absent from this machine — or a driver that drives none of the surfaces this platform produces. The second of those reaches only a platform that takes part in the driver contract: a platform whose manifest declares no `## Driver` block drives with its own tooling exactly as it did before this contract existed, and that cause fires for it only when it has no tooling to drive a running instance at all, which its validator announces as a declared deviation. In every one of them the check is **deferred, not dropped**: the validator writes the cases a human must run into a separate `ManualChecks.md`, marks the matching `OpsChecklist.md` items Pending, and returns the case titles in `manual_checks` — surface that list with the stage report. Which driver condition applied comes back in `driver_status` — no driver, one that cannot be reached, or a mismatched one — because the user's next action differs in each; `drive_app: off` is the project's own setting rather than a driver condition, and needs no such report. The vocabulary and the consequences are `conventions/driver-contract.md`. None of these lowers the verdict on its own. That handoff assumes driving was mandatory; on this profile it never is, so none of the four leaves anything to defer under `auto` — `off` (or any of the others) drops the optional check rather than handing it over, and `auto` therefore has nothing to defer and writes no `ManualChecks.md`. Detailed behavior (flaky-detection procedure, return-digest format) lives with the `validator` agent. The contract's `manual_checks: always` is what produces that artifact on a UI-bearing test run regardless: the ground a green suite leaves unverified — push, biometrics, camera, permission dialogs, backgrounding, low connectivity — written up as cases a human walks, the same way. The `manual-checks` skill governs `ManualChecks.md`'s shape — its structure, the required fields of a case, and the rules that make a case executable — and reads `Plan.md ## Manual acceptance` as its input. Each line, and each deferred check, becomes a case only when it needs a person, by the `manual-checks` skill's `## Does this check need a person?`; one the run checked itself is covered in `## Scope` with its evidence, any other is a `## Not covered` line, automatable but not automated. Under `auto`, no case left means no file: `Validation.md` carries `manual checks: none — <why>`, naming what was covered and each automatable gap, and the Manual test pass item of `OpsChecklist.md` is N/A with that reason; `always` writes the file regardless. The validator writes `ManualChecks.md` by the `manual-checks` skill, refreshing one behind HEAD by `## Refreshing` with the changed files from `git diff --name-only <COVERS>..HEAD`, and runs `scripts/lint-manual-checks.sh` on it, repairs what it names and runs it again. When the contract's `manual_checks_check` is `on` and a passed Validation wrote or changed a `ManualChecks.md` holding a case (moving `[COVERS]` alone is no change), the main context runs `manual-checks` → `## Check`: a fresh `[validator]` on the `light` model walks the file alone, and the validator revises once from what it could not execute. In a `catch-up` it validates the `review_ranges` at the depth the `phase-verification` skill gives their diff.

- **Review** — `[reviewer]` (if `need_review=true` in args). **Special case for the TEST profile:** the review evaluates the quality of the **tests**, not production code, by the `test-authoring` skill's `## Review` section; its first two findings always block. Artifact: `Review.md`, **first line is required** to be `[REVIEW_STATUS] = APPROVED | CHANGES_REQUESTED | DISCUSSION` (this field is the shared contract between workflow-* and the orchestrator; it is also used by `spine-toolkit:workflow-review` for auto-move into DONE/). `Review.md` is written by applying the `task-documents` skill, its `Review.md` section, in the style of the `artifact-reader` skill: every finding carries an `**Impact:**` line. The reviewer reads exactly the ranges in `review_ranges` (`conventions/task-ranges.md`): the whole task on a first pass, the commits since its previous `[REVIEWED_COMMIT]` lines on a re-review, where it also marks each prior Critical and Major Resolved, Still open or Regressed. One that is Still open or Regressed is a finding of the re-review too, under `### Findings` at its severity. It writes the `[REVIEWED_COMMIT]` lines `scripts/task-ranges.sh` prints under `tips --kind reviewed` in the closing block of `Review.md`, exactly as printed; the first line stays the status line. A finding that editing the task's own files closes, with no code commit, goes under `## For Done` and never alone makes the status `CHANGES_REQUESTED`. When the task produced a `ManualChecks.md`, the reviewer reads it as well: a case a tester cannot execute as written is an ordinary finding, by the `manual-checks` skill's `## The case` and `## Grounding` — an empty case and a behaviour claim with no code reference included. The plan's half of that contract is checked here too: `Plan.md` is required to carry a `## Manual acceptance` section — the single line `Fully automatable.` when nothing qualifies — and a plan with neither is a finding, since the artifact clause above fires only when an artifact was written at all. A case that needs no person by the `manual-checks` skill's `## Does this check need a person?`, and a `## Manual acceptance` line with no `needs:`, are findings too; neither blocks. Each phase's `**Verification:**` line is judged by the `phase-verification` skill's `## Review` section: a missing line, an under-claimed rung, and — at `proportional` — a phase repeating the full regression are findings, none of them blocking. Last, run scripts/lint-artifact-readability.sh on the file once, with `--words-per-sentence` taken from the contract's `budgets`; fix each finding once and name what is left in the stage summary.

  Unless `report` is `off`, judge the numbers by `task-report` → `## Review`; a diverging number blocks.

- **Done** — final report `Done.md` (written by applying the `task-documents` skill, its `Done.md` section, in the style of the `artifact-reader` skill): what is now covered (list of components and scenarios), what coverage was achieved (if measured), the list of frameworks used, validation status (are all added tests green, any flaky), and objections (if the user insisted on a contested decision — e.g. declining to test a critical path). When `Done.md` already exists — a redo, a restart, a continue after a hand-back — every claim in it is checked against the current artifacts and the `git log` of every repository the task touched before it is kept, and the report says how many claims were corrected, or that every claim held. Before anything else Done closes every item under `## For Done` in `Review.md` by editing the task's own files, never code, and lists each under `## Review findings closed`; the closing block of `Done.md` holds the `[DONE_COMMIT]` lines `scripts/task-ranges.sh` prints under `tips --kind done`. In a `catch-up` — the orchestrator's action for commits that landed after `Done.md`, running Validation → Review → Done over `review_ranges` — Done also appends to `Plan.md` a phase "Catch-up: commits after Done" that names the ranges, marked ✅, with a `**Verification:**` line naming the depth Validation ran at. Under `fix-review` — the orchestrator's action after Review returns `CHANGES_REQUESTED` — the code-changing stage runs one phase, "Review fixes <n>", built from `fix_findings`: appended to `Plan.md` first with a `**Verification:**` line, then fixed and committed; Validation, Review of those commits and Done follow as usual, and with `after_done` Done also writes the catch-up phase. Last, run scripts/lint-artifact-readability.sh on the file once, with `--words-per-sentence` taken from the contract's `budgets`; fix each finding once and name what is left in the stage summary.

  Unless `report` is `off`, first dispatch an agent of the implementing stage's role for `task-report` → `## Links` steps 1–2, then follow steps 3–6 and run `scripts/lint-report-links.sh <task dir>`.

  When the contract's `artifact_check` is `on`, the main context checks `Plan.md` after Plan and `Done.md` after Done: after the stage that wrote `Plan.md` or `Done.md`, dispatch a fresh agent of the writer's role to read the file only, per `artifact-reader` → `## Check`, then revise once. The reader runs on the `light` model and returns a retelling and the places it had to guess; an entry without a quote names no place and is skipped, and the writer revises once from the rest, never a second round, however many places the read named. A reader that returns nothing leaves the file unchecked and stops nothing; the run notes one line per file.

  Refresh `Walkthrough.md` after `Done.md` is written and its commits are made. Done never edits `Walkthrough.md`: an item under `## For Done` about it goes to the writer, and counts as closed once the writer returns the file. When no item went to it and `scripts/lint-walkthrough.sh --current <task dir>` exits 0, the writer is not dispatched, and the run says so in one line. `task-walkthrough` owns the refresh rules; its `[COVERS]` line decides whether there is anything to do. A refresh that changed the file is checked the same way.

## 2a. Scale

`scale` arrives in the contract as `lite` or `full`, never empty. `full` runs the stages above
exactly as written. The axis itself — the three levers, the floor, the ratchet and its four
criteria — is `conventions/task-scale.md`; what follows is only what is specific to TEST.

At `lite`:

- **Analyze does not get its own stage.** No agent is dispatched for it and no `Research.md` is
  written. `Plan.md` carries an `## Analysis` section as the first section under `## For the implementer`, holding what that stage would have found:
  what is uncovered, which paths are critical, the test level each case belongs at, and whether the
  code under test needs seams before it can be tested at all. That section is `Research.md`
  folded into `Plan.md`, so the `task-documents` skill's `Research.md` section applies to it.
- **`Walkthrough.md` is not written** unless `[WALKTHROUGH]` in `Task.md` says so.
- Every artifact the table in `scripts/lint-artifact-budget.sh` names carries a line ceiling, and
  `Validation.md` links to build and test output rather than pasting it.
  Read the ceilings from the contract's `budgets` field, pass each one to the agent writing that
  artifact, and expect the orchestrator to measure against the same values when the stage returns.

Unchanged at `lite`: one commit per green phase with the phase's tests run before it, `Validation`
by its own agent **including the flake detection** — a test that flaps is the failure this profile
exists to catch, and its three-run re-check is a guarantee, not ceremony — and `Review` of the
tests by an independent agent.

**The ratchet.** Both points collapse into the planner's first act, `lite` having folded Analyze
into Plan. Criterion 1 is the usual trigger here: a suite spanning more than five production files'
worth of surface is not a small task, however small each test looks.

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
  coverage and files created outside every `covers` and every `places`; both are advisory and neither stops
  anything. `progress` regenerates the step table of every declared progress component
  between its markers, leaving everything outside them alone; a progress file whose markers
  are malformed is refused rather than reshaped, and named.
- **Review** — run `check` with the task's whole change set and no `--phase`. It names every row
  still open across all phases; report them, do not enforce them.

All of it is skipped by a stage that changes no files, by a task whose `Task.md` carries `[DOCS] =
[off]`, by a project whose config carries the same, and by a project that declares
no components at all — neither in the map named by `[DOCS_MAP]`, `DocsMap.md` by default —
nor in any package it holds, so a project that declares nothing is served by silence.
Review reads `Docs.md` the way it reads
`OpsChecklist.md`: a row left `Pending` is surfaced for an explicit accept or defer.

## 3. Manual mode

After each completed stage the orchestrator asks the user via the structured question mechanism using the `stage_done_prompt` key from `locales/<lang>.md`, with placeholder `{stage}`.

Workflow-test **does NOT ask the user itself** — it returns control to the orchestrator after a stage completes (see section 5, Output Contract) with `next_recommended_action`. The decision to pause, continue, or capture discussions in `Questions.md` is the orchestrator's responsibility.

If the active host has no structured question tool, the orchestrator uses a textual fallback (numbered options + reply parsing). That is the orchestrator's responsibility, not workflow-test's.

## 4. Auto mode

No pauses between stages. Workflow-test runs the stages sequentially within `stage_scope` and returns the final result to the orchestrator in a single output.

**Per-phase commits inside the Write stage are autonomous** — created without a user prompt, in both manual and auto modes. The only commit that always requires confirmation regardless of mode is a flow-level wrap commit (squash, merge, push) when the orchestrator initiates one. That confirmation is the orchestrator's responsibility, not workflow-test's.

## 5. Output Contract

After each stage (in `manual` mode) or after a full pass (in `auto` mode), workflow-test returns a JSON-like structure to the orchestrator:

```
{
  status: ok | error | cancelled | interrupted,
  last_completed_stage: Analyze | Plan | Write | Validation | Review | Done,
  artifact_path: <path to the final artifact, e.g. Tasks/ACTIVE/001-test/Done.md>,
  next_recommended_action: continue | stop | ask_user,
  notes: <free-form text, optional>
}
```

Field semantics:
- `status=ok` — the stage finished correctly.
- `status=error` — an error occurred (including reasons such as the locale key `status_error_empty_required_field`, an invalid contract, a fatal subagent failure, or `refactor_required` from the Write stage).
- `status=cancelled` — the user explicitly declined to continue (the orchestrator forwarded a `No` from its AUQ; rendered to the user via locale key `status_cancelled_user_no`). A normal outcome, not an error.
- `status=interrupted` — execution was interrupted by a technical fault or external signal (not by user decision): subagent disconnect, timeout, tool unavailable. Requires diagnostics on the orchestrator side.
- `last_completed_stage` — the last stage that actually finished (not the one execution stopped on with an error).
- `artifact_path` — path to the key artifact of the last stage (`Research.md`, `Plan.md`, `Validation.md`, `Review.md`, `Done.md`). The Write stage has no dedicated `.md` artifact — points to `Plan.md` (with the updated progress table).
- `next_recommended_action=continue` — the next stage may start immediately; `stop` — natural finish (Done) or a fatal error; `ask_user` — confirmation is needed before continuing (e.g. after a Validation with `[VALIDATION_STATUS] = FAILED | FLAKY`, after a Review with `[REVIEW_STATUS] = CHANGES_REQUESTED`, or after `refactor_required` from Write).
- `notes` — short free-form description (e.g. the examples in locale keys `notes_test_failed_example` and `notes_refactor_required_example`).

Based on this, the orchestrator decides: continue, abort, or ask the user.

## 6. What workflow-test does NOT do

- Does NOT route — profile selection happens in the orchestrator before the call.
- Does NOT read `Task.md` to determine stack/mode — everything arrives in `args`.
- Does NOT trigger `task-new` or `task-move` — that is not its scope.
- Does NOT decide to skip stages — the orchestrator already passed `start_stage`, `end_stage`, `stage_scope`.
- Does NOT create backups in `_archive/` — the orchestrator did so before handing off control; the paths are already in `archive_paths`.
- Does NOT ask the user — the orchestrator does that between stages in `manual` mode.
- Does NOT **ask** the user before per-phase commits — workflow-test creates them autonomously after each green phase, with no user prompt. The orchestrator handles user-facing commit confirmation only for any flow-level wrap commit it initiates (squash, merge, push). **"Does NOT confirm with user" means "does not interrupt to ask", NOT "does not commit".** Failing to commit per phase loses incremental progress on interrupt and forces a re-do of the whole Write stage.
- Does NOT modify production code. If the code under test is not testable without refactoring — returns `{status: error, reason: refactor_required}`; does not patch on its own.
- Does NOT decide on coverage metrics (coverage thresholds, target percentages) — that's the orchestrator's / user's domain; workflow-test only writes tests per the plan and records the actual coverage in `Done.md`.
