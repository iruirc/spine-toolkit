# Estimation Gate

The readiness gate between Plan and Execute for a task that carries an estimate. It holds whenever
`estimation` is `on`, whatever the unit: `run-forecast` and `feature-estimation` both cite it, and so
do the FEATURE and EPIC profiles. The gate checks whether the plan is ready to act on, never how big
its number is.

The Plan reports `estimation_gate` as `blocked`, with the reason, when any rule below holds; a
blocked gate returns `ask_user` and Execute does not start. `### Estimate maturity` and
`### Estimation conditions` sit once under `## Estimation` and serve both units: under `both` the
forecast and the estimate in days share one copy of each.

## Maturity

Maturity says whether the plan is safe to start, not how precise it is. Confidence is a separate
axis, and a precise estimate can still be blocked.

| Label | Meaning | Gate |
|---|---|---|
| `Draft` | the plan is unfinished: a load-bearing input is missing, or `## Estimation` is missing or malformed | blocked: Plan is not complete; return `ask_user`, never enter Execute |
| `Conditional` | the estimate rests on named conditions not yet accepted, or an open unknown trips the load-bearing-unknown rule | `### Estimation conditions` is required; see `## Conditions` |
| `Committable` | no blocking condition and no load-bearing unknown | passes on this axis |

An absent `### Estimate maturity` means a clean estimate: read it as `Committable`. State the label
only when it is not plainly `Committable`.

## Conditions

A `Conditional` estimate carries its conditions in a table, never in prose, so they survive a
resume:

```markdown
### Estimation conditions
| Condition | Owner | Status | Evidence / next action |
|---|---|---|---|
| Backend contract frozen by end of week 1 | Backend | pending_user | Ask user before Execute |
```

| Status | Meaning |
|---|---|
| `pending_user` | holds Execute until the owner accepts, defers or resolves it |
| `accepted` | the owner accepts the assumption; it stays visible for Review and Done |
| `deferred` | the condition moves out of scope or to a later task |
| `resolved` | the evidence is in an artifact, a commit, a ticket or the owner's answer |

- `Conditional` without `### Estimation conditions` blocks the gate.
- Any `pending_user` row blocks the gate. The `ask_user` lists each pending row for the owner to
  accept, defer or resolve.
- On resume the architect writes the owner's answer into the row's `Status` and
  `Evidence / next action`, never silently. A `pending_user` row left untouched still blocks.
- Execute starts only when every row reads `accepted`, `deferred` or `resolved`.

## Load-bearing unknown

The rule has no unit. An unknown is load-bearing when its answer could change the phase table of
`Plan.md`: add a phase, remove one, or raise a phase's `phase-verification` rung. Such an unknown
needs a spike or an answer before Execute. Until it has one, the estimate is `Conditional` and the
unknown is a `pending_user` row in `### Estimation conditions` whose next action names the spike or
the question.

The estimate in days keeps a variant of the same rule: an unknown that could swing the estimate by
more than 30% is load-bearing too, and `feature-estimation` Step 4 says what its spike costs and
where the work returns. The 30% threshold belongs to the days only; a forecast of an agent run has
no percentage rule.

## What never blocks

- The forecast's number. A long forecast is information for the owner at the gate after Plan in
  `manual`, not a reason to stop: there is no threshold.
- Confidence. `Low` or `Low (uncalibrated)` says how far to trust the width of a range, not whether
  the work may start.
- An epic's summed forecast. It sums the steps' forecasts and is informational; each step's own
  Plan meets this gate on its own.
