---
name: workflow-quick
description: |
  QUICK profile workflow: Edit → Validation → Review → Done. Activated by spine-toolkit:orchestrator; not invoked by the user directly.
  Use when (en): orchestrator dispatches a task with [TASK_TYPE]=QUICK
  Use when (ru): оркестратор диспетчеризует задачу с [TASK_TYPE]=QUICK
stack_axes_envelope: { may: all, never: [] }
---

# Workflow Quick

This skill is **Method B** for the QUICK profile: it runs the stages when the host has no Workflow tool. `workflows/profile-quick.js` is Method A and runs the same stages as code. The orchestrator picks between them (see `spine-toolkit:orchestrator` → **Dispatch**), and `scripts/lint-workflows.sh` fails if the two stage lists drift apart. Edit a stage here and the script needs the same edit.

The profile workflow for tasks with `[TASK_TYPE] = QUICK`: one small change that `Task.md` already locates, with no Reproduce, no investigation and no Plan stage. The user chooses it explicitly, and only for a root task. The skill receives an already-resolved contract from the orchestrator and does not try to re-resolve any parameter on its own.

## Language Resolution

Before producing any user-facing string:

1. Read `CLAUDE-spine-toolkit.md` from the project root.
2. Find the `[LANG]` field.
3. Take the field's value, lowercase and trim it. That is `<lang>`.
4. If `<lang>` is `en` or `ru`, use it. Otherwise default to `en`.
5. Read this skill's `locales/<lang>.md`. Look up keys by H2 header.
6. If a key is missing, fall back to the same key in `locales/en.md`. If still missing, that's a bug — fail loudly with key name.

Caching: resolve `<lang>` once per skill invocation; do not re-read CLAUDE-spine-toolkit.md per string.

## 1. Input Contract

The skill is invoked by `spine-toolkit:orchestrator` via the `Skill` tool with structured `args` in `key=value` form, separated only by newlines. The field structure is documented in `spine-toolkit:orchestrator` (section **Outbound Contract**). If a required field arrives empty, the skill returns `{status: error, reason: status_error_empty_required_field}` (the `reason` value is taken from the locale key in `locales/<lang>.md`).

The fields that directly drive this workflow's behavior:
- `start_stage`, `end_stage`, `stage_scope` — which stages run, in the order Edit → Validation → Review → Done. `single` runs `start_stage` alone, `forward` runs through `end_stage` (the end of the profile when it is `null`), `all` starts at Edit. An `end_stage` before `start_stage` is a contract error: `{status: error, reason: "end_stage before start_stage"}`.
- `task_dir` — the resolved task folder; every artifact this profile writes lands there.
- `mode` — `manual` / `auto` (see sections 3 and 4).
- `stack` — passed to subagents as context.
- `lang` — project language for artifact prose; artifact structure stays EN (`conventions/i18n.md`). Passed through to every subagent. Every subagent prompt names it in words (`English`, `Russian`) at its start and again as its last line.
- `need_test`, `need_review` — a QUICK task defaults to `need_test=false` and `need_review=true`. `need_review=false` removes Review.
- `scale` — always `lite` for QUICK (`scripts/resolve-settings.sh` resolves it from the type): the artifacts carry the ceilings in `budgets`, and `Walkthrough.md` is written only when `walkthrough` says so.
- `archive_paths` — backups the orchestrator already made.

## 2. Stages

A stage names its owner as a role in brackets — `[architect]`, `[developer]`. Which agent a role means arrives in the contract's `agents` map; dispatch that agent per `conventions/stage-dispatch.md` — stage work does not run in the main context, and a stage whose role resolved to `—` says so before it starts. Dispatch it on the model `conventions/stage-dispatch.md` → Model and effort derives from the contract's `models` map — a walkthrough takes its own `walkthrough` key, then `light`, before its writer's role, and its check takes `light` — and name no model where the rule yields `session`; this method cannot pass an effort.

- **Edit** — `[developer]`. First the entry check, against the code rather than the task's wording. The task stays QUICK only if every one of these holds: the change touches at most two production files; it changes no public API other code depends on and crosses no package boundary; it does not touch the security perimeter — authentication, stored secrets, network configuration, input from outside the app; `Task.md` names where the change goes and what it is. If any one fails, the stage changes nothing, writes nothing and commits nothing, and returns `quick_escalation: {reason}` naming the item and what it found; the run ends there with `next_recommended_action: ask_user`, and the orchestrator tells the user to change `[TASK_TYPE]`.

  When the check holds, the stage writes `Plan.md` with a single phase: a top-level table of one row (statuses ✅/🔄/⬜), a detail section of `- [ ]` checkboxes, one per file to edit, opened by a `**Verification:**` line chosen by the `phase-verification` skill, and a `## Manual acceptance` section — the single line `Fully automatable.` when nothing qualifies, as the `manual-checks` skill defines it. `Plan.md` exists so that State Detection, `fix-review` and `catch-up` work for QUICK as they do for the other profiles; a `Plan.md` already on disk means an earlier run made the check, and Edit finishes its outstanding items instead. Then the change: tick each item, and when every checkbox except the verification checks is ticked, build, run the checks the line names, flip the row ⬜→✅ and commit once, autonomously, by `conventions/commit-messages.md`. With `need_test=true` the same agent writes the test in the same phase, by the `test-authoring` skill. Under `fix-review` it runs the single "Review fixes <n>" phase built from `fix_findings` instead (see Done). Then `Walkthrough.md` by `spine-toolkit:task-walkthrough` when the contract's `walkthrough` is not `off`.

- **Validation** — `[validator]`. Artifact: `Validation.md`, first line `[VALIDATION_STATUS] = PASSED | FAILED | FLAKY`. A build and a full test run, through the platform's own tooling; there is no replay, because there is no `Reproduce.md`. The checks under `## Manual acceptance` are driven where `drive_app` and the driver allow and otherwise deferred into `ManualChecks.md`, whose shape the `manual-checks` skill governs; `driver_status` and the deferral follow `conventions/driver-contract.md` as for every profile. No `OpsChecklist.md`. In a `catch-up` it validates the `review_ranges` at the depth the `phase-verification` skill gives their diff.

- **Review** — `[reviewer]` (if `need_review=true`). Artifact: `Review.md`, first line `[REVIEW_STATUS] = APPROVED | CHANGES_REQUESTED | DISCUSSION`. The reviewer reads exactly the ranges in `review_ranges` (`conventions/task-ranges.md`), writes the `[REVIEWED_COMMIT]` lines `scripts/task-ranges.sh` prints under `tips --kind reviewed`, and puts a finding that editing the task's own files closes under `## For Done`, where it never alone makes the status `CHANGES_REQUESTED`. It judges the change against `Task.md` and `Plan.md`, and whether it is still a QUICK change; no security lens ran, so a diff that touches the perimeter is a blocking finding. When the task produced a `ManualChecks.md`, a case a person cannot execute as written is an ordinary finding, by the two rules in the `manual-checks` skill; a `Plan.md` without `## Manual acceptance` is a finding too. The `**Verification:**` line is judged by the `phase-verification` skill's `## Review` section, none of them blocking; the tests the task added, by the `test-authoring` skill's `## Review` section.

- **Done** — final report `Done.md`: what changed and whether it repaired a defect or added a small behaviour, the test added (or that none was, under `need_test=false`), the validation status, and objections. When `Done.md` already exists — a redo, a restart, a continue after a hand-back — every claim in it is checked against the current artifacts and the `git log` of every repository the task touched before it is kept, and the report says how many claims were corrected, or that every claim held. Before anything else Done closes every item under `## For Done` in `Review.md` by editing the task's own files, never code, and lists each under `## Review findings closed`; the first lines of `Done.md` are the `[DONE_COMMIT]` lines `scripts/task-ranges.sh` prints under `tips --kind done`. In a `catch-up` Done also appends to `Plan.md` a phase "Catch-up: commits after Done" that names the ranges, marked ✅, with a `**Verification:**` line naming the depth Validation ran at. Under `fix-review` Edit runs one phase, "Review fixes <n>", built from `fix_findings`: appended to `Plan.md` first with a `**Verification:**` line, then fixed and committed; Validation, Review of those commits and Done follow as usual, and with `after_done` Done also writes the catch-up phase.

  Refresh `Walkthrough.md` here when Edit did not run in this invocation; `task-walkthrough` owns the refresh rules.

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
[off]`, by a project whose `CLAUDE-spine-toolkit.md` carries the same, and by a project that declares
no components at all — neither in the map named by `[DOCS_MAP]`, `DocsMap.md` by default —
nor in any package it holds, so a project that declares nothing is served by silence.
Review reads `Docs.md` the way it reads
`OpsChecklist.md`: a row left `Pending` is surfaced for an explicit accept or defer.

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
  notes: <free-form text, optional>
}
```

`quick_escalation` comes back only from Edit's entry check, with `ask_user` and `last_completed_stage: null`. The other fields mean what they mean for every profile: `ask_user` also follows a Validation other than `PASSED` and a Review other than `APPROVED`; `status=cancelled` renders `status_cancelled_user_no`; `notes` reads like `notes_build_failed_example`.

## 6. What workflow-quick does NOT do

- Does NOT route, create or move tasks, or create backups — the orchestrator does.
- Does NOT decide to skip stages or re-resolve settings — everything arrives in `args`.
- Does NOT change `[TASK_TYPE]` when the entry check fails — the user decides what the task becomes.
- Does NOT run the security lens — the entry check keeps the perimeter out of a QUICK task.
