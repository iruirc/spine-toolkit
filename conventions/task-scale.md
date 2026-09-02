# Task Scale

One axis, two values, and the same guarantees at both. `scale` decides how deep a task's pipeline
goes; it never decides whether the work is checked.

## The two values

`full` runs every stage as its own agent writing its own artifact — the behaviour every project had
before this axis existed, and the value a project gets when its config says nothing.

`lite` folds the investigating stage into the artifact that consumes it, drops the sections nothing
downstream reads, and caps how long each artifact may run. It is cheaper, not looser.

There is no third value. A third needs two thresholds and a corpus calibrated for neither.

## Resolution

```
Task.md [SCALE]  →  CLAUDE-spine-toolkit.md ## Scale  →  full
```

First hit wins. A missing section is the default, not an error. The orchestrator resolves this once
per dispatch and ships the result in the Outbound Contract, for the same reason `walkthrough`
travels there: a workflow script has no filesystem and cannot read the value for itself.

## Three levers, one value

The value moves three different things, and a skill's text has to keep them apart — otherwise
"make it lighter" reads as "make it worse".

| Lever | What it cuts | How it pays |
|---|---|---|
| Stage gating | which stages get an agent of their own | directly: every agent carries a full starting context on every one of its steps |
| Structure gating | which sections an artifact carries | through re-reading: a section enters the starting context of every later agent |
| Prose budget | how many lines an artifact may run to | the same way, and it is the only one of the three that measurement can check |

They do not get separate flags. Separate flags would be a matrix of states with nothing to
calibrate them against.

## The floor

Not one of these is removed at any value:

- one git commit per green phase, with the phase's tests run before it;
- `Reproduce` for BUG — a proven red run before the fix;
- `Validation` — a build and a test run, by an agent of its own;
- `Review` — by an independent agent, with a verdict on the artifact's first line.

An artifact that a `lite` run does write is shorter. An artifact that carries a guarantee is still
written, and still by the agent whose independence is the point.

## The ratchet

A `lite` run can be raised to `full`. It is never lowered, at any point, by anyone.

Two points, both before anything expensive:

| Point | Who decides | Why there |
|---|---|---|
| the end of the profile's first investigating stage | the agent that has just measured the perimeter | before it, nobody knows the perimeter |
| the entry to `Plan` | the planner, holding the work-item list | the last point before implementation |

Where `lite` has folded the investigating stage into `Plan`, both points collapse into the planner's
first act. Once an implementing stage (`Execute` / `Fix` / `Refactor` / `Write`) has started, the
ratchet is closed.

Raise if **any one** of these holds:

1. the perimeter is more than five production files, or spans more than one package;
2. the change crosses a package boundary or a public API other code depends on;
3. the work items do not fit in a single phase;
4. you cannot state the mechanism in one paragraph — for BUG, the root cause is not localized.

An agent raises the scale by returning `scale_escalation: {to: "full", reason: "<what you found>"}`
**and then writing its own artifact at the new depth**, in the same pass. One agent, one artifact,
no re-dispatch of work already done.

The orchestrator writes `[SCALE] = [full]` back into `Task.md` on receiving it, so a rerun does not
rediscover the same finding, and dispatches whatever is left of the range at `full`. Two cases
produce no write-back: a run already at `full` has nothing to raise, and `[SCALE] = [full]` already
in `Task.md` is the author's own decision, which a stage does not get to re-make. Because the value
lives in the file, a later `redo` of any stage runs at `full` too — the size is a property of the
task, not of one dispatch.

## Explicit beats the axis

`scale` sets the default for an artifact that has its own switch, and loses to that switch when it
is set. `[WALKTHROUGH] = [on]` in `Task.md` writes `Walkthrough.md` on a `lite` run. The reverse
does not hold: `full` turns nothing back on that the user turned off. An axis that silently
overrode an addressed decision would be the opacity this design exists to avoid. The same one-shot
resolution means a mid-run raise to `full` does not turn `walkthrough` back on either: the
orchestrator resolved it once before dispatch, and the script has no way to re-resolve it.

## Budgets are measured

Whole-file line ceilings live in `scripts/lint-artifact-budget.sh` and nowhere else in prose. A brief
may state the ceiling for the artifact its agent is about to write, but the ceiling is *enforced* by
running that script — a count limit published as a directive and never checked is a limit this
repository has already watched go unobserved for months. State it, then measure it.

That instrument fits an artifact of fixed shape. It does not fit one whose length is a function of
the work: `Walkthrough.md` carries a block per commit, `ManualChecks.md` a case per check, and a
single number for either file would strangle a large task or mean nothing on a small one. Those two
are budgeted **per unit** — per commit, per case, per divergence — in the skill that governs each
(`task-walkthrough`, `manual-checks`). A per-unit budget is not something a line count can decide,
so it is read like the rest of the artifact, by the stage that reviews it. Adding one of these to
the lint's table would not make it measured; it would make the number arbitrary.

## What the axis does not govern

Role `security` is a subject-matter question, not a size one: it is not invoked on a `lite` task
unless the perimeter touches credentials, network, deep links, storage or authentication — and it
is invoked on such a task at any size.
