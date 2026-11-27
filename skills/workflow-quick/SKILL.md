---
name: workflow-quick
description: |
  QUICK profile workflow: Edit → Validation → Review → Done. Activated by spine-toolkit:orchestrator; not invoked by the user directly.
  Use when (en): orchestrator dispatches a task with [TASK_TYPE]=QUICK
  Use when (ru): оркестратор диспетчеризует задачу с [TASK_TYPE]=QUICK
metadata:
  stack_axes_envelope: { may: all, never: [] }
---

# Workflow Quick

This skill is **Method B** for the QUICK profile: it runs the stages when the host has no Workflow tool. `workflows/profile-quick.js` is Method A and runs the same stages as code. The orchestrator picks between them (see `spine-toolkit:orchestrator` → **Dispatch**), and `scripts/lint-workflows.sh` fails if the two stage lists drift apart. Edit a stage here and the script needs the same edit.

The profile workflow for tasks with `[TASK_TYPE] = QUICK`: one small change that `Task.md` already locates, with no Reproduce, no investigation and no Plan stage. The user chooses it explicitly, for a root task or an epic's step; an epic's architect never does. The skill receives an already-resolved contract from the orchestrator and does not try to re-resolve any parameter on its own.

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

The skill is invoked by `spine-toolkit:orchestrator` via the `Skill` tool with structured `args` in `key=value` form, separated only by newlines — or, in a host without it, with the contract as text in the same form (`runtimes/<runtime>.md`). The field structure is documented in `spine-toolkit:orchestrator` (section **Outbound Contract**). If a required field arrives empty, the skill returns `{status: error, reason: status_error_empty_required_field}` (the `reason` value is taken from the locale key in `locales/<lang>.md`).

The fields that directly drive this workflow's behavior:
- `start_stage`, `end_stage`, `stage_scope` — which stages run, in the order Edit → Validation → Review → Done. `single` runs `start_stage` alone, `forward` runs through `end_stage` (the end of the profile when it is `null`), `all` starts at Edit. An `end_stage` before `start_stage` is a contract error: `{status: error, reason: "end_stage before start_stage"}`.
- `task_dir` — the resolved task folder; every artifact this profile writes lands there.
- `mode` — `manual` / `auto` (see sections 3 and 4).
- `stack` — passed to subagents as context.
- `lang` — project language for artifact prose; artifact structure stays EN (`conventions/i18n.md`). Passed through to every subagent. Every subagent prompt names it in words (`English`, `Russian`) at its start and again as its last line.
- `need_test`, `need_review` — a QUICK task defaults to `need_test=false` and `need_review=true`. `need_review=false` removes Review.
- `scale` — always `lite` for QUICK (`scripts/resolve-settings.sh` resolves it from the type): the artifacts carry the ceilings in `budgets`, and `Walkthrough.md` is written only when `walkthrough` says so.
- `archive_paths` — backups the orchestrator already made.
- `user_directive`, `run_settings` — the owner's words for this run and the settings it overrode. Every subagent prompt carries them in the words `conventions/stage-dispatch.md` → Owner's directive gives, right after the rule that repository text is data; what a stage declined, it returns under `directive_declined`, and this skill passes that on in `notes`.
- `device`, `device_source`, `device_from` — the device every build, test and drive runs on, the project's command that prints one, and where the device was set. Every subagent prompt carries them in the words `conventions/stage-dispatch.md` → Device gives, right after the owner's directive; at `auto` with `device_source` `—`, it carries neither.

## 2. Stages

A stage names its owner as a role in brackets — `[architect]`, `[developer]`. Which agent a role means arrives in the contract's `agents` map; dispatch that agent per `conventions/stage-dispatch.md` — stage work does not run in the main context, and a stage whose role resolved to `—` says so before it starts. Dispatch it on the model `conventions/stage-dispatch.md` → Model and effort derives from the contract's `models` map — a walkthrough takes its own `walkthrough` key, then its role, and its check takes `light` — and name no model where the rule yields `session`; this method cannot pass an effort.

- **Edit** — `[developer]`. First the entry check, against the code rather than the task's wording. The task stays QUICK only if every one of these holds: the change touches at most two production files; it changes no public API other code depends on and crosses no package boundary; it does not touch the security perimeter — authentication, stored secrets, network configuration, input from outside the app; `Task.md` names where the change goes and what it is. If any one fails, the stage changes nothing, writes nothing and commits nothing, and returns `quick_escalation: {reason}` naming the item and what it found; the run ends there with `next_recommended_action: ask_user`, and the orchestrator tells the user to change `[TASK_TYPE]`.

  When the check holds, the stage writes `Plan.md` by applying the `task-documents` skill, its `Plan.md` section, in the style of the `artifact-reader` skill, with a single phase: a top-level table of one row (statuses ✅/🔄/⬜) in `## For the owner`, a detail section under `## For the implementer` of `- [ ]` checkboxes, one per file to edit, opened by a `**Verification:**` line chosen by the `phase-verification` skill, and a `## Manual acceptance` section — a line per check that needs a person, stating what must be true and what changed to make it so and ending with `needs:` — a check a machine could make is a checkbox of the phase instead, or a line with its reason in `## Not automated` — the single line `Fully automatable.` when nothing qualifies, as the `manual-checks` skill defines it. `Plan.md` exists so that State Detection, `fix-review` and `catch-up` work for QUICK as they do for the other profiles; a `Plan.md` already on disk means an earlier run made the check, and Edit finishes its outstanding items instead.

  Unless the contract's `report` is `off`, apply the `task-report` skill's `## When`, `## Where` and `## The decision` and write `[REPORT_DECISION]` and `[REPORT_PATH]`.

  Then the change: tick each item, and when every checkbox except the verification checks is ticked, build, run the checks the line names, flip the row ⬜→✅ and commit once, autonomously, by `conventions/commit-messages.md`. After the commit, a check that ran a whole module's tests green gets one line under its checkbox in Plan.md, by the `phase-verification` skill's `## The line`: `ran: <repository> <module> HEAD <sha> tests <N> result "<result line>" log phase-evidence/phase-<id>/<module>.log`, `<sha>` the phase commit in the module's repository, each `result` a result line of the run's log quoted exactly, as the platform's `test-frameworks` defines it, `<N>` the sum of their counts and the log the run's copy in the task folder. A run of named classes, and a red run, get none; the tasks folder is no change, so the line goes in with the next commit, and Validation carries the run instead of repeating it. With `need_test=true` the same agent writes the test in the same phase, by the `test-authoring` skill. Under `fix-review` it runs the single "Review fixes <n>" phase built from `fix_findings` instead (see Done).

  When `[REPORT_DECISION]` is `needed` or `update`, dispatch an agent of this stage's role to write the report by `task-report` → `## The document` and `## Updating`, per `conventions/stage-dispatch.md`.

  Then `Walkthrough.md` by `spine-toolkit:task-walkthrough` when the contract's `walkthrough` is not `off` and when the contract's `walkthrough_when` is `stage`; at `done`, the default, Done writes it.

- **Validation** — `[validator]`. Artifact: `Validation.md`, first line `[VALIDATION_STATUS] = PASSED | PASSED_WITH_FLAKES | FAILED | FLAKY`. `PASSED_WITH_FLAKES` means the task's own checks passed and the only failures were flaky tests outside the task, each green on a separate retry; it names them, and it passes the gate as `PASSED` does. A build and a test run of the regression set, through the platform's own tooling; there is no replay, because there is no `Reproduce.md`. The checks under `## Manual acceptance` are driven where `drive_app` and the driver allow and otherwise deferred into `ManualChecks.md`, whose shape the `manual-checks` skill governs; `driver_status` and the deferral follow `conventions/driver-contract.md` as for every profile. Each line, and each deferred check, becomes a case only when it needs a person, by the `manual-checks` skill's `## Does this check need a person?`; one the run checked itself is covered in `## Scope` with its evidence, any other is a `## Not covered` line, automatable but not automated. Under `auto`, no case left means no file: `Validation.md` carries `manual checks: none — <why>`, naming what was covered and each automatable gap; `always` writes the file regardless. The validator writes `ManualChecks.md` by the `manual-checks` skill, in the style the contract's `manual_checks_style` names, its `[STYLE]` line saying which, refreshing one behind HEAD by `## Refreshing` with the changed files from `git diff --name-only <COVERS>..HEAD`, and runs `scripts/lint-manual-checks.sh` on it, repairs what it names and runs it again. When the contract's `manual_checks_check` is `on` and a passed Validation wrote or changed a `ManualChecks.md` holding a case (moving `[COVERS]` alone is no change), the main context runs `manual-checks` → `## Check`: a fresh `[validator]` on the `light` model walks the file alone, and the validator revises once from what it could not execute. The validator builds the regression set by the `phase-verification` skill's `## Validation's regression` section, from the contract's `validation_ranges`: `task` holds the task's commits per repository, and `rerun` the commits since the last green Validation — when it is null every module of the set runs that no carried run covers, and `conventions/stage-dispatch.md` says how a Method B prompt names them. It builds and tests that set only, and records it in a `## Regression set` section of `Validation.md`, which the `task-documents` skill's `## Validation.md` describes. The project's known failures registry is the file the contract names in `known_failures`, a missing file an empty registry, and the validator only reads it. It classifies every failing test by the `phase-verification` skill's `### Failures outside the task`: one outside the task is a row of `## Outside the task` in `Validation.md`, in the form the `task-documents` skill gives, and an item of the return's `outside_failures`; a `permanent` entry whose test passed goes into `known_failures_cleared`. A green whole-module run that no later commit and no uncommitted edit reaches is carried, not run again: a phase's `ran:` line in `Plan.md`, written `carried <sha> (phase <N>)` in the Run cell, or a green `ran` row of an earlier `Validation.md` — the current file or its copy in `archive_paths` — whatever its status, written `carried <sha> (validation)`. A module red in the latest Validation that ran it runs again. On PASSED or PASSED_WITH_FLAKES it writes the `[VALIDATED_COMMIT]` lines `scripts/task-ranges.sh` prints under `tips --kind validated` in the closing block, exactly as printed; a FAILED or FLAKY Validation writes none. It then runs `scripts/lint-validation-scope.sh` on the task folder, repairs what it names once, runs it again and names what is left in the stage summary. Lines of class `reach` are not findings: it leaves them for Review. On a re-run the validator reads `Validation.md` — or its copy in `archive_paths`, where the stage's backup moved it — before overwriting it, for the counts and HEAD it carries. A `catch-up` is such a re-run over the commits after `Done.md`. Under the contract's `manual_checks_pass` = `end` the cases of a step go to the epic's collective pass, not to a person as the step ends: the validator marks them by the `manual-checks` skill's `## Marks for a collective pass`, and a check deferred only because a driver could not reach it is marked `**Runner:** agent`, not left for a person. Under `per-step` nothing changes.

- **Review** — `[reviewer]` (if `need_review=true`). Artifact: `Review.md`, first line `[REVIEW_STATUS] = APPROVED | CHANGES_REQUESTED | DISCUSSION`. `Review.md` is written by applying the `task-documents` skill, its `Review.md` section, in the style of the `artifact-reader` skill: every finding carries an `**Impact:**` line. The reviewer runs `task-ranges.sh ranges` with `review_since` (`conventions/task-ranges.md`) as its first step and reads exactly the ranges it prints, writes the `[REVIEWED_COMMIT]` lines `scripts/task-ranges.sh` prints under `tips --kind reviewed` in the closing block of `Review.md`, exactly as printed (the first line stays the status line), and puts a finding that editing the task's own files closes under `## For Done`, where it never alone makes the status `CHANGES_REQUESTED`. It judges the change against `Task.md` and `Plan.md`, and whether it is still a QUICK change; no security lens ran, so a diff that touches the perimeter is a blocking finding. When the task produced a `ManualChecks.md`, a case a tester cannot execute as written is an ordinary finding, by the `manual-checks` skill's `## The case` and `## Grounding`, with `## Brief` in place of `## The case` for a file whose `[STYLE]` is brief — an empty case and a behaviour claim with no code reference included; a `Plan.md` without `## Manual acceptance` is a finding too. A case that needs no person by the `manual-checks` skill's `## Does this check need a person?`, and a `## Manual acceptance` line with no `needs:`, are findings too; neither blocks. Each case is judged by the `manual-checks` skill's `## What a case must prove` too, as that skill's `## Review` says. Apply the `ops-risks` skill's `## Review`: each risk the diff triggers is checked for its proof, a missing proof is a finding of the severity that section gives, and `Review.md` carries `## Ops risks`. The `**Verification:**` line is judged by the `phase-verification` skill's `## Review` section, none of them blocking; the tests the task added, by the `test-authoring` skill's `## Review` section; its first two findings always block. Before it re-runs anything the reviewer reads the `## Regression set` of `Validation.md` and runs `scripts/lint-validation-scope.sh` on the task folder: when it prints no finding the reviewer runs no suite and takes the counts from `Validation.md`; when it prints findings the reviewer re-runs what they name — for a repository, the modules of the set in it. A module of the set that Validation did not run is a Major finding and goes into `blocking_findings`, even when the re-run is green — unlike the plan findings above, it blocks although Validation has passed. A dependent module the set leaves out is a Major finding too, and a run of modules outside the set is a Minor finding that never blocks. A line of class `reach` is no finding of the lint: the reviewer confirms from the diff and the manifests that the commits after its carried sha do not reach the module it names, and a carried row they do reach is a Major finding in `blocking_findings`. Each row of `## Outside the task` is checked against the diff by the `phase-verification` skill's `### Failures outside the task`: a failure the diff does reach, listed as outside, is a Major finding in `blocking_findings`. Last, run scripts/lint-artifact-readability.sh on the file once, with `--words-per-sentence` taken from the contract's `budgets`; fix each finding once and name what is left in the stage summary.

  Unless `report` is `off`, judge the numbers by `task-report` → `## Review`; a diverging number blocks.

- **Done** — final report `Done.md` (written by applying the `task-documents` skill, its `Done.md` section, in the style of the `artifact-reader` skill): what changed and whether it repaired a defect or added a small behaviour, the test added (or that none was, under `need_test=false`), the validation status, and objections. When `Done.md` already exists — a redo, a restart, a continue after a hand-back — every claim in it is checked against the current artifacts and the `git log` of every repository the task touched before it is kept, and the report says how many claims were corrected, or that every claim held. Before anything else Done closes every item under `## For Done` in `Review.md` by editing the task's own files, never code, and lists each under `## Review findings closed`; the closing block of `Done.md` holds the `[DONE_COMMIT]` lines `scripts/task-ranges.sh` prints under `tips --kind done`. In a `catch-up` Done also runs `task-ranges.sh ranges --since done` and appends to `Plan.md` a phase "Catch-up: commits after Done" that names the ranges it prints, marked ✅, with a `**Verification:**` line naming the regression set Validation ran — what it ran and what it carried. Under `fix-review` Edit runs one phase, "Review fixes <n>", built from `fix_findings`: appended to `Plan.md` first with a `**Verification:**` line, then fixed and committed; Validation, Review of those commits and Done follow as usual, and with `after_done` Done also writes the catch-up phase. The phase row has row id `R<n>` and the title "Review fixes <n>" in English whatever the prose language; in its detail section a finding whose recommendation offers more than one way gets a line under it naming the way taken, `by the owner's directive` when the directive chose it, and the Review of those commits checks the fix against that line; a finding left unfixed stays unticked, the row goes to ⏸, and the stage stops before Validation, naming each such finding in its reply — the orchestrator decides what follows. Last, run scripts/lint-artifact-readability.sh on the file once, with `--words-per-sentence` taken from the contract's `budgets`; fix each finding once and name what is left in the stage summary.

  Unless `report` is `off`, first dispatch an agent of the implementing stage's role for `task-report` → `## Links` steps 1–2, then follow steps 3–6 and run `scripts/lint-report-links.sh <task dir>`.

  When the contract's `done_check` is `on` — a QUICK task is `lite`, so only when the owner set it — the main context checks `Done.md` after Done; the one-phase `Plan.md` of Edit is not read, whatever `plan_check` says: after the stage that wrote `Done.md`, dispatch a fresh agent of the writer's role to read the file only, per `artifact-reader` → `## Check`, then revise once. The reader runs on the `light` model and returns a retelling and the places it had to guess; an entry without a quote names no place and is skipped, and the writer revises once from the rest, never a second round, however many places the read named. A reader that returns nothing leaves the file unchecked and stops nothing; the run notes one line per file.

  Refresh `Walkthrough.md` after `Done.md` is written and its commits are made. Done never edits `Walkthrough.md`: an item under `## For Done` about it goes to the writer, and counts as closed once the writer returns the file. When the file is already current and Done committed nothing outside the Tasks folder, those items go to one patch instead, by `task-walkthrough`'s `## Patching`: an item counts as closed only when the patch returns it closed, and no fresh reader follows the patch. When no item went to it and `scripts/lint-walkthrough.sh --current <task dir>` exits 0, the writer is not dispatched, and the run says so in one line. `task-walkthrough` owns the refresh rules; its `[COVERS]` line decides whether there is anything to do. A refresh that changed the file is checked the same way. At `walkthrough_when` = `done`, the default, this is usually the first write, over the task's whole range; where the file already exists — a second Done, a catch-up, a file an older release wrote — it is refreshed by `task-walkthrough` → `## Refreshing`.

## 2a. Scale

`scale` arrives as `lite` for every QUICK task: `scripts/resolve-settings.sh` resolves it from the
type, and a `[SCALE]` in `Task.md` is reported and ignored. QUICK has no stage to fold — it already
runs without Reproduce, an investigating stage and Plan — so the value moves only what `lite` moves
everywhere: the line ceilings in `budgets`, and `Walkthrough.md`, not written unless `[WALKTHROUGH]`
in `Task.md` says so. There is no ratchet: a task that outgrows QUICK leaves it through Edit's
entry check, and the user changes `[TASK_TYPE]` (`conventions/task-scale.md`).

## 2b. Documentation

`workflows/profile-*.js` carries this in its shared prelude; here it is the same three points,
because the two methods run the same profile.

A change set is matched against the components the project declares in its registry —
`conventions/docs-components.md` for the format, `scripts/docs-route.sh` for the matching.
Whether a rule actually moved is not computed: it is answered per component in the task's
`Docs.md`, in three states, Applicable, N/A with a reason, and Pending, by applying `spine-toolkit:docs-route`.

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
Review surfaces a row of `Docs.md` left `Pending` for an explicit accept or defer.

## 3. Manual mode

After each completed stage the orchestrator asks the user via the structured question mechanism using the `stage_done_prompt` key from `locales/<lang>.md`, with placeholder `{stage}`. Workflow-quick does NOT ask the user itself — it returns control to the orchestrator with `next_recommended_action`.

## 4. Auto mode

No pauses between stages. Workflow-quick runs the stages within `stage_scope` and returns the final result in a single output. The Edit commit is autonomous in both modes.

## 5. Output Contract

```
{
  status: ok | error | cancelled | interrupted,
  last_completed_stage: Edit | Validation | Review | Done,
  artifact_path: <path to the last stage's artifact>,
  next_recommended_action: continue | stop | ask_user,
  quick_escalation: {reason} | absent,
  validation_status: PASSED | PASSED_WITH_FLAKES | FAILED | FLAKY | absent,
  outside_failures: [{repository, module, test, outcome: known | flaky | red, entry}] | absent,
  known_failures_cleared: [KF-<N>] | absent,
  notes: <free-form text, optional>
}
```

`quick_escalation` comes back only from Edit's entry check, with `ask_user` and `last_completed_stage: null`. The other fields mean what they mean for every profile: `ask_user` also follows a Validation other than `PASSED` or `PASSED_WITH_FLAKES` and a Review other than `APPROVED`; `status=cancelled` renders `status_cancelled_user_no`; `notes` reads like `notes_build_failed_example`.

`validation_status`, `outside_failures`, `known_failures_cleared` — after a Validation stage: its status line, the rows of `## Outside the task`, and the IDs of its `KF-<N> no longer fails` lines. The orchestrator offers the registry from them (`spine-toolkit:orchestrator` → **Gating**). `PASSED_WITH_FLAKES` passes the gate as `PASSED` does: `continue`, with the note `Validation passed with <n> flake(s) outside the task.`, `<n>` being the items of `outside_failures` whose outcome is `flaky`.

## 6. What workflow-quick does NOT do

- Does NOT route, create or move tasks, or create backups — the orchestrator does.
- Does NOT decide to skip stages or re-resolve settings — everything arrives in `args`.
- Does NOT change `[TASK_TYPE]` when the entry check fails — the user decides what the task becomes.
- Does NOT run the security lens — the entry check keeps the perimeter out of a QUICK task.
