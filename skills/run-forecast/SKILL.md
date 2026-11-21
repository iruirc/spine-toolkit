---
name: run-forecast
description: "Use at the Plan stage of a FEATURE or EPIC task when `estimation` is `on` and `estimation_unit` is `agent-run` or `both`, to forecast how long the agents' run from Execute to Review takes and how many gates it stops at; and at Done of the same task to write the estimate retrospective against the measured run and the task's row in the agent-run calibration log. The forecast is a structural model: code phases, regression modules, a driver scenario and fix rounds times per-key coefficients, which the project overrides in `## AgentRunCoefficients` and the log proposes. Output is a best and a worst scenario, never a point."
---

# Run Forecast

The owner deciding at the gate after Plan whether to start the agents needs to know how long the
agents will take, not how many days an engineer would. This skill counts what `Plan.md` already
holds, the code phases, the modules of the regression set, a driver scenario and the fix rounds,
and multiplies each by a coefficient in minutes. At Done it reads the measured run back and writes
one row of a log that later proposes the project's own coefficients.

The forecast covers the stages Execute → Review. Research, Plan and Done are in neither the forecast
nor the fact. Whether the plan may start is not this skill's call: the readiness gate is
`conventions/estimation-gate.md`, shared with `feature-estimation`, and the forecast's number never
blocks.

> **Related skills:**
> - `feature-estimation` — the estimate in engineering days, applied instead of this skill at
>   `days` and beside it at `both`
> - `phase-verification` — the rung of each phase; a load-bearing unknown is one that could raise it
> - `task-documents` — where `## Estimation` and `## Estimate retrospective` sit in `Plan.md` and
>   `Done.md`

## When to use

- FEATURE Plan, when `estimation` is `on` and `estimation_unit` is `agent-run` or `both`.
- EPIC Plan under the same settings: the summed forecast of the steps (`## EPIC`).
- Done of a task whose `Plan.md` carries `### Run forecast`: the retrospective and the log row.
- Not at `estimation = off`, and not at `estimation_unit = days`: `feature-estimation` alone
  serves that unit. Not for BUG, REFACTOR, TEST, QUICK, REVIEW or RESEARCH.

`## DeliveryMode` and `## AILeverage` of the project config refine only the estimate in days. This
skill never reads them.

## Model

The terms come from `Plan.md`:

| Part | Basis | Default coefficient | Key |
|---|---|---|---|
| Execute | the number of code phases | 8–20 min per phase | `execute_per_phase` |
| Validation | the modules of the regression set | 5–15 min per module | `validation_per_module` |
| Validation | a driver scenario, when Validation will run one | +15–30 min | `driver_scenario` |
| Review | — | 10–25 min | `review` |
| Fix rounds | best 0, worst `min(1, fix_rounds)` | 30–60 min per round | `fix_round` |

The defaults are an order of magnitude from agent-run logs, not a measurement of this project.

- **Two scenarios.** The best case takes the low end of every coefficient and 0 fix rounds; the
  worst case takes the high end and 1 round. They are two coherent worlds, not the minimum and the
  maximum of every knob at once.
- **Fix rounds.** `fix_rounds` is the task's resolved `[FIX_ROUNDS]`. At 0 the worst case has no
  round either.
- **Gates.** In `manual`: 3 for Execute, Validation and Review; 3 more for each fix round, its Fix,
  Validation and Review; and 1 more for each `pending_user` row in `### Estimation conditions`. In
  `auto`: 0.
- **Confidence.** `Low (uncalibrated)` while any coefficient the forecast used is this skill's
  default rather than a row of `## AgentRunCoefficients`. Once every one comes from the project, the
  usual scale applies: `High` for a narrow spread backed by finished tasks like this one, `Medium`
  when part of the basis rests on judgement, `Low` for a wide spread or thin evidence.
- **Phase rungs.** The coefficients are not split by `phase-verification` rung. Execute is one
  stage, the time of a single phase is not measured, and there is nothing to calibrate a split
  against.

**Project override.** The project config may carry `## AgentRunCoefficients`:

```markdown
## AgentRunCoefficients
| Key | Value | Reason |
|---|---|---|
| execute_per_phase | 12–30 | median 18 over 6 finished tasks; phases touch two modules |
```

The keys are the five in the table above; the value is a range of whole minutes, `N–M`. A row
replaces that key's default and leaves the others alone. A malformed row, an unknown key or a
template placeholder is ignored, and `### Assumptions` under `## Estimation` names it, so the reader
sees which default stood in for it.

## Plan.md

The forecast is a section of `## Estimation` in `Plan.md`, in this form:

```markdown
## Estimation
### Run forecast
| Part | Basis | Best | Worst |
|---|---|---:|---:|
| Execute | 5 code phases | 40m | 1h40m |
| Validation | 3 modules, driver scenario | 30m | 1h15m |
| Review | | 10m | 25m |
| Fix rounds | 0–1 | 0 | 1h |
| **Run (Execute → Review)** | | **1h20m** | **4h20m** |

Gates (manual): 3–6. Confidence: Low (uncalibrated).
```

- The Basis column names the counts Done writes to the log: the code phases, the modules, and
  whether a driver scenario runs. Without a driver scenario the Validation basis names only the
  modules.
- Under `auto` the line reads `Gates (auto): 0.`, then the confidence.
- Under `both` the subsections of `feature-estimation` follow under the same `## Estimation`.
  `### Estimate maturity` and `### Estimation conditions` serve both units and appear once.
- The Plan's answer carries the same figures as `run_forecast: {best, worst, gates, confidence}`,
  each a string as the section writes it: `1h20m`, `4h20m`, `3–6`, `Low (uncalibrated)`.
- If `### Run forecast` already exists, the earlier one moves under `### Estimation history` with
  its date; re-forecasting mid-task is normal.

**Calibration first.** Before forecasting, run the calibration script on the project's log and
show the owner what it proposes (`## Calibration`).

**Gate.** Maturity, conditions and the load-bearing-unknown rule are
`conventions/estimation-gate.md`. A Plan that blocks there reports `estimation_gate` as `blocked`
with the reason; the forecast's size is never a reason.

## Done.md

When `estimation` is `on`, the unit is `agent-run` or `both`, and `Plan.md` carries
`### Run forecast`:

1. Run, from the core root:

   ```
   scripts/agent-metrics.sh --format json --task <id> --project-sessions
   ```

   It gathers the task's runs from every session of the project, so a task interrupted and
   continued in a new session is measured whole.
2. Read `totals`. Every duration there is in milliseconds:

   | Part | Field |
   |---|---|
   | Execute | `stageSpans.Execute` |
   | Validation | `stageSpans.Validation` |
   | Review | `stageSpans.Review` |
   | Fix rounds | `fixRounds`, and `fixSpanMs` for their time |
   | Gates | `gateRuns` in `manual`; 0 in `auto` |

   `stageSpans` has no key for a stage that had no timed agent: read a missing key as no time.
   `fixSpanMs` is 0 when there were no fix-review runs. `gateRuns` counts the task's runs in which
   an agent ran Execute, Validation or Review, fix-review runs included; a Research or Plan run is
   not a gate of the forecast, and `runs`, which counts every run, is not the gate count. A fix round's stages are counted in
   `fixSpanMs`, never in `stageSpans`, so the Run's actual is the three stages plus `fixSpanMs`. A
   stage's span is summed run by run, so the owner's wait between two runs is never in it.
3. Write `## Estimate retrospective` in `Done.md`, in the forecast's unit (below).
4. Correct this task's row in the calibration log, or append it (`## Calibration log`).

The retrospective takes this form:

```markdown
## Estimate retrospective
| Part | Forecast | Actual | |
|---|---:|---:|---|
| Execute | 40m–1h40m | 1h05m | in |
| Validation | 30m–1h15m | 1h50m | over |
| Review | 10m–25m | 20m | in |
| Fix rounds | 0–1 | 1 (55m) | in |
| **Run** | **1h20m–4h20m** | **4h10m** | **in** |

Gates: forecast 3–6, actual 6. Source: workflow. Variance: Validation re-ran the app twice on a flaky driver step.
```

The last column is `in` inside the forecast range, `under` below it and `over` above it; the Fix
rounds row judges the count of rounds. `Variance:` names the cause of every `under` and `over`, or
says `none`.

**Git fallback.** The fact falls back to the commit span from git, with `source = git`, when:

- the script finds no runs for the task: a host whose transcripts it cannot read, another working
  copy, transcripts already cleaned away; or
- `totals.skippedSessions` is not empty. The fact is then incomplete, and `variance_reason` names
  the skipped session ids.

The commit span runs from the task's first phase commit to its last. Its stage cells are `—`, its
verdict is `n/a (git span)`, and the retrospective's last column reads the same. A `git` row never
enters calibration.

Under `both`, Done writes both retrospectives and both log rows; the days follow
`feature-estimation`.

## Calibration log

The log is `Tasks/_calibration/agent-run-log.md`, separate from the log of the estimate in days.
When it is absent, create it with exactly this header; never reorder or rename a column:

```markdown
# Agent-run calibration log

> Durable evidence base for `run-forecast` calibration. One row per finished task.
> One row per task, corrected in place when its Done runs again; no other row is reordered or removed.
> Columns are fixed-order and machine-read — do not reorder or rename.
> Durations are whole minutes. `source = git` rows hold a commit span and never enter calibration.

| date | task_id | type | mode | phases | modules | driver | forecast | actual | execute | validation | review | fix_rounds | fix_time | gates_forecast | gates | source | in_range | variance_reason |
|------|---------|------|------|--------|---------|--------|----------|--------|---------|------------|--------|------------|----------|----------------|-------|--------|----------|-----------------|
```

| Column | Value |
|---|---|
| `date` | the Done date, `YYYY-MM-DD` |
| `task_id` | the task by its number, as below |
| `type` | `FEATURE`, or `EPIC` for an epic's rolled-up row |
| `mode` | `manual` or `auto` |
| `phases` | the code phases the forecast counted, `0` when there were none |
| `modules` | the modules of the regression set, `0` when there were none |
| `driver` | `yes` when the forecast had a driver scenario, otherwise `no` |
| `forecast` | the Run's range in whole minutes, `N–M` |
| `actual` | the Run's actual in whole minutes: the commit span at `source = git` |
| `execute` `validation` `review` | each stage's span in whole minutes; `—` at `source = git` |
| `fix_rounds` | the rounds run; `—` at `source = git` |
| `fix_time` | `fixSpanMs` in whole minutes, `0` with no round; `—` at `source = git` |
| `gates_forecast` | the forecast's gates, `N–M` |
| `gates` | the actual gates: `0` in `auto`, `—` at `source = git` in `manual` |
| `source` | `workflow` or `git` |
| `in_range` | `in`, `under`, `over`, or `n/a (git span)` |
| `variance_reason` | the cause of a miss, the skipped session ids, or `—` |

The stage columns are filled in `auto` too: a stage's span exists in both modes. A row with `0`
phases or `0` modules still calibrates: it stays out only of the keys that divide by that count.

`task_id` names the task by its number — `041` or `041-photo-feed` — and a step by its epic's number
and its own — `042-03` or `042-cart/03-promo` — because step folders are numbered afresh in every
epic; a task's own row is the one naming the same task, whatever slug follows the number.

One row per task: a Done that runs again corrects its own task's row instead of appending a second,
and folds any duplicate rows for the same task into that one row. No other row is moved or removed.

Epics record one rolled-up row in addition to each step's own row: `type = EPIC`, each count,
duration and gate column the sum of the steps' rows, `driver = yes` when any step's is, and
`source = git` when any step's is. The calibration script skips it.

## Calibration

At Plan, before the forecast, run from the core root:

```
scripts/run-calibration.sh Tasks/_calibration/agent-run-log.md
```

It reads the rows with `source = workflow` and a `type` other than `EPIC`, and prints one line per
key that has data, ready to paste into `## AgentRunCoefficients`:

```
| <key> | <q1>–<q3> | median <m>, <n> rows |
```

- `run-calibration: <n> usable rows, need 3; nothing proposed` — fewer than three usable rows.
- `run-calibration: no log at <path>; nothing proposed` — no log yet.

Both exit 0 and propose nothing. What the script writes to stderr (a dropped non-positive sample, a
missing header, a malformed line) is for the architect to mention to the owner, not to paste.

A proposal goes to the owner as a proposal, with the lines as printed; the owner decides what enters
`## AgentRunCoefficients`, and with what reason. Never write the config silently: every future
forecast depends on those numbers.

## EPIC

- The epic's `### Run forecast` sums the forecasts of its steps, one row per step. A step not yet
  planned is forecast by the model above from the phases its card in the epic's `Plan.md` expects;
  a step that has written its own Plan contributes its own `### Run forecast`.
- When a step writes its Plan, the epic's row for that step takes the step's figures and the totals
  are summed again.
- The summed forecast is informational. It is never a gate: each step meets
  `conventions/estimation-gate.md` at its own Plan.
- At the epic's Done, the rolled-up row of `## Calibration log` sums the steps' rows.
