# Configuration

`CLAUDE-spine-toolkit.md` in the project root is the toolkit's own configuration. `spine-toolkit:setup`
creates and updates it and `/lang` rewrites one field of it; your own project instructions stay in
`CLAUDE.md`, which the toolkit only ever touches to insert the import line. The template it is
rendered from is [`../templates/claude-toolkit-md/en.md`](../templates/claude-toolkit-md/en.md).

Every setting a run resolves is one `[FIELD] = [value]` line — the same grammar a task's `Task.md`
uses for its own fields, and a line commented out with `#` is documentation, never a value. This
page is one section per field, in the order the template writes them.

## The chain

A run resolves each field by walking one chain, first hit wins:

```
Task.md  →  the epic's Task.md for a .step/ folder  →  the nearest CLAUDE-spine-toolkit.md  →  the default
```

A missing field is the default, not an error: nothing stops because a setting was left unwritten. An
unrecognized value is named on stderr and the chain continues past it, so a typo in a task lands on
the project's choice rather than on the built-in default. `[PROGRESS]` is the one field whose bad
value is skipped in silence — the settings column prints what it resolved to, so the mismatch with
the file is visible already.

[`../conventions/task-settings.md`](../conventions/task-settings.md) is the normative statement of
the chain — including the one extra step `[WALKTHROUGH]` inserts into it — and
`scripts/resolve-settings.sh` is its only implementation. To see what a given task actually resolves
to, run `scripts/resolve-settings.sh show <task-dir> --all`.

## The two blocks

**`## Project settings`** is what a task cannot change. No `Task.md` is read for these seven fields:
the config's line, or the default, is the answer.

**`## Task defaults`** is what a task can change, by writing the same field into its own `Task.md`.
The config's line is the project's default for these twelve fields, and the task's own line beats it.

Every other block of the file — `## Persona`, `## Rules`, `## Platform`, `## Agents`, `## Stack`,
`## Modules`, `## EstimationDeltas`, `## DeliveryMode`, `## AILeverage`, `## Paths`,
`## Orchestration` — is read by a skill for its own purposes and holds no resolved field. One
exception feeds every task: the folders `## Paths` names under `External packages` and `Roots`,
with the project root, are the only places a stage agent may search for a file.

## Project settings

### [LANG]

**Values:** `en` `ru` · **Default:** `en` · **Task override:** no · **Defined by:**
[`../conventions/i18n.md`](../conventions/i18n.md)

The language the toolkit writes prose in — every sentence an agent composes, in an artifact or in a
message. Structure stays English at either value: headings, field names and status words are what
skills parse, and they must survive a mid-project switch. The field is found by its name anywhere in
the file, and `/lang en|ru` is what rewrites it.

### [PROGRESS]

**Values:** `quiet` `normal` `live` · **Default:** `normal` · **Task override:** no ·
**Defined by:** the `orchestrator` skill

How much the orchestrator narrates a profile run: `quiet` — the final report only; `normal` — the
stage-to-agent plan once, then a report after every stage; `live` — everything from `normal` plus
each stage's token cost, a totals line when the run finishes, and the command for a live agent panel
you can run in a second terminal pane.

### [SETTINGS_REPORT]

**Values:** `diff` `full` `off` · **Default:** `diff` · **Task override:** no · **Defined by:** the
`orchestrator` skill

How much of what the run resolved the settings column prints: `diff` — the fields this task or this
project chose a value for that is not the built-in default (a line that writes the default down
again is not a choice this run has to report), `full` — every field, `off` — none. The full list is
one `scripts/resolve-settings.sh show <task dir> --all` away at any time.

This field governs reporting only — the between-stage confirmations of `manual` mode are unaffected
by it.

### [BUDGETS]

**Values:** `<artifact>: <lines>` entries, comma-separated · **Default:** the `CAPS` table in
`scripts/resolve-settings.sh` · **Task override:** no · **Defined by:**
`scripts/lint-artifact-budget.sh`

Optional: per-artifact line ceilings overriding the defaults, for example
`[BUDGETS] = [Task.md: 120]`. The artifacts are a step's `Task.md`, measured at every scale, and
`Reproduce.md`, `Plan.md`, `Validation.md`, `Review.md`, `Done.md`, measured on a `lite` task. An
entry here moves a number, never which scale an artifact is measured at. Change a ceiling when a
measurement of this project's documents says the default does not fit, not when the lint turns red:
a ceiling raised to silence the lint measures nothing. A name the lint does not know, or a value
that is not a positive whole number, keeps the default and is reported.

### [DOCS_MAP]

**Values:** a path, relative to the project root · **Default:** `DocsMap.md` · **Task override:** no
· **Defined by:** the `docs-route` skill and
[`../conventions/docs-components.md`](../conventions/docs-components.md)

Where the registry of this project's documentation components lives. The file is optional: without
it the mechanism is off and the run says nothing about documentation. What goes inside the registry
is fixed by the skill and the convention, not by this field — the same division `[MANUAL_CHECKS]`
has with `ManualChecks.md`.

### [DOCS_STRICTNESS]

**Values:** `blocking` `advisory` `off` · **Default:** `advisory` · **Task override:** no ·
**Defined by:** the `docs-route` skill

The default for a component that declares none: `blocking` — a phase does not close while the
question a touched component raises is unanswered; `advisory` — the run names it and moves on;
`off` — the component is routed and reported but never asked about.

### [DOCS_FRESHNESS]

**Values:** `on` `off` · **Default:** `on` · **Task override:** no · **Defined by:** the `docs-route`
skill

Whether a component's files carry the Status / Synced / Owner / Source of truth header.

## Task defaults

### [WORKFLOW_MODE]

**Values:** `manual` `auto` · **Default:** `manual` · **Task override:** `[WORKFLOW_MODE] = [manual|auto]`
· **Defined by:** the `orchestrator` skill

Whether the run stops between stages. `manual` dispatches one stage at a time and gates on the
user's confirmation before the next; `auto` passes the whole stage range in a single call and takes
each suggestion without asking. Per-phase commits inside an implementing stage are autonomous at
either value — the mode governs the stage boundary, not the commit.

### [SCALE]

**Values:** `lite` `full` · **Default:** `full` · **Task override:** `[SCALE] = [lite|full]` ·
**Defined by:** [`../conventions/task-scale.md`](../conventions/task-scale.md)

How deep a task's pipeline goes. `lite` — investigation folds into the artifact that consumes it,
each artifact carries a line ceiling, and no estimation section or ops checklist is produced;
`full` — every stage gets its own agent and its own artifact. The floor is identical at both values:
one commit per green phase, a reproduction before a bug fix, a Validation stage with its own agent,
and a Review stage with an independent one. `lite` is cheaper, not looser.

A `lite` run can be raised to `full` once — by the stage that first measures the perimeter, or by
the planner — and is never lowered; the raise is written back into the task's `Task.md`.
`[SCALE] = [full]` in a `Task.md` also switches the raise off, the author having already decided.

A project without this field runs `full`, which is what every project did before the setting
existed. The template ships `[SCALE] = [lite]`, so a project newly set up from it runs `lite` — the
one field whose shipped line and absent-field default differ, and they differ on purpose: `lite` is
what a new project is given, while a config that never named the setting was already running `full`.

### [DRIVE_APP]

**Values:** `auto` `off` · **Default:** `auto` · **Task override:** `[DRIVE_APP] = [auto|off]` ·
**Defined by:** the platform's validator and
[`../conventions/driver-contract.md`](../conventions/driver-contract.md)

Whether the Validation stage may drive the running app through this platform's own tooling: `auto` —
the profile decides (FEATURE: when the feature has a UI layer; BUG: always, to replay the
reproduction; REFACTOR: when UI code was touched; TEST: only for UI tests); `off` — never, because
this project has nothing to drive or no way to drive it. A platform whose validator has no such
tooling at all declares the deviation itself; this field is for the project's own choice.

`off` does not delete the check: the validator writes the cases a human has to run into a separate
`ManualChecks.md` in the task folder and marks the matching `OpsChecklist.md` items Pending. For BUG
the deferred check is the reproduction replay itself.

### [MANUAL_CHECKS]

**Values:** `auto` `always` · **Default:** `auto` · **Task override:**
`[MANUAL_CHECKS] = [auto|always]` · **Defined by:** the `manual-checks` skill

When the validator writes `ManualChecks.md`, the hand-run script for a human: `auto` — only for
checks it was told not to run itself; `always` — every time, so a UI-bearing task ships a manual pass
even when the validator drove the app and covered the happy path. What goes inside that file is
fixed by the `manual-checks` skill, not by this field.

### [DRIVER]

**Values:** a driver-plugin name, `auto`, `—` · **Default:** `auto` · **Task override:**
`[DRIVER] = [<driver-plugin>|auto|—]` · **Defined by:**
[`../conventions/driver-contract.md`](../conventions/driver-contract.md)

Which driver plugin drives the running app: `auto` — the driver this platform recommends, which is
what keeps a project that never touched this field behaving as it always did; a plugin name — that
one instead of the recommendation; `—` — none at all. `—` is a deliberate choice, not a failure: the
checks that needed driving are handed to a human exactly as `[DRIVE_APP] = [off]` hands them over,
and the verdict is not lowered. What a driver can and cannot do is its own declaration, and what it
cannot do becomes a manual check automatically.

This field is the orchestrator's pre-flight concern alone: it never rides the Outbound Contract, so
no workflow script gates on it.

### [PHASE_VERIFICATION]

**Values:** `proportional` `full` · **Default:** `proportional` · **Task override:**
`[PHASE_VERIFICATION] = [proportional|full]` · **Defined by:** the `phase-verification` skill

How much each phase checks before it commits: `proportional` — only what the phase can break, at the
rung its `**Verification:**` line in `Plan.md` names, with the full regression left to Validation;
`full` — the full regression in every phase, for a project whose whole suite is cheap enough that
repeating it costs nothing. There is no `off`. The rungs and how a planner picks one are fixed by
the `phase-verification` skill, not by this field.

### [FIX_ROUNDS]

**Values:** a whole number ≥ 0 · **Default:** `2` · **Task override:** `[FIX_ROUNDS] = [<n>]` ·
**Defined by:** the orchestrator's Gating

How many rounds of `fix-review` a run in `auto` starts by itself after Review returns
`CHANGES_REQUESTED`: each round fixes the findings as one plan phase, validates, reviews the new
commits and closes. When the rounds are spent, the orchestrator stops and asks. The count starts
over after every Done, so a later `catch-up` gets rounds of its own. `0` turns the automatic loop off. `manual` always asks, whatever the value.

### [WALKTHROUGH]

**Values:** `brief` `deep` `off` · **Default:** `deep`, and `off` when `scale` resolves to `lite` ·
**Task override:** `[WALKTHROUGH] = [brief|deep|off]` · **Defined by:** the `task-walkthrough` skill

Whether a task writes `Walkthrough.md`, and at what depth. The artifact is the human-facing account
of what actually landed, written for an engineer who did not write the code and was not on the task.
Written at the end of the implementing stage, so it is readable before Validation and Review, and
refreshed afterwards if later commits moved past it. `deep` and `brief` both carry diagrams where
they help and follow-ups; the difference is below.

`deep` — what changed, each change before and after on one concrete case; then a glossary of the
terms it uses, the commit order and why, and a section per commit: what appeared, the failure it is
written against, how that is closed, which alternative was rejected. This is the value that makes the
file worth opening a year later, and it is the default.

`brief` — what changed, one line per change; then a summary, divergences and a one-bullet-per-commit
log, for a reader who already knows the area.

`off` — never written.

`on` is the pre-depth value and is read as `deep` — more than it used to write; a project that wants
the old shape says `brief`.

Not applicable to RESEARCH and REVIEW, whose deliverable is the artifact itself. A `lite` task writes
nothing unless it says otherwise: the project's own line is read *after* the `lite` gate and cannot
out-rank it, while the task's own `[WALKTHROUGH]` is read before it and wins outright.

### [WALKTHROUGH_CHECK]

**Values:** `auto` `on` `off` · **Default:** `auto` — `on` at `deep`, `off` at `brief` ·
**Task override:** `[WALKTHROUGH_CHECK] = [auto|on|off]` · **Defined by:** the `task-walkthrough`
skill, `## Check`

Whether `Walkthrough.md` is read back by a reader with none of the writer's context, and revised
once from what that reader could not follow. The reader is a fresh agent of the writer's role that
opens the file and nothing else. It retells every item of `## What changed` and names each place it
had to guess; an empty list ends the check, otherwise the writer fixes the places named. One round,
and the run notes how many places there were.

`auto` follows the depth `[WALKTHROUGH]` resolves to: `on` at `deep`, `off` at `brief`. `on` checks
a `brief` file too; `off` never checks. Where `[WALKTHROUGH]` resolves to `off` — a `lite` task
included — nothing is checked, whatever this field says. The check costs one `light` dispatch per
write that changed the file, and one more writer dispatch when it finds something.

### [SECURITY]

**Values:** `auto` `on` `off` · **Default:** `auto` · **Task override:** `[SECURITY] = [auto|on|off]` ·
**Defined by:** the `security-lens` skill

Whether a FEATURE, BUG or REFACTOR task gets the security lens: one look at what the task adds or
changes that an attacker can reach, before its code is written. `auto` asks a `light` triage first
and runs the lens only when the task touches credentials, the network, stored data, an external
entry point, authentication, personal data, permissions or a third-party dependency; `on` runs it
on every task, `off` on none. `scale` does not move it: a `lite` task that touches any of these gets
the lens, and a `full` one that touches none of them does not. The triage costs one `light`
dispatch, the lens one dispatch of the `security` role.

### [DOCS]

**Values:** `on` `off` · **Default:** `on` · **Task override:** `[DOCS] = [on|off]` · **Defined by:**
the `docs-route` skill

Whether the documentation mechanism runs at all. `off` in the config suspends it project-wide: the
four commands a run invokes do nothing and say nothing, while `registry` still reads the file, so a
suspended project can still inspect what it suspended. A task that names `[DOCS]` explicitly
overrides the project in either direction, and names the components it creates in `[DOCS_NEW]` — a
`Task.md` field with no config counterpart, since a project does not create a task's components for
it.

### [MODELS]

**Values:** `<key>: <value>` entries, comma-separated; keys `light`, `walkthrough`, `done` and the
eight role names, values `opus` `sonnet` `haiku` `fable` `session` · **Default:** `sonnet` for `light`
and `validator`, `session` for `walkthrough`, `done` and the other seven roles · **Task override:**
`[MODELS] = [<key>: <value>, …]` ·
**Defined by:** [`../conventions/stage-dispatch.md`](../conventions/stage-dispatch.md) → Model and
effort

Which model a subagent runs on. A role's key covers every stage its agent runs. `light` covers the
calls whose work the script's own prompt defines — reading `Plan.md` back, ticking an epic step,
moving a reviewed task, reading `Walkthrough.md` back for its check — and falls back to the role's
key when it says `session`. `walkthrough` covers writing `Walkthrough.md` and revising it after the
check, and falls back to `light` when it says `session`: `walkthrough: opus` puts that one file on a
stronger model and moves no other call. `done` covers writing `Done.md`, and falls back to the
writer's role — not to `light` — when it says `session`: a Done checks its report against the task,
and `done: sonnet` runs that check on its own model without moving the role's other stages. Under
Method B, Done is written in the main context, on the session's model. `session` passes
no model, so `CLAUDE_CODE_SUBAGENT_MODEL`, then the session's model decide. `validator` starts on
`sonnet`: building, running the tests and reading their logs need no heavier model. A `platform` left
from 1.11.0 reads as if its line were absent. `haiku` has a 200k context and no effort setting, too
small for a phase or a walkthrough. On Amazon Bedrock, Google Cloud's Agent Platform and Microsoft
Foundry `sonnet` means Sonnet 4.5. The orchestrator and any stage it runs in the main context stay on
the session's model. An epic's keys reach its steps.

### [EFFORT]

**Values:** `<key>: <value>` entries, comma-separated; keys `walkthrough`, `done` and the eight role
names, values `low` `medium` `high` `xhigh` `max` `session` · **Default:** `session` · **Task override:**
`[EFFORT] = [<key>: <value>, …]` · **Defined by:**
[`../conventions/stage-dispatch.md`](../conventions/stage-dispatch.md) → Model and effort

The reasoning effort a subagent runs at, per role. `session` passes none, so the session's level
applies. The mechanical calls always run at `low`; writing and revising `Walkthrough.md` run at the
`walkthrough` level, and writing `Done.md` at the `done` level, each at its writer's where that says
`session`. A level the model does not support drops to the nearest one it does. When the Workflow
tool is unavailable and a profile runs through its skill, no effort can travel with a dispatch:
every stage runs at the session's level, and the run says so once.

### [LONG_RUN]

**Values:** `<key>: <minutes>` entries, comma-separated; keys `stall` and `max`, whole minutes > 0 ·
**Default:** `stall: 5, max: 30` · **Task override:** `[LONG_RUN] = [<key>: <minutes>, …]` ·
**Defined by:** [`../conventions/agent-tooling.md`](../conventions/agent-tooling.md) → Long-running commands

How long a command a stage agent runs through `scripts/long-run.sh` may print nothing before it
counts as hung (`stall`), and how long it may run at all (`max`). Raise them for a project whose
clean build or full UI test run is slower, or whose link step is silent for minutes. An epic's keys
reach its steps.
