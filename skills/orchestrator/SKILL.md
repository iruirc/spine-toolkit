---
name: orchestrator
description: |
  Routes a user request to the appropriate profile workflow (FEATURE/BUG/REFACTOR/TEST/REVIEW/EPIC/RESEARCH), resolves missing parameters (profile, mode, stack, start point), and manages stages and artifact archival.
  Use when (en): "run N", "do N", "execute N", "continue N", "only <stage> for N", "up to <stage> for N", "start from <stage> for N", "redo <stage> for N", "start from phase N.N for X", "redo phase N.N for X", "start over for N", "rerun validation for N", "catch up N"
  Use when (ru): "запусти N", "сделай N", "выполни N", "продолжи N", "только <stage> для N", "до <stage> для N", "начни с <stage> для N", "переделай <stage> для N", "начни с фазы N.N для X", "переделай фазу N.N для X", "начни заново для N", "перезапусти валидацию для N", "догони N"
---

# Orchestrator

Single entry point for routing tasks from `Tasks/<STATUS>/<task_id>-*/` into the corresponding profile workflow. The skill accepts a minimal input (only `task_id`), fills in the remaining parameters via a deterministic algorithm, and hands control to `spine-toolkit:workflow-*` via a structured contract.

The skill itself does not perform the work of stages — it only resolves parameters, validates the command, confirms with the user (in `manual` mode), and dispatches control to the profile workflow.

## Language Resolution

Before producing any user-facing string:

1. Read `CLAUDE-spine-toolkit.md` from the project root.
2. Find the `[LANG]` field.
3. Take the field's value, lowercase and trim it. That is `<lang>`.
4. If `<lang>` is `en` or `ru`, use it. Otherwise default to `en`.
5. Read this skill's `locales/<lang>.md`. Look up keys by H2 header.
6. If a key is missing, fall back to the same key in `locales/en.md`. If still missing, that's a bug — fail loudly with key name.

Caching: resolve `<lang>` once per skill invocation; do not re-read CLAUDE-spine-toolkit.md per string.

## Agent Tooling

Use `conventions/agent-tooling.md` for host-neutral interaction terms.

A user command that reaches this skill is standing authorization to dispatch the profile's stage agents for the whole task — see `conventions/stage-dispatch.md`.

In this skill, `AskUserQuestion` / `AUQ` means the structured question
mechanism. If the active host cannot provide a structured question tool, ask the
question with numbered options in a regular message and parse the user's reply.
Use the same locale key the AUQ call would have used, for example
`fallback_profile_question`.

Reply parsing: a digit, the profile name, or an unambiguous prefix (`bug`, `ref`, `test`).

## Resilient Input Contract

The minimum viable input is just `task_id`. All other fields are optional and resolved in the Resolution Algorithm.

| Field | Type | Source | Default / Error |
|---|---|---|---|
| `task_id` | string | NL/$ARGUMENTS (e.g. `026`, `052`, `001-foo`) | **required** — error using key `error_no_task_id` |
| `action` | enum: `run` / `continue` / `redo` / `restart` / `restart-full` / `catch-up` | parsed from the command (see triggers table) | `run` for a bare "run/do/execute N", `continue` for "continue N", `catch-up` for "catch up N" |
| `stage_target` | string (profile stage name) | required for `redo` / `restart`, or for `--from` / `--to` modifiers under `run` | not needed for `run` / `continue` / `restart-full` without modifiers |
| `mode_override` | enum: `manual` / `auto` | explicit "automatically" / "step-by-step" in the request | resolved via `resolve-settings.sh` (Resolution Algorithm step 3); default `manual` |
| `stack_override` | string | stack explicitly named in the request | resolved per-axis via stack-detect (see Resolution Algorithm step 4); AUQ only for unresolved needed axes |

**Invariant:** the orchestrator does NOT crash on missing optional fields. It resolves them in the Resolution Algorithm and only then hands the fully populated contract to workflow-*.

## Routing

The orchestrator does not activate on every user request — light commands bypass it. Order of checks (first match wins):

1. **Project initialization** — "create project" / "initialize" → answer with key `routing_project_init` and stop. Orchestrator does not run. The trigger is what the user asked for, never the shape of the repository: which files make a project is a platform's knowledge, and routing precedes Resolution — no config, no manifest and no `agents` map yet, possibly no platform installed at all. That is also why the string points at the platform's `init` entry point in general terms rather than naming an agent it cannot resolve. An unconfigured project that reaches task work instead is caught at the head of check 4, which points at the same entry point.
2. **Task management** — "create task" / "new task" / "ft" / "create sub-task for N" → skill `task-new`. "Move task" / "to DONE" / "step N of epic M to <STATUS>" → skill `task-move`. Orchestrator does not run.
3. **Micro-edit** — "fix" / "rename" / "change" + ≤2 files with no interface changes → execute directly with a quick build check. Orchestrator does not run.
4. **Otherwise** — this is task work. The orchestrator runs:
   - Is there a `CLAUDE-spine-toolkit.md`? No → answer with key `error_no_project_config` and stop. This precedes `task-new` and every question of the Resolution Algorithm on purpose: with no config there is no `## Platform`, so no manifest and no `agents` map, and nothing this branch resolves could be dispatched — scaffolding a task and asking about stack axes first would spend the user's answers on a dispatch that cannot happen. `error_no_platform_manifest` at step 5.7 is the neighbouring case, a config that exists but names no usable platform.
   - Is there a `Task.md` for `task_id`? Yes → read `[TASK_TYPE]`, `[WORKFLOW_MODE]` (if present), `## 4. [Stack]` (if present), `[STATUS]` (for steps).
   - No → run `task-new`, then continue.
   - Determine the profile from `[TASK_TYPE]` (see Dispatch).
   - Confirmation/skip is governed in Resolution Algorithm, step 6 (single source of truth).
   - **Driver pre-flight.** Run this only when `drive_app` does not resolve to `off` **and** the
     resolved stage range includes Validation — or, for RESEARCH with `research_experiment=on`
     (read as the Outbound Contract's `research_experiment` paragraph says), the Research stage,
     whose experiment drives the app (`skills/workflow-research/SKILL.md` § 2c). On a run that
     reaches neither, or one told not to drive, none of it is needed and the driver's manifest is
     not invoked at all. Take `driver`
     from the same `resolve-settings.sh json <task dir>` call Resolution Algorithm step 3 already
     made, rather than reading `Task.md` or the project config directly a second time — then resolve
     it against the platform manifest's `## Driver → default`. A value of `auto` falls through to
     that default; an explicit `—` is the project choosing none, and ends the chain there. On `—`,
     say nothing: no driver is a supported configuration, not a problem. Otherwise invoke
     `<driver>:manifest`. If it does not resolve, report with key
     `warn_driver_plugin_missing`. If it resolves, read the `namespace` row of its `## Driver`
     block — it lists one or more prefixes — and look for a tool named `mcp__<prefix>__*` for each
     in turn. The first prefix with tools present is the one this session uses. If none of them
     has any, report with key `warn_driver_server_missing`, substituting the full list into
     `{namespaces}`. **Both are warnings, not stops** —
     the run proceeds, the build and the tests still produce their evidence, and the validator
     defers the UI checks to a human on its own — or the experiment writes the steps it could not
     drive as a protocol for a person. The warning exists so that this is learned before the
     implementing stage, or the experiment, rather than after it.

## State Detection

The source of truth is `Plan.md` (the progress table with checkboxes `⬜ 🔄 ✅ ⏸ 🚫 ⊘`).

Checkbox legend: `⬜` = todo (planned), `🔄` = in progress, `✅` = done, `⏸` = paused, `🚫` = blocked, `⊘` = skipped.

State Detection is **profile-aware** and **purely file-existence driven** — the orchestrator never parses inline content of `Task.md`. Per-profile mapping from filesystem markers in the task folder to a `start_stage`:

| Profile | `Plan.md` exists | `Review.md` exists | `Research.md` exists | `Reproduce.md` exists | None of the above |
|---|---|---|---|---|---|
| FEATURE | first `⬜` phase | n/a | `Plan` | n/a | `Research` |
| EPIC | first `⬜` phase | n/a | `Plan` | n/a | `Research` |
| BUG | first `⬜` phase | n/a | `Plan` | `Diagnose` | `Reproduce` |
| REFACTOR | first `⬜` phase | n/a | `Plan` | n/a | `Analyze` |
| TEST | first `⬜` phase | n/a | `Plan` | n/a | `Analyze` |
| REVIEW | n/a | n/a | n/a | n/a | `Review` (single-stage profile) |
| RESEARCH | n/a | `Done` | `Review` (if `need_review=true`) else `Done` | n/a | `Research` |

Algorithm:

1. Task folder is in `Tasks/DONE/` OR `Done.md` exists → the task has been finished once. For FEATURE, BUG, REFACTOR and TEST, first run `bash "<core root>/scripts/task-ranges.sh" ranges <task dir> --since done`:
   - every repository at 0 commits → finished: AUQ to confirm a full restart (=`action=restart-full`), reopen (move back into `ACTIVE/`), or exit;
   - any repository with commits after its `[DONE_COMMIT]` → AUQ using key `auq_catch_up_question` with `{counts}` (repository: commits, one per line), `catch-up` first (key `auq_catch_up_option`, =`action=catch-up`), then the three options above;
   - otherwise, a repository `unknown` because `Done.md` predates the record → the same AUQ with the three options above first and `catch-up` last, the option carrying `warn_catch_up_whole_task`.
   - exit 2 is a stop: report the script's stderr.
   Other profiles: finished, the three options above.
2. Walk the columns of the row matching the current profile **left to right**; the first match determines `start_stage`. For BUG specifically: `Plan.md` wins over `Research.md`, which wins over `Reproduce.md`.
3. `Plan.md` exists but its progress table is missing or unparseable → consider stage `Plan` complete; start at the next stage in the profile's sequence (FEATURE/EPIC: `Execute`; BUG: `Fix`; REFACTOR: `Refactor`; TEST: `Write`); for REVIEW (no next stage), ask explicitly via AUQ. RESEARCH has no Plan stage at all — this branch is unreachable for RESEARCH. Add a warning to the user.
4. **Inline-content note.** If `Task.md` carries embedded reproduce/research/analyze material but no artifact files exist in the task folder, State Detection still picks the first stage of the profile (per the rightmost column of the table); for BUG that stage checks a root cause `Task.md` names at file:line rather than rediscovering it. The user can override via the `confirm_dispatch` picker (Resolution Algorithm step 6) or by passing `--from <stage>`.

**Invariant:** `start_stage` produced by State Detection is always a member of the target profile's stage list. Defense-in-depth validation runs in Resolution Algorithm step 5.5 regardless.

**De-sync:**
- `Task.md` is newer than `Plan.md` → warn that the task description may have changed after planning; suggest `redo Plan`.
- Git contains commits touching task files without checkbox updates in `Plan.md` → warn about the desync; do not block, but flag it in the outbound contract.

## Resolution Algorithm

```
1. Validate & find task folder:
   • If task_id is not provided → error using key `error_no_task_id` and stop.
   • Otherwise — locate the folder Tasks/<STATUS>/<task_id>-*/ (scan Tasks/**/<task_id>-* across all STATUS folders).
   • For steps: Tasks/**/<parent_id>-*/.../<step_id>.step/
   ↓ if not found → error using key `error_task_not_found` with placeholder `{task_id}`

2. Resolve TASK_TYPE → profile
   • Read Task.md, extract the [TASK_TYPE] field
   ↓ if missing → AUQ using key `fallback_profile_question`
   ↓ profile = workflow-<TASK_TYPE.lower()>

3. Resolve the settings — one call, every field:
     bash "<core root>/scripts/resolve-settings.sh" json <task dir>
   • mode_override (NL: "automatically" / "step-by-step") wins over the `mode` field
   • progress_override (NL: "quietly" / "with live indication") wins over the `progress` field
   ↓ every other field is the value the script printed; do not re-derive one by reading a file
   ↓ a non-zero exit is a stop, not a default: report the script's own stderr and dispatch
     nothing. `docs-route.sh` and `lint-artifact-budget.sh` end their own runs at exit 2 for the
     same reason, and a run that guessed a setting here would carry the guess into every stage.

   An unrecognized `progress` value resolves to "normal" without an error: the resolved value is
   printed in the settings column, so a typo shows up as a mismatch with the file rather than as
   silence. Every other value the script could not take at face value reaches this call on
   stderr; which key announces which line is in **Progress reporting**.

4. Resolve stack (per-axis; replaces the old monolithic chain):
   4.0 if stack_override is set (stack explicitly named in the request):
          stack := stack_override
          skip to step 5            # explicit override wins, like mode_override
   4.1 envelope := workflow-<profile> frontmatter `stack_axes_envelope`
                   (absent → {may: all, never: []})
   4.2 if envelope.never == all:                       # review, epic
          stack := raw read of CLAUDE-spine-toolkit.md ## Stack  # ambient info-only
          # NO chain, NO AUQ, NO stack-detect; skip to step 5
          # 4.2 is load-bearing: stack-detect returns {} here, not the ambient text
   4.3 scope := task file scope
               (Task.md ## 1. [Files] | fallback: plan's affected paths)
   4.4 {needed, resolved, unresolved} :=
          Skill stack-detect (task_files=scope, envelope=envelope, task_id=task_id)
       # stack-detect owns the manifest's ## Heuristics + the per-axis chain.
       # Path matching is free; it opens a file only for an axis the chain
       # left unresolved, so a configured project costs no read here
   4.4a if scope is empty (## 1. [Files] absent, blank, or comment-only
        AND no fallback affected paths):
          # defer: do NOT AUQ even for partially-unresolved axes — files
          # unknown yet (early Research/Reproduce/Analyze). Asking now would
          # cache a guessed axis into ## 4. [Stack] and poison later stages.
          stack := concatenated string of `resolved` (project-config hits only)
          note `unresolved` as deferred (informational, passed to workflow-*)
          skip 4.5 and 4.6; proceed to step 5
          # re-resolved automatically on a later stage dispatch once Diagnose/
          # Plan populates [Files] or the plan's affected paths exist
   4.5 for axis in unresolved:
          AUQ using locale key `auq_axis_<axis>_question`
              ↓ no such key (an axis beyond the six core names) →
                `auq_axis_generic_question`, placeholder `{axis}`
              options := the manifest's ## Axes values for axis
          resolved[axis] := user choice
       (multiple unresolved → group into one multi-question AUQ form)
   4.6 cache: upsert Task.md → ## 4. [Stack] with resolved values
              (AUQ becomes a one-time event per task)
   4.7 stack := concatenated string of resolved values "v1+v2+v3"
              (axes not in `needed` / still absent are omitted)
              # a catalog value may itself contain "+", so this string is display and
              # agent context only — never split it back into axes

5. Resolve start_stage (depends on action):
   action=run, stage_target=null  → state-detection: first unfinished stage
   action=run, stage_target=X     → start at X (--from), do not touch previous stages
   action=continue                → state-detection (same as run without stage)
   action=redo, stage_target=X    → start at X, re-execute ONLY this stage
   action=restart, stage_target=X → start at X, re-execute X and all subsequent stages
   action=restart-full            → start at the profile's first stage, re-execute all
   action=catch-up                → start at Validation, forward (Validation → Review → Done)
                                    ↓ no Done.md → error using key `error_catch_up_not_done` with `{task_id}`, dispatch nothing

5.5. Validate start_stage against profile.stages:
   • profile_stages := ordered stage list of the target profile (canonical source: workflow-<profile> SKILL.md heading)
   • if start_stage ∈ profile_stages → continue
   • else (defense-in-depth — covers bugs in State Detection, user typos in `--from`, future code paths):
       if mode == manual:
           recommended := the stage State Detection (Section "State Detection") would have picked
           if recommended ∉ profile_stages:                                # State Detection itself was buggy
               recommended := profile_stages[0]                            # safe fallback to profile's first stage
           options := stage_picker_options(recommended, profile_stages)   ↓ see helper below
           AUQ using key `auq_stage_recovery_question`
              placeholders: `{profile}`, `{invalid_stage}`, `{profile_stages_list}`
              options: `options` (rendered with recommended-suffix on `recommended`)
           → user picks stage S → start_stage := S, continue
           → user picks Cancel → return {status: cancelled, reason: status_cancelled_user_no}
       if mode == auto:
           return {status: error, reason: error_stage_not_in_profile,
                   notes: locale `error_stage_not_in_profile` with placeholders filled}

5.6. Record the base and compute the review ranges (FEATURE, BUG, REFACTOR, TEST only;
     every other profile gets review_ranges={} and no Base.md):
   • the range includes the profile's code-changing stage (Execute / Fix / Refactor / Write),
     and there is no Plan.md yet or no phase of its progress table is marked ✅
       → bash "<core root>/scripts/task-ranges.sh" record <task dir>      # writes Base.md once
     # a phase already landed: today's tip is not the task's start, so the base fallback decides
   • the range includes Review, or action=catch-up:
       since := done     if action=catch-up
                base     if Review.md is absent, or action is restart or restart-full
                reviewed otherwise
       review_ranges := bash "<core root>/scripts/task-ranges.sh" ranges <task dir> --since <since>
       ↓ action=catch-up and every repository is ok at 0 commits
         → announce `info_catch_up_nothing` with `{task_id}` and stop, dispatch nothing
       ↓ since ≠ base and a repository came back rewritten or unknown
         → rerun with --since base
       ↓ a repository came back rewritten or unknown from either call — at --since base too,
         where there is nothing to rerun → announce `warn_review_ranges_full` with {repos}
   • otherwise review_ranges := {}
   ↓ exit 2 from either call is a stop, as for resolve-settings.sh: report its stderr, dispatch nothing

5.7. Resolve agents (per-role) — the map every stage dispatches through:
   • platform := first non-empty line of ## Platform in CLAUDE-spine-toolkit.md
   • invoke `<platform>:manifest`, read its ## Roles table
     ↓ if ## Platform is absent or empty, or the manifest skill does not load →
       error using key `error_no_platform_manifest` and stop
       (`{plugin}` := the ## Platform name, or `—` when the section is absent or empty)
   • rows(role) := the ## Agents rows of CLAUDE-spine-toolkit.md for the roles that block names,
                   the manifest's ## Roles rows for every other role     # the config overrides per role
     # a ## Agents row is a line whose left-hand side is one of the nine role words, bare or
     # axis-qualified. The block's shipped body is explanatory prose with angle-bracket
     # placeholders; nothing in it is a row, so a fresh config overrides nothing.
   • for each of the nine core roles, looking ONLY at rows(role):
         an axis-qualified row `role[axis=value]` whose `value` equals this project's resolved
         value for `axis`                                      (first in file order if several)
         > the bare `role =` row
         > `—`                                                             (declared absent)
   • agents := {role: chosen value} — all nine roles, in vocabulary order:
     architect, developer, tester, reviewer, refactorer, validator, security, diagnostics, init

6. Confirmation in manual mode:
   if mode == manual:
       AUQ using key `confirm_dispatch` with placeholders `{profile}`, `{mode}`, `{stack}`, `{start_stage}`
       options (in this order):
           1. locale key `confirm_dispatch_yes`     → dispatch as resolved
           2. locale key `auq_confirm_dispatch_pick_stage` → open the picker:
                  recommended := start_stage (the stage that arrived from step 5/5.5 — by construction valid)
                  options := stage_picker_options(recommended, profile_stages)
                  AUQ using key `auq_stage_override_question`  (placeholder: `{profile}`)
                  → user picks S → start_stage := S, then dispatch
                  → user picks Cancel → return {status: cancelled, reason: status_cancelled_user_no}
           3. locale key `confirm_dispatch_cancel`  → return {status: cancelled, reason: status_cancelled_user_no}
   else:
       skip confirmation, go straight to Dispatch

   Confirmation is also skipped if both key parameters (profile AND mode) are explicitly stated in the user's original command.
   "Explicitly stated" = present as literal keywords in the request text.
   Example: `run 026 as BUG automatically` — confirmation skipped (both "BUG" and "automatically" are present).
   Example: `run 026` — confirmation required (neither profile nor mode is explicit).
```

**Stack resolution (step 4) delegates to `spine-toolkit:stack-detect`.** The
orchestrator passes `{task_files, envelope, task_id}` and receives
`{needed, resolved, unresolved}`. `stack-detect` performs no AUQ and writes no
files — the orchestrator owns the per-axis AUQ (locale keys
`auq_axis_<axis>_question`, options from the manifest's `## Axes`), the
`Task.md → ## 4. [Stack]` cache write, and concatenated serialization. Which
axes exist, which values they take and which repo signals imply them are the
manifest's `## Axes` and `## Heuristics` — core names no axis but `ecosystem`;
projects override the global `## Stack` via `CLAUDE-spine-toolkit.md → ## Modules`.
The effective precedence is task-local `## 4. [Stack]` → module override →
global `## Stack` → import scan. When
`envelope.never == all` (review/epic), the project `## Stack` is read raw and
passed as ambient informational context only — no chain, no AUQ.

**Agent resolution (step 5.7) reads the platform's manifest.** The orchestrator is the only
place that can: a workflow script's sandbox has no filesystem, which is why the finished map
travels in the contract exactly as `stack` and `lang` do. It is read by **invoking**
`<platform>:manifest`, never by opening a file under the host's plugin cache — the table format
and everything a platform must declare live in `conventions/platform-contract.md`.

The resolution is redone on every orchestrator invocation and written to no project file: the
manifest is the source of truth, and a copy cached in a config would go stale the moment the
platform plugin updates. Three details the step's precedence list leans on:

- **Axis values** for an axis-qualified row come from the per-axis `resolved` map of step 4,
  before it is flattened into `stack`. Two paths through step 4 never build that map, and each
  has its own source. On **4.0** — the user named the stack outright, the case where the axis is
  most certain — the values are those `## Axes` values that appear in the `stack_override` string
  **as whole words**, matched case-insensitively except for a catalog value that is also ordinary
  English, one word or a phrase, which is matched case-sensitively so that the sentence's ordinary
  use of the word pins nothing. Classify a new platform's catalog value by value against that one
  test — would this value occur in an English sentence that is not about the stack? — because every
  catalog has some: framework and pattern names are drawn from ordinary vocabulary. An axis for
  which two or more **distinct** values match is left unresolved rather than guessed — naming two
  values of one axis in a contrast ("X, not Y") means one of them, and an unresolved axis degrades
  safely while a wrongly pinned one does not. So is an axis the override never names: 4.0 skips to step 5
  and reads no config, so there is nothing else to fall back to. On **4.2** (review/epic, no
  per-axis resolution) the values are the `axis: value` lines of the project `## Stack`, matched
  case-insensitively. An axis still without a value matches no axis-qualified row — such a role
  falls through to its bare row, or to `—`.

  One class of miss survives all of that and is deliberately not chased: a catalog value colliding
  with ordinary prose in a way case cannot separate — a value the catalog itself spells in
  lowercase, or a capitalized value at the head of a sentence, where the capital says "sentence"
  and not "framework". They all fail in the same direction, pinning an axis wrongly rather than
  leaving it unresolved, and
  telling them apart needs phrase-level analysis that would fail the same way more often.
- **The `## Agents` override** in `CLAUDE-spine-toolkit.md` takes the same row grammar as the
  manifest's `## Roles`. It is a per-role replacement, not a merge: for a role it names, the
  manifest's rows for that role — bare and axis-qualified alike — are not consulted at all. The
  block ships in every config and normally holds no row: a block whose only content is its own
  explanatory prose names no role and overrides nothing, which is the state to expect, not an
  unfinished config.
- **`—` is an answer, not a failure.** A role no platform agent implements is a declared absence,
  and the stage that owns it still runs — announced as a deviation in the stage's first message with
  key `deviation_role_absent` (placeholders `{role}`, `{stage}`), under the "Declared deviation"
  rule of `conventions/stage-dispatch.md`. Method B runs it inline;
  a Method A script can neither announce nor run it and hands the stage back instead (**Dispatch**
  → "Method A — a stage whose role resolved to `—`"). Only an unreadable manifest is an error.

**Helper: `stage_picker_options(recommended, profile_stages)`** — deterministic picker, hard cap 4 total options (structured question option-count limit, observed empirically; exceeding it causes some hosts to silently truncate).

```
N := len(profile_stages)
if N <= 3:
    options := profile_stages + [Cancel]                     # ≤ 4 options total
else:
    i := index_of(recommended) in profile_stages
    if i == 0:        neighbors := [profile_stages[1], profile_stages[2]]
    elif i == N - 1:  neighbors := [profile_stages[N-2], profile_stages[N-3]]
    else:             neighbors := [profile_stages[i-1], profile_stages[i+1]]
    options := [recommended, *neighbors, Cancel]             # exactly 4
```

Rendering rules:

- `recommended` carries the locale key `auq_stage_recovery_recommended_suffix` appended to its label. Other stages are unannotated.
- The Cancel option uses locale key `confirm_dispatch_cancel`.
- Stages are rendered **in profile order** (so neighbors render in their natural positions, not as "recommended + neighbors").
- If the user wants a stage that is not in the picker (far from `recommended`): pick Cancel and re-invoke with `--from <stage>`.

Worked examples for BUG profile (`profile_stages = [Reproduce, Diagnose, Plan, Fix, Validation, Review, Done]`, N=7):

- `recommended = Reproduce` (i=0) → picker = `[Reproduce (R), Diagnose, Plan, Cancel]`
- `recommended = Plan` (i=2) → picker = `[Diagnose, Plan (R), Fix, Cancel]`
- `recommended = Done` (i=6) → picker = `[Validation, Review, Done (R), Cancel]`

See also the "Stage Management" section — it details the semantics of `run --from` / `redo` / `restart` / `restart-full` and the "what gets archived" matrix.

## Outbound Contract

After Resolution, the orchestrator hands these fields to the dispatch path chosen in **Dispatch**. The fields are identical either way; only the encoding differs. Method B takes `key=value` form, **separated only by newlines** (a comma is NOT used as a field separator). Method A takes the same fields as a JSON object. **All fields are filled** — neither workflow-* nor a workflow script tries to recover anything.

Multi-valued fields (e.g. `archive_paths`) are encoded in **list syntax**: square brackets, commas inside. The four map-valued fields (`agents`, `budgets`, `models`, `effort`) are encoded in **brace syntax**: `{key: value, key: value}`.

Method A passes `need_test` and `need_review` as JSON booleans (`true`/`false`), never as the strings `"true"`/`"false"` — a workflow script compares them with `=== false`.

```
task_id=001
task_dir=Tasks/ACTIVE/001-feature-search
profile=feature
action=run|continue|redo|restart|restart-full|catch-up
start_stage=Plan
start_phase=2.3
end_stage=null
stage_scope=single|forward|all
mode=manual|auto
lang=ru|en
stack=alpha
agents={architect: fixture-platform:fixture-architect, developer: fixture-platform:fixture-developer, tester: fixture-platform:fixture-developer, reviewer: fixture-platform:fixture-architect, refactorer: fixture-platform:fixture-developer, validator: —, security: —, diagnostics: —, init: —}
need_test=true|false
need_review=true|false
walkthrough=brief|deep|off
walkthrough_check=on|off
docs=on|off
scale=lite|full
drive_app=auto|off
manual_checks=auto|always
phase_verification=proportional|full
security=auto|on|off
budgets={Done.md: 80, Plan.md: 200, Reproduce.md: 120, Review.md: 120, Task.md: 100, Validation.md: 100}
models={light: sonnet, walkthrough: session, done: session, architect: session, developer: session, tester: session, reviewer: session, refactorer: session, validator: sonnet, security: session, diagnostics: session}
effort={walkthrough: session, done: session, architect: session, developer: session, tester: session, reviewer: session, refactorer: session, validator: session, security: session, diagnostics: session}
long_run={stall: 5, max: 30}
plugin_root=/Users/<user>/.claude/plugins/cache/<marketplace>/spine-toolkit/<version>
roots=[/Users/<user>/App, /Users/<user>/Packages/Net]
review_ranges={"since": "reviewed", "repos": {".": {"range": "1a2b3c4..HEAD", "commits": 2, "state": "ok"}}}
archive_paths=[Tasks/ACTIVE/001-profile/_archive/Plan-2026-04-25T143022.md, Tasks/ACTIVE/001-profile/_archive/Research-2026-04-25T143022.md]
```

Semantics of `stage_scope`:
- `single` — only `start_stage` (for `redo`)
- `forward` — `start_stage` → end (for `run --from`, `continue`, `restart <stage>`)
- `all` — every stage of the profile, from first to last (for `restart-full`)

`end_stage` — filled only when `--to <stage>` is used (e.g. "do 026 up to plan"); otherwise `null`.

`start_phase` — for phase-level resume inside a stage (e.g. `Execute:phase=2.3`). Filled only when the trigger names a phase ("start from phase 2.3", "redo phase 2.3"); otherwise `null`.

`task_dir` — the resolved task folder, `Tasks/<STATUS>/<task_id>-*/`, without a trailing slash. The orchestrator already holds this path (it archives into it), and passing it explicitly is what keeps two agents from disagreeing about which folder they are working in. Required: a Method A script has no filesystem access and cannot glob for it, and refuses to start without it.

`lang` — the `<lang>` resolved by the Language Resolution section (`ru` | `en`; default `en`). Always filled. The subagent uses it for artifact **prose** and its final report; artifact **structure** stays EN regardless (see `conventions/i18n.md` → "Artifact authoring rule"). Passing it explicitly means workflow-* / subagents never re-read `CLAUDE-spine-toolkit.md` for output language.

`agents` — the role-to-agent map resolved in step 5.7. Always filled, always all nine roles, always in vocabulary order (`architect`, `developer`, `tester`, `reviewer`, `refactorer`, `validator`, `security`, `diagnostics`, `init`). Method B encodes it as the single line above; Method A passes the same object as real JSON, so a script reads `A.agents.architect` and gets `"fixture-platform:fixture-architect"` for the reference platform above. Keys are bare role names: the manifest's `role[axis=value]` form is resolved away in step 5.7 and never reaches the contract. A role the platform declared absent arrives as the em dash `—` in both encodings — a value a consumer checks for before dispatching, not a missing key, and the reason this field is never partial and never omitted. This is what lets a stage name its owner by role: which agent that role means is a property of the platform, not of the profile.

`walkthrough` — whether the run writes `Walkthrough.md`, and at what depth. Always filled, for every profile, so a consumer reads one shape rather than testing for the field first. Resolved `Task.md` `[WALKTHROUGH]` → `off` when `scale` is `lite` (the `scale` field below owns that step) → `CLAUDE-spine-toolkit.md` `[WALKTHROUGH]` → `deep`; a missing field is the default, not an error. Three values: `deep` writes what changed, a glossary, the commit order and a section per commit; `brief` writes what changed, a summary, the divergences and a one-bullet-per-commit log; `off` writes nothing. `on` is the pre-depth value and resolves to `deep` at the link that carries it, ahead of the rest of the chain. It declared whether, never how deep, so there is no prior depth to preserve — `on` used to produce what `brief` now produces, so a chain that still carries it writes more than it did, and the run announces that once with key `warn_walkthrough_pre_depth`. It reaches a config `/setup` migrated with the value untouched, or a `Task.md` written before the depths existed; a config nobody migrated never gets that far, because the resolver refuses the old format outright. Any other value is reported and skipped, and the chain carries on past it: a typo in the task's own field lands on the project's `[WALKTHROUGH]` where it names one, and only a chain that names no usable value anywhere lands on `deep`. The run announces the skipped value once with key `warn_walkthrough_unrecognised` (placeholder `{value}`), which says what was skipped and not what was written; a silent fallback would hide a typo in a project's config for as long as nobody compared two walkthroughs. It travels in the contract because the script itself gates on it — a Method A run has no filesystem access and cannot read the value for itself. Always `off` for `profile=review` and `profile=research`, where the profile has no implementing stage and no diff of its own; if the task file sets it anyway, say once that it was not executed and why, rather than dropping it silently.

`walkthrough_check` — whether a reader with none of the writer's context reads `Walkthrough.md` after each write that changed it, and the writer revises once from what that reader could not follow. Resolved by the same run of `resolve-settings.sh json`; `conventions/task-settings.md` holds the chain and how `auto` becomes a value. Always filled, for every profile, and only ever `on` or `off`: `auto` never reaches the contract, and wherever `walkthrough` is `off` this is `off` too. The protocol is `task-walkthrough` → `## Check`. It travels in the contract for the reason `walkthrough` does — a Method A script gates on it and has no filesystem to read it from.

`docs` — whether this run has any documentation to route. Resolved by asking `<core root>/scripts/docs-route.sh state <project root> --task-dir <task dir>`, which walks the same chain the mechanism itself walks, in order: the lever resolves like every other field — the task's own `[DOCS]` decides alone when it is present, in either direction; for a `.step/` folder the epic's `[DOCS]` reaches it next; failing both, the project's `[DOCS]` decides (`conventions/task-settings.md`); and only if the run is on at all does the answer depend on whether anything is declared, in the project's registry or in one at any external package root. A registry that exists but does not parse answers `on`, deliberately — the run then meets the error by name instead of skipping a registry someone meant to be read. It travels in the contract for the reason `walkthrough` does — a Method A run has no filesystem access and cannot read the value for itself. The script is the single authority on the answer; do not re-derive it by reading the config, because the check spans the project's registry and one at every external package root.

`scale` — how deep this task's pipeline goes. Resolved `Task.md` `[SCALE]` →
`CLAUDE-spine-toolkit.md` `[SCALE]` → `full`; a missing field is the default, not an error.
Always filled, for every profile: `review` and `research` accept it and ignore it, having no
implementing stage to make cheaper, and it is never omitted, so a consumer reads one shape rather
than testing for the field first. It travels in the contract for the reason `walkthrough` does — a
Method A script gates on it and has no filesystem to read it from. What the two values mean, which
three levers one value moves, and what the floor is at both: `conventions/task-scale.md`.

`scale` also moves the default under `walkthrough`, and loses to that field's own switch
(`conventions/task-scale.md` → Explicit beats the axis): the chain reads `Task.md [WALKTHROUGH]` →
`off` when `scale` is `lite` → `CLAUDE-spine-toolkit.md [WALKTHROUGH]` → `deep`.

**Receiving a raise.** A stage may return `scale_escalation: {to: "full", reason: "<what it
found>"}` — the ratchet of `conventions/task-scale.md`, which owns the two points it may fire at
and the four criteria for firing. On receiving one:

1. write `[SCALE] = [full]` into the task's `Task.md`, immediately after the `[NEED_REVIEW]` line —
   the same write-back `[RESEARCH_AGENT]` gets, and for the same reason: a rerun must not have to
   rediscover the finding;
2. announce it with key `scale_escalated` (placeholders `{stage}`, `{reason}`);
3. dispatch whatever is left of the range with `scale=full`.

Nothing is re-dispatched that is already running: a Method A script that raised the value mid-range
carried on at the new one and says so in its return, so step 3 covers only stages not yet started.
The raise is **never lowered**, at any point, by anyone.

Two cases write nothing. A run already resolved to `full` has nothing to raise. And `[SCALE] =
[full]` already in `Task.md` is the author's own decision: report the stage's finding, change no
file. Because the value lives in the file, a later `redo` of any stage runs at `full` as well — the
size belongs to the task, not to one dispatch.

`drive_app` — whether the Validation stage may drive the running app through the platform's own tooling. Resolved by the same run of `resolve-settings.sh json`; `conventions/task-settings.md` holds the chain and field table. Always filled, for every profile. `auto` leaves the choice to the profile, which each `workflow-*` skill states for its own Validation stage; `off` is the project saying it has nothing to drive. The Driver pre-flight (**Routing**, check 4) reads this field to decide whether it runs at all. A RESEARCH experiment reads it too: at `off` it drives nothing (`skills/workflow-research/SKILL.md` § 2c).

`manual_checks` — when the validator writes `ManualChecks.md`. Resolved by the same run of `resolve-settings.sh json`; `conventions/task-settings.md` holds the chain and field table. Always filled, for every profile. `auto` writes the file only for the checks the validator was told not to run itself; `always` writes it every time, even when the validator drove the app and covered the happy path.

`phase_verification` — how much each phase checks before it commits. Resolved by the same run of `resolve-settings.sh json`; `conventions/task-settings.md` holds the chain and field table. Always filled, for every profile. `proportional` leaves the full regression to Validation; `full` repeats it in every phase. The rungs themselves are `phase-verification`'s business, not this field's.

`security` — whether the security lens runs on a FEATURE, BUG or REFACTOR task. Resolved by the same run of `resolve-settings.sh json`; `conventions/task-settings.md` holds the chain and field table. Always filled, for every profile, and passed as resolved: `auto` reaches the contract, because what it becomes depends on what the task touches, and only the run's triage can find that out. `on` runs the lens without a triage; `off` runs neither. `scale` does not move it. The triage, the lens and what the writer does with them are the `security-lens` skill's.

`budgets` — the line ceiling of every artifact core measures. Resolved by running `<core root>/scripts/lint-artifact-budget.sh --budgets <task dir>`, which reads the script's defaults and the project's `[BUDGETS]` over them; the brace map it prints is this field. Always filled, for every profile, so a consumer reads one shape rather than testing for the field first. Method B takes that line as it is; Method A passes the same object as real JSON with integer values, so a script reads `A.budgets['Task.md']` and gets `100` by default. It travels in the contract for the reason `walkthrough` does — a Method A script names a ceiling in a brief and has no filesystem to read it from. The script is the one reader of `[BUDGETS]`: do not re-derive the map from the config. Each line the script reports on stderr as not recognized is announced once with key `warn_budget_unrecognised` (placeholder `{line}`); it forwards only the resolver lines about the ceilings it asked for, which is what makes every line it prints a budget line. Which artifact is measured at which scale is not this field's business: `conventions/task-scale.md`.

`models` — the model each dispatch runs on: a key for each of the eight roles the profiles dispatch, `light` for the calls whose work the script's own prompt defines, `walkthrough` for writing `Walkthrough.md`, and `done` for writing `Done.md`. Resolved by running `<core root>/scripts/resolve-settings.sh json <task dir>`, whose `models` field walks, key by key, `Task.md` `[MODELS]` → for a `.step/` folder, the epic's `Task.md` `[MODELS]` → `CLAUDE-spine-toolkit.md` `[MODELS]` → `sonnet` for `light` and `validator`, `session` for every other role and for `walkthrough` and `done`; that field is this field. Always filled, for every profile, `light`, `walkthrough` and `done` first and then the roles in vocabulary order without `init`, which no profile dispatches. Method B takes that map as it is; Method A passes the same object as real JSON, so a script reads `A.models.light` and gets `"sonnet"` by default. It travels in the contract for the reason `walkthrough` does — a Method A script sets each dispatch's model and has no filesystem to read it from. The script is the one reader of `[MODELS]`, in the config and in a task file alike: do not re-derive the map from the config. How a dispatch turns the map into a model is `conventions/stage-dispatch.md` → Model and effort. Each entry the script reports on stderr as not recognized is announced once with key `warn_tuning_unrecognised`, its placeholders filled from that line: `{source}` is the text before `: '`, `{entry}` the text between the quotes. This call is the one place a tuning warning is announced — no other script forwards one.

`effort` — the reasoning effort each dispatch runs at, a key for each of the same eight roles, `walkthrough` and `done`. Resolved by the same run of `resolve-settings.sh json`, over `Task.md` `[EFFORT]` → the epic's for a `.step/` folder → `CLAUDE-spine-toolkit.md` `[EFFORT]` → `session`; that field is this field. Always filled, for every profile, `walkthrough` and `done` first and then the roles in vocabulary order. Method B takes that map as it is; Method A passes the same object as real JSON. It travels in the contract, has one reader, and has what it cannot use announced exactly as `models` does. Only Method A can pass it per dispatch; what a Method B run says instead is in **Dispatch**.

`long_run` — how long a command a stage agent runs may stay silent (`stall`) and may run at all (`max`), in minutes. Resolved by the same run of `resolve-settings.sh json`; `conventions/task-settings.md` holds the chain and field table. Always filled, for every profile. The script hands both to every agent as the `--stall` and `--max` of `scripts/long-run.sh`, in seconds; Method A passes the object as real JSON, and Method B puts the same values, in seconds, in its dispatch prompt (`conventions/stage-dispatch.md`). When `stall` is not below `max`, the resolver's stderr line — `long_run: stall <n> is not below max <m>, the budget fires first` — is announced to the user as is; the values still apply as written.

`roots` — the folders a stage agent may search for a file, the core root aside: the project root, then every folder `## Paths` in `CLAUDE-spine-toolkit.md` names under `External packages` or `Roots`, absolute. Printed by the same run of `resolve-settings.sh json`; always filled, for every profile. Method A passes the list as real JSON, Method B names it in its dispatch prompt (`conventions/stage-dispatch.md`); either way it becomes the brief's `Search roots:` line, which `conventions/agent-tooling.md` → Finding files turns into a rule. Absent, the brief names only the project root and the core root and the run goes on: unlike a missing `plugin_root`, a shorter list narrows the search without breaking it.

`review_ranges` — what Review reads, per repository of the task, and what a `catch-up` validates: the JSON `task-ranges.sh ranges` printed in Resolution step 5.6, as described in `conventions/task-ranges.md`. `{}` when the range holds neither Review nor a catch-up, and for RESEARCH, REVIEW and EPIC. Method A passes the object as real JSON; Method B names each range in the Review stage's prompt (`conventions/stage-dispatch.md`).

`archive_paths` — list of paths to backups already created in `_archive/` for stages that will be overwritten (filled before handing off control). Format: `[path1, path2, path3]`. Empty list = `[]`. Method A passes it as a JSON array of strings.

**Invariant:** workflow-* never receives empty fields. If a field arrives empty — workflow-* returns an error to the orchestrator and does not try to recover.

**RESEARCH-only optional field — `research_agent`.** When `profile=research`, the orchestrator MAY include `research_agent=architect|diagnostics|security` in the args. The field carries a bare **role**, which workflow-research resolves through the `agents` map at dispatch like every other stage owner, mirroring how `[TASK_TYPE]` carries `FEATURE` rather than `spine-toolkit:workflow-feature`. Which of the three the role means on this platform is the platform's business, not the profile's. Resolution:

1. If `[RESEARCH_AGENT] = <value>` is present in `Task.md` (between `[NEED_REVIEW]` and section `## 1. [Files]`) → use that value.
2. Else, scan Task.md `## 2. [Description]` and `## 3. [Task]` for keywords:
   - keywords from locale key `research_agent_diagnostics_keywords` → suggest `diagnostics`
   - keywords from locale key `research_agent_security_keywords` → suggest `security`
   - none / ambiguous → suggest `architect`
3. In `manual` mode: AUQ using key `auq_research_agent_question`, listing the suggested role first with the locale-key suffix `auq_stage_recovery_recommended_suffix` appended to its label — same pattern used by the stage-picker (Resolution Algorithm § 5.5 / § 6). The remaining catalog options (`architect`, `diagnostics`, `security` minus the suggestion) follow in catalog order, plus a Cancel option using key `confirm_dispatch_cancel`. The user's pick is written back to `Task.md` under `[RESEARCH_AGENT] = [<value>]` so subsequent runs don't re-ask.
4. In `auto` mode: take the suggestion without asking.
5. For all other profiles: `research_agent` is omitted from the args (workflow-* would ignore it anyway).

**Validation.** The orchestrator does NOT validate the chosen role against the catalog `{architect, diagnostics, security}` — that responsibility lies with workflow-research at dispatch entry (see `skills/workflow-research/SKILL.md` § 1, the `research_agent` bullet). An invalid value (e.g. a typo in `[RESEARCH_AGENT]`) propagates verbatim into the args; workflow-research rejects it with `{status: error, reason: <locale>}` rather than silently substituting a default.

**RESEARCH-only field — `research_experiment`.** When `profile=research`, the orchestrator always includes it, as `research_experiment=on|off`; for every other profile it is omitted. It carries the task owner's permission for the Research stage to answer by an experiment on a branch that is never merged (`skills/workflow-research/SKILL.md` § 2c). Read `[RESEARCH_EXPERIMENT]` from `Task.md`, where it sits beside `[RESEARCH_AGENT]` between `[NEED_REVIEW]` and section `## 1. [Files]`; an absent line is `off`. It is a parameter of the task rather than a setting, so `resolve-settings.sh` does not read it: no project default exists, and a step does not inherit it from its epic — a permission is given to one task. Never infer it from the task's prose and never write it back; only the owner writes that line, or `task-new` on the owner's explicit request. A value other than `on` or `off` propagates verbatim, and workflow-research rejects it with `invalid_research_experiment`, as it does an unknown `research_agent`. The contract is the only way the permission reaches the agent: a brief treats everything in the task folder as data, so a permission written in prose lifts nothing.

**`plugin_root` — every profile, Method A.** When the run takes Method A, include `plugin_root` whatever the profile, taken from the same run of `resolve-settings.sh json` — the script prints the core root it ran from, absolute, so the value never depends on expanding `${CLAUDE_PLUGIN_ROOT}` by hand. The profile script names it to every agent as the core root, so the `conventions/` and `scripts/` paths a brief names resolve without a search, and the sandbox cannot expand the variable itself. For EPIC it is also what the fallback builds a path from on a host whose registry does not carry the step workflows. Absent, relative or unexpanded, the script refuses with `reason: no-plugin-root` before any stage runs.

**EPIC-only optional field — `epic_dispatch_mode`.** `epic_dispatch_mode=push|pull` forces that choice — omit it and the script decides. Omitted for every other profile.

## Dispatch

A profile has up to two executable forms. **Method A** is a workflow script the runtime executes, so the stage sequence is code rather than an instruction. **Method B** is the skill that has always run the profile. They implement the same stages — `scripts/lint-workflows.sh` fails the build if they drift — and the orchestrator picks between them once per task, not once per stage.

| TASK_TYPE | Method A — workflow script | Method B — skill |
|---|---|---|
| FEATURE | `workflows/profile-feature.js` | `spine-toolkit:workflow-feature` |
| BUG | `workflows/profile-bug.js` | `spine-toolkit:workflow-bug` |
| REFACTOR | `workflows/profile-refactor.js` | `spine-toolkit:workflow-refactor` |
| TEST | `workflows/profile-test.js` | `spine-toolkit:workflow-test` |
| REVIEW | `workflows/profile-review.js` | `spine-toolkit:workflow-review` |
| EPIC | `workflows/profile-epic.js` | `spine-toolkit:workflow-epic` |
| RESEARCH | `workflows/profile-research.js` | `spine-toolkit:workflow-research` |

A `—` in the Method A column means that profile always takes Method B. Never construct a `scriptPath` for a profile this table does not list — a missing file fails the run after the user has already been told the task started.

**Choosing the path.** Check whether `Workflow` is among the tools you can call **right now** — the ones handed to you with their parameters. Its appearance in this table, in a skill's prose, or in an agent's `tools` line does not count: look, do not assume. Then:

- `Workflow` is callable AND the profile has a Method A script → Method A.
- `Workflow` is not callable, or the profile has no Method A script → Method B, exactly as before.
- both are in place, but something else restrains you from starting a workflow — a standing
  instruction, a policy, a permission → the standing authorization in `conventions/stage-dispatch.md`
  covers it, because the user asking for this task to run is what that section is about. If it still
  does not, name the obstacle and ask with key `dispatch_blocked_prompt` (placeholder `{reason}`),
  options `dispatch_blocked_option_a` / `dispatch_blocked_option_b`. Never downgrade in silence: a
  Method B run chosen this way is indistinguishable from one that never had the workflow path.

State the choice **once** per task, using key `dispatch_method_a` or `dispatch_method_b`, inside the opening block that **Progress reporting** requires before the first dispatch. At `quiet` there is no opening block: state it in the final report instead. Not per stage.

Under Method B, when the contract's `effort` names any value other than `session`, add `warn_effort_method_b` (placeholder `{roles}`: those roles, comma-separated) to the same opening block, or to the final report at `quiet`, once per task. A Method B dispatch cannot carry an effort, so every stage runs at the session's (`conventions/stage-dispatch.md` → Model and effort).

**Method A — invoke.** The opening block goes out before this call, not after it: once the workflow is running, the feed shows a spinner and nothing about what is inside.

```
Workflow({
  name: "spine-toolkit:profile-<profile>",
  args: { <the Outbound Contract, as a JSON object> }
})
```

`name` rather than `scriptPath`: the host registers a plugin's `workflows/*.js` under `<plugin>:<meta.name>` and materializes the script itself, while a path into the plugin's own install directory is a file the session has no claim to read — Claude Code refuses it from 2.1.275, and the refusal lands in front of the user before the task has started. Two fallbacks follow, in order:

- The name does not resolve (`Workflow "…" not found`) — a host whose registry predates plugin workflows. Retry once with `scriptPath: "${CLAUDE_PLUGIN_ROOT}/workflows/profile-<profile>.js"`; if `${CLAUDE_PLUGIN_ROOT}` does not expand, resolve the core root the way `conventions/agent-tooling.md` describes and build the path from there.
- The path is refused too — Method B, and the run says so: the opening block has already gone out naming Method A, which makes this a deviation to declare under `conventions/stage-dispatch.md` → Declared deviation.

Pass `args` as a real JSON object. A JSON-encoded string arrives at the script as a string.

**Method A — manual mode.** A running workflow cannot ask the user anything. So `manual` mode dispatches **one workflow per stage**: `stage_scope=single` with `start_stage=<stage>`, wait for the result, run the usual post-stage gating (open-questions inspection, then `stage_done_prompt`), then dispatch the next stage. `auto` mode passes the whole range in a single call.

**Method A — reading the result.** The script returns the same Output Contract every `workflow-*` skill returns — `status`, `last_completed_stage`, `artifact_path`, `next_recommended_action`, `notes` — plus the stage status fields where they apply: `validation_status`, `review_status`, `reproducible`, `blocked_phase`. Gate on those fields rather than re-reading the artifact's first line. The first line is still written and still what a human reads; it is simply no longer the parsing surface.

The return also carries `stages[]` — one record per stage that finished, in order, each with
`stage`, `agent`, `ok`, `artifact_path`, `summary` and `status`. It is what makes a per-stage
report possible in `auto`, where a single return covers the whole range. Method B skills do not
return it and are not expected to: there the orchestrator drives each stage itself and already
has every field.

EPIC returns more: `branch`, `completed_steps`, `skipped_steps`, `failed_steps`, and `pending_steps`. A non-empty `pending_steps` is not a failure — it is the epic handing back the steps it could not run itself, in order. Dispatch each one as an ordinary task, then re-dispatch the epic at `start_stage=Done`.

RESEARCH with `research_experiment=on` also returns `experiment` whenever its Research stage ran — `status`, `branches`, `restored` and, when something went wrong, `reason`, as `skills/workflow-research/SKILL.md` § 2c defines them — and so does its Method B skill. `restored: false` comes back with `stop`: open the report with the checkout still on the experiment branch, before anything else. A `status` other than `done` comes back with `ask_user` before the next stage, in `auto` as well: ask whether to go on (to Review, or to Done when `need_review=false`), redo Research, or stop. In `manual` this question replaces `stage_done_prompt` for that stage.

**Method A — a stage whose role resolved to `—`.** The script neither dispatches nor skips it: it ends the range at that stage and hands it back. `handback` is **always present** in the return, `null` when nothing was handed back and `{stage: <stage>, role: <role>}` when something was — the same always-present shape as EPIC's `pending_steps`, so a consumer tests one field rather than distinguishing absent from empty.

With `handback` non-empty the script returns `status: ok` — a role the platform declared absent is a legitimate platform shape, not a fault — `next_recommended_action: ask_user`, and `last_completed_stage` set to the last stage that actually finished, which is `null` when the handed-back stage was the first in the range. `ask_user` is not a default, it is the only correct value, and it is what closes the two ways this can go wrong: `stop` reads as an ordinary finished range, so a consumer that does not know about `handback` silently drops the handed-back stage and every stage after it — the silent skip this whole design exists to prevent, reachable by omission; `continue` invites a consumer computing "next = `last_completed_stage` + 1" to land on the same stage and hand back forever.

On a non-empty `handback` the orchestrator runs that stage itself in the main context, announcing the deviation in the stage's first message with key `deviation_role_absent` (`conventions/stage-dispatch.md`), then re-dispatches the workflow from the following stage. The sandbox can report what it could not run; only the orchestrator can run it. Method B needs no hand-back — the skill runs the stage itself and makes the announcement.

`status: error` with `reason: no-args` means the contract never reached the script. Do not run the stage by hand and do not slide over to Method B as if nothing happened — say what happened, then re-dispatch with the contract filled. `reason: no-plugin-root` is the same stop for one field: re-dispatch with `plugin_root` as `resolve-settings.sh json` printed it.

**Method B — invoke.** Unchanged: invoke the `Skill` tool with the name from the table and `args` in Outbound Contract format.

## Progress reporting

`Progress` (Resolution Algorithm, step 3) governs reporting only. It never changes what runs,
and it never suppresses a question: the `manual` between-stage AUQ, the open-questions gate, and
commit confirmations behave identically at all three values.

**At `quiet`** — nothing beyond the final report that closes the range. Sending work to the
background still deserves one plain line saying a stage started; that line names no agent, no
method, no scope and no artifact, and it does not point at `/workflows`. Each of those belongs to
the opening block or the dispatch line, and `quiet` is the value that renders neither.

**At `normal` and above** — an opening block, once per task, before the first dispatch. Render
`progress_open_header` (`{method}` is the literal `Method A` or `Method B`), then the sentence
from `dispatch_method_a` / `dispatch_method_b`, then the stage-to-agent table, then
`progress_open_live_hint` for Method A only, `{workflow}` being the script's `meta.name`.

**The experiment line.** With `research_experiment=on` and a range that includes the Research
stage, render `research_experiment_announce`, `{branch}` being `experiment/<task>` as
`skills/workflow-research/SKILL.md` § 2c names it. It goes out at every `progress` value,
`quiet` included: it is a permission to change code, not progress. At `normal` and above it
follows the stage-to-agent table of the opening block; at `quiet` it is one line of its own
before the first dispatch.

Then, unless `settings_report` is `off`, the settings column: `progress_open_settings`, then the
`[FIELD] = [...]` lines of `bash "<core root>/scripts/resolve-settings.sh" show <task dir>` at
`diff`, or of `show <task dir> --all` at `full`. Drop the command's own trailing `# <n> more at
their default` line — that line is the script talking to whoever ran it directly, in English
regardless of `lang` — and render `progress_open_settings_rest` in its place, `{count}` filled
from the same number; `--all` never prints that line, so nothing renders there. At `diff` the
column names a field only where the value somebody chose is not the built-in default, so a project
left on the shipped template prints just two rows: `[SCALE]`, the one field whose shipped line and
absent-field default differ, and the `[WALKTHROUGH]` that a `lite` scale drags to `off` with it.

**Announcing what the resolver could not use.** Every such line is shaped `<source>: '<value>'
<what happened>`, `<source>` being `Task.md [FIELD]` or a config path and the same `[FIELD]`. The source
says which field, the text after the quotes which key:

| text after the quotes | source names | key |
|---|---|---|
| `is the pre-depth spelling, read as '<depth>'` | `[WALKTHROUGH]` | `warn_walkthrough_pre_depth` |
| `not recognized, skipped` | `[WALKTHROUGH]` | `warn_walkthrough_unrecognised` (`{value}`) |
| `not recognized, skipped` | `[BUDGETS]` | `warn_budget_unrecognised` (`{line}`) |
| `not recognized, skipped` | `[MODELS]` or `[EFFORT]` | `warn_tuning_unrecognised` (`{source}`, `{entry}`) |

Any other field has no key of its own: say in one sentence which field, which value, and that the
next source down applied. Each line is announced once per run, whichever call surfaced it — every
script that reads the resolver forwards only the lines about the fields it asked for, so the same
typo never arrives twice under two different names.

Under Method A, every `Workflow` call is then preceded by `progress_dispatch` — the one per stage in
`manual`, the single one in `auto`, and any re-dispatch after a hand-back or a retry. `{range}` is
what that call covers: one stage, or `<start> → <end>`. The host lists each run by `meta.name`
alone, so a `manual` task fills `/workflows` with identical rows; this line is what ties a row to
its stage.

The table's agent column comes from `meta.phases[].agent` in `workflows/profile-<profile>.js`.
Read that file's `meta` block — it is the same file that dispatches, and a second copy of the map
in this skill would drift from it. Method B reads it too: the Workflow tool is absent there, but
the file is on disk.

Then, after each stage: `progress_stage_report`, plus `progress_stage_artifact` where the stage
wrote one, plus the agent's own one-or-two-sentence summary, plus `progress_stage_verdict` where
the stage carries a verdict.

**Metrics — Method A only.** Method B has no `runId` to pass, so this whole block does not
apply there: under Method B the orchestrator prints no metrics line and no totals line.

At `live`, after the stage report, run

```
bash "${CLAUDE_PLUGIN_ROOT}/scripts/agent-metrics.sh" --format json --run <runId>
```

and render `progress_stage_metrics` from the entry in `phases[]` whose `title` equals the stage
just reported — it folds every agent the stage ran, its read-plan, walkthrough,
walkthrough-check and walkthrough-revise calls included.
Fill `{tuning}`, `{out}`, `{ctx}`, `{cacheWrite}`, `{cacheRead}`, `{tools}` and `{elapsed}` from
that entry's `tuningText`, `outText`, `ctxText`, `cacheWriteText`, `cacheReadText`, `tools` and
`elapsedText` — the ready-to-print strings where the script gives one, never from the raw `out`,
`ctx`, `cacheWrite`, `cacheRead` and `elapsedMs` numbers beside them; `{elapsed}` is the time
its agents worked, summed. At `quiet` and `normal` the script is not run at all — those two values
behave exactly as they did before the metrics line existed.

The call is best-effort: a non-zero exit or unparseable output means the stage report is
printed without the metrics line and nothing else changes.

In `manual` the source is the single-stage return, printed before `stage_done_prompt`. In `auto`
the source is `stages[]` from the one return, printed as consecutive entries.

At `live`, after the range closes, make ONE call —

```
bash "${CLAUDE_PLUGIN_ROOT}/scripts/agent-metrics.sh" --format json --task <task_id>
```

— and render `progress_run_totals` from that document's `totals`. The script folds a task's runs
together on its own, so this is the same instruction in `auto` and in `manual`: no accumulation,
no summing `totals.agents`/`totals.out`/`totals.elapsedMs` across a `--run` per stage by hand.
Fill placeholders from the print-ready `*Text` strings, never from the raw numbers beside them —
same rule as `progress_stage_metrics` above.

Then render `progress_run_volume`, immediately after `progress_run_totals`, from the same `totals`
object.

**At `live`** — additionally append `progress_open_live_ticker_note` to the opening block under
Method A, rendered with `{script}` (the absolute path to `scripts/agent-monitor.sh`, built from
`${CLAUDE_PLUGIN_ROOT}`) and `{session}` (`$CLAUDE_CODE_SESSION_ID`), and
`progress_open_method_b_live` under Method B.

**Timing.** The elapsed figure comes from the Workflow tool result, not from the script — the
sandbox has no clock. In `manual` one call is one stage, so it is that stage's time — and the host
already prints it above the stage report, so do not repeat it. In `auto` it
covers the whole range and is printed once, via `progress_run_elapsed`, at the end. Per-stage
durations inside an `auto` run do not exist; do not invent them.

## Gating

**Manual** (default) — pause after each stage with an AUQ (use key `stage_done_prompt` with placeholder `{stage}`) confirming the move to the next; discussions that don't fit in a single reply are recorded in the task's `Questions.md`.

**Auto** — no pauses between stages.

**Error mid-range.** A stage that returns `status: error` ends the range where it stands, in `auto`
as much as in `manual`. `auto` means no pause between stages that *succeeded*; carrying on past a
failure would build the next stage on a foundation that is not there.

Report the stage, the reason, and whatever artifacts did get written, then AUQ with key
`stage_error_prompt` (placeholders `{stage}`, `{reason}`). `stage_error_option_retry` re-dispatches
that one stage with `stage_scope=single`; `stage_error_option_stop` returns control with `status:
error` and `last_completed_stage` set to the last stage that actually finished — not the one that
failed.

Two things deliberately do NOT happen on this path. The status-driven auto-move to `DONE` does not
fire: it reads the verdict on the first line of `Review.md`, and a run that stopped earlier never
wrote one — no verdict, no move. And the `_archive/` backups taken before dispatch are left in
place; they exist for exactly this case, and clearing them would remove the rope at the moment
someone reaches for it.

**Open-questions inline (research-style stages).** In `manual` mode, before rendering `stage_done_prompt`, the orchestrator inspects the just-completed stage's primary artifact (`Research.md` in every profile — the research-style stage writes that name whatever the stage is called — plus `Reproduce.md` for BUG) for non-empty open-question sections.

Recognized H3 section titles (case-insensitive, scoped under any H2):
- `### Designer questions`
- `### Backend questions`
- `### Known unknowns`
- `### Open questions`

Per-item rule: a bullet (`- ` or `* `) counts as open if it does NOT start with `[RESOLVED]` or `[DEFERRED]` after the bullet marker. The orchestrator collects open items as `{section, id_or_text}` pairs (id = leading token like `D1`, `U7`, `R3` when present; otherwise first 80 chars of the item text).

If at least one open item is found → render `stage_done_prompt_with_questions` instead of `stage_done_prompt`, with placeholders `{stage}` and `{questions}` (the formatted list of open items, grouped by section). AUQ options:

1. `stage_done_option_continue` → proceed to next stage; open items propagate untouched (will hit Plan-stage estimation-gate later if blocking).
2. `stage_done_option_resolve` → enter Q-by-Q resolution dialog (see below).
3. `stage_done_option_edit` → instruct the user to edit the artifact manually; on return, re-run open-questions inspection from scratch.
4. `confirm_dispatch_cancel` → return `{status: cancelled, reason: status_cancelled_user_no}`.

If no open items found → render the unchanged `stage_done_prompt`.

**Q-by-Q resolution dialog.** For each collected open item, in source order, AUQ using `stage_done_dialog_question` (placeholders `{n}`, `{total}`, `{section}`, `{text}`) with options:
1. `stage_done_dialog_answer` → prompt the user for free-form text; append the answer as a sub-bullet under the original item and prefix the original bullet with `[RESOLVED]`.
2. `stage_done_dialog_defer` → prefix the original bullet with `[DEFERRED]`; no answer recorded.
3. `stage_done_dialog_skip` → leave item untouched.
4. `confirm_dispatch_cancel` → abort the dialog; return to the `stage_done_prompt_with_questions` AUQ with the (possibly partially) updated list.

Edits land in the primary artifact in-place; an `## Open Questions Log` section is appended to `Questions.md` (created if absent) with one bullet per resolved or deferred item, format: `- [<stage>] [<section>] <id_or_text> — <RESOLVED: answer | DEFERRED>`.

After the dialog finishes (all items processed OR user aborted), re-run the open-questions inspection on the updated artifact and re-render `stage_done_prompt_with_questions` until either zero open items remain or the user picks `stage_done_option_continue` / `confirm_dispatch_cancel`.

**Scope:** the inspection runs ONLY at stage-done boundaries that produce a research-style artifact. It does NOT run after Plan / Execute / Validation / Review / Done. The `workflow-*` Output Contract is unchanged — open-questions handling is entirely orchestrator-side and does not require new fields in `next_recommended_action`.

**Artifact budget.** After a stage returns, and before rendering `stage_done_prompt`,
measure the task folder: run `<core root>/scripts/lint-artifact-budget.sh <task_dir>`, the core root
being the directory that holds `workflows/` (`conventions/agent-tooling.md` → Plugin Roots And
Templates). Without a flag it measures a `lite` task's own artifacts, and exits 0 at `full`, on a
profile with no implementing stage, and on a `lite` task inside its ceilings. After the Plan stage of
an EPIC that chose decomposition, add `--task-docs`, at any scale: it also measures the `Task.md` of
every step not yet started — `[STATUS]` PENDING, as that stage writes them — its ceiling and its three
anchors (`skills/task-documents/SKILL.md`). A step that has started or closed is not measured: its
`Task.md` is already the record of what ran. A non-zero exit prints one line per finding.

Measure rather than instruct: a count limit published in a brief and never checked is the class of
directive this toolkit has already watched go unobserved, which is why the ceilings live in that
script and not in a sentence (`conventions/task-scale.md`).

On a non-zero exit, report each line over a ceiling with key `budget_over_limit` (`{artifact}`, `{actual}`,
`{cap}`) and re-dispatch that artifact's own stage owner **once**, asking for a trim only — no new
findings, no re-investigation, no change to any verdict line. If it is still over after that one
pass, report it and carry on. A long artifact is a cost, not a failure, and a trim loop would spend
more than the prose does.

A step's `Task.md` goes back to the architect the same way, once: over its ceiling, with key
`budget_over_limit`, asking to move mechanics into `### Questions for Research` and drop what
retells the epic's research — never a requirement; an anchor missing, empty or a bare dash, with key
`task_doc_anchor_missing` (`{step}`, `{anchor}`), asking to fill it or to write `— <reason>` where it
does not apply.

In `auto` on a Method A range the whole range returns at once: run the same measurement then, once,
over what the range wrote. An EPIC range holding both Plan and Execute is dispatched as two calls
instead — the first with `end_stage=Plan`, the second from Execute — and the `--task-docs`
measurement runs between them: measured after the range, a step would already have run on the
`Task.md` the measurement exists to fix. The second call continues the same run: `start_stage=Execute`,
`stage_scope=forward`, no new archiving, and no second opening block.

**Artifact language.** At the artifact budget's boundaries — after a stage returns and before
`stage_done_prompt`, or once when an `auto` Method A range returns, over what the range wrote — run
`<core root>/scripts/lint-artifact-lang.sh <task_dir>`. It reads `lang` through `resolve-settings.sh`
and measures the prose of the task folder's own artifacts; which files, what counts as prose and
where a finding starts are `conventions/artifact-language.md`'s. When a REVIEW result reports
`moved-to-done` (`action_taken` under Method A, `moved-to-DONE` in the notes under Method B), the
folder has moved: run the check at the task's new `Tasks/DONE/<folder>` path. After an EPIC Method A
range, name in the same call the folder of every step the range ran, completed or failed:
`<task_dir>/<step_id>` for each entry of `completed_steps` and `failed_steps`, `step_id` being the
step folder's own name, `.step` suffix included. Exit 0 reports only what the script printed on
stderr, if anything. Exit 2 is reported as the script printed it, and the run carries on.

On exit 1, act only when the `(lang …)` the findings end with is the contract's `lang`. The two are
separate readers of `[LANG]`; when they disagree, report it once with key `lang_readers_disagree`
(`{measured}`, `{lang}`) and send nothing. Otherwise report each finding with key `lang_mismatch`
(`{artifact}`, `{section}`, `{lang}`), then send each file it names back **once** to the role whose
call writes it — for a file in a step folder, the column its own `Task.md` `[TASK_TYPE]` names:

| Artifact | FEATURE | BUG | REFACTOR | TEST | EPIC | RESEARCH | REVIEW |
|---|---|---|---|---|---|---|---|
| `Research.md` | architect | architect | architect | tester | architect | `research_agent` | — |
| `Reproduce.md` | — | diagnostics | — | — | — | — | — |
| `Plan.md` | architect | architect | architect | tester | architect | — | — |
| `Validation.md`, `OpsChecklist.md`, `ManualChecks.md` | validator | validator | validator | validator | — | — | — |
| `Review.md`, `ChangesRequested.md` | reviewer | reviewer | reviewer | reviewer | — | reviewer | reviewer |
| `Walkthrough.md` | architect | developer | refactorer | tester | architect | — | — |
| `Done.md` | architect | developer | refactorer | tester | architect | architect | reviewer |
| `Docs.md` | developer | developer | refactorer | tester | architect | — | — |

A `—` owner, whether a `—` cell above or a role the `agents` map resolved to `—`, sends nothing: the
finding is reported with key `lang_mismatch_unowned` (`{artifact}`, `{section}`, `{lang}`) instead.
A file already sent back in this run is not sent again: a later boundary reports its findings with
key `lang_mismatch_persists` instead.

The role resolves through the contract's `agents` map, on the model of the call that writes the file
(`conventions/stage-dispatch.md` → Model and effort: kind `walkthrough` for `Walkthrough.md`, `done`
for `Done.md`, `mechanical` for what REVIEW's `auto-move` writes — its `Done.md` and
`ChangesRequested.md` — and `stage` for the rest); the effort is the
session's, since this dispatch takes none. The brief names the language in words and asks for one
thing: the prose of the named sections rewritten in it. Headings stay as they are, except a title the
artifact's own skill calls prose, such as a manual check's case title; field labels, status words,
code, identifiers, paths, commit subjects and quoted logs and messages stay as they are too; no new
finding, no re-investigation, no change to any verdict line. Then run the script again. A finding
still there is reported with key `lang_mismatch_persists` (`{artifact}`, `{section}`) and the run
carries on — a second round would cost more than the file is worth to the run, and the finding stays
in front of the user. Run this script and the budget's both before sending either rewrite; when both
name one file, the language goes first: a trim is easier in the language the file keeps.

**Per-phase commits vs flow-level commits.** The "commit always confirmed with user" rule applies ONLY to flow-level wrap commits the orchestrator itself initiates (squash, merge, push) — these are user-confirmed regardless of mode. **Per-phase commits inside a workflow-* multi-phase stage (Refactor / Execute / Fix / Write) are autonomous** — the workflow-* skill creates one commit per green phase without a user prompt, in both manual and auto modes. The orchestrator MUST NOT misread "does not confirm commit with user" inside workflow-* skills as "does not commit at all"; per-phase commits are mandatory for the phase invariant ("each phase independently buildable+test-passing+committed") to hold against interrupts.

**Backup before overwriting / removing an artifact:** copy to `Tasks/<STATUS>/<task_id>-*/_archive/<stage>-<timestamp>.md`, where `<timestamp>` is ISO-8601 without colons (`2026-04-25T143022`). The orchestrator makes the backup BEFORE calling workflow-* and passes the paths via `archive_paths` in the outbound contract.

In `manual` mode, a structured confirmation is mandatory before the backup / removal.

## Stage Management

Triggers (free-form, parsed into `action` + `stage_target`):

| User text | action | stage_target | stage_scope |
|---|---|---|---|
| "run 026" / "do 026" / "execute 026" | `run` | null | `forward` (from the state-detection point) |
| "continue 026" | `continue` | null | `forward` |
| "do 026 up to plan" | `run` | null (`end_stage=Plan`) | `forward` (capped at the top) |
| "only plan for 026" / "only research for 026" | `run` | `<stage>` (`end_stage=<stage>`) | `single` |
| "start from Plan for 026" | `run` | `Plan` (as `--from`) | `forward` |
| "redo plan for 026" | `redo` | `Plan` | `single` |
| "start from phase 2.3 for 026" | `run` | `<stage>:phase=2.3` | `forward` (from the phase anchor) |
| "redo phase 2.3 for 026" | `redo` | `<stage>:phase=2.3` | `single` (at the phase level) |
| "rerun validation for 026" | `redo` | `Validation` | `single` |
| "start over for 026" | `restart-full` | null | `all` |
| "catch up 026" | `catch-up` | null | `forward` |

> Note on the semantics of "rerun": `rerun <stage>` = `redo` of a single stage (an atomic redo). Do not confuse it with `restart`, which resets `<stage>` AND every subsequent stage. The user verb "rerun" here is closer in meaning to "redo atomically" than to "reset and walk through to the end again".

Action and archival semantics:

| Action | Semantics | What gets archived in `_archive/` | Where it starts |
|---|---|---|---|
| `run --from <stage>` | Skip previous stages | nothing | from `<stage>` |
| `redo <stage>` | Redo one stage | `<stage>` artifact | from `<stage>`, after = untouched |
| `restart <stage>` | Reset and rerun from stage to end | `<stage>` and all subsequent | from `<stage>` to end of profile |
| `restart-full` | Full reset | all artifacts (a RESEARCH task's `experiment/` stays in place) | from the profile's first stage |
| `catch-up` | Validate, review and close the commits after Done | `Review.md`, `Done.md` | from `Validation` to the end |

A `catch-up` of a task in `Tasks/DONE/` first moves it back to `ACTIVE/` the way `/task-move` does — before any backup is taken, so `archive_paths` name files under `ACTIVE/` — and moves it back into `DONE/` once the run returns with `Done` completed. A catch-up stopped at `CHANGES_REQUESTED` is resumed after the fixes with `catch-up` again, not with a bare `redo Review` or Done, so the "Catch-up: commits after Done" phase is written and the task moves back into `DONE/`.

**All redo / restart operations in manual mode require a structured confirmation BEFORE archiving.**

Command validation:
- "only Plan" / "start from Plan" without `Research.md` (for profiles that have a preceding `Research`) → error using key `error_research_required` with placeholder `{stage}`.
- "redo <stage>" with no `<stage>` artifact present → error using key `error_redo_no_artifact` with placeholder `{stage}`; suggest `run --from <stage>`.
- An out-of-profile stage name → handled centrally in Resolution Algorithm step 5.5 (manual: stage picker; auto: hard error using key `error_stage_not_in_profile`).

## Subagent Context

The workflow-* subagent receives:

1. The full text of the task's `Task.md` (as is).
2. A short summary of previous stages (1–3 paragraphs): what was done, key decisions, open questions. Pulled from the most recent artifacts (`Research.md`, `Plan.md`).
3. Stack: the `stack` value from the Outbound Contract.
4. Mode: `mode` from the Outbound Contract.
5. Lang: the `lang` value from the Outbound Contract (resolved once via the
   Language Resolution section). The subagent writes artifact **prose** and its
   final report in `lang`; artifact **structure** (headings, field labels,
   status enums) stays EN. See `conventions/i18n.md` → "Artifact authoring
   rule". Passing `lang` explicitly means the subagent never re-reads
   `CLAUDE-spine-toolkit.md` to decide output language. Name it in words —
   `English`, `Russian` — at the start of the prompt and again as its last
   line: a code on one line of a long English prompt is the line an agent loses.
6. Agents: the `agents` map from the Outbound Contract — the role-to-agent
   binding each stage dispatches through.

**The stack does not need to be re-sent in full text:** the skill does not read `CLAUDE-spine-toolkit.md` — stack, mode, and paths come from the context the active agent host typically loads at session start (when `CLAUDE.md` is present at the project root and imports `CLAUDE-spine-toolkit.md` via `@./`). The orchestrator parses this already-loaded context to resolve priorities.
