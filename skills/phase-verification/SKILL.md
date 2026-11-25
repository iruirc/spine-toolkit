---
name: phase-verification
description: "Use at Plan to decide how much each phase checks before it commits, at the implementing stage to run exactly that, and at Review to judge the choice. The rung follows from what a phase changes for the modules that depend on it, never from how risky the edit feels, and the regression belongs to Validation, whose set this skill also defines. Governed by `[PHASE_VERIFICATION]` in Task.md and the project config."
---

# Phase Verification

Every phase ends buildable, green and committed, so it can be reverted or bisected on its own. This skill decides how much "green" means. Too little, and a break surfaces at Validation across a dozen commits; too much, and every phase re-runs what Validation is about to run anyway. **The task's regression belongs to Validation. A phase checks what it can break.** What Validation runs is defined under `## Validation's regression`.

## Terms

- **Perimeter** — the modules a phase edits.
- **Dependent** — a module the phase does not edit that builds from the perimeter's source in this task's checkouts. A consumer pinned to a published version cannot see the change and is not a dependent here.

## The rungs

Each rung includes the one above it.

| Rung | When | What runs |
|---|---|---|
| `internal` | nothing outside the perimeter can see the change | build and the tests of the perimeter |
| `surface` | what dependents build against changes, but not what they observe: new API nobody calls yet, removal of something nobody calls any more, build configuration | + a build of every dependent — the narrowest build that covers them all |
| `behaviour` | what dependents observe changes: the semantics of an existing call, a default value, a shared test fixture | + the tests of the dependents that observe it, by name — not all dependents |

The tests of the perimeter are every test of the modules it edits (with no modules, the whole suite is the perimeter's tests, not finding 3 of `## Review`): Validation counts that run. A dependent's tests are named by class, never run whole; a full test plan of the app, or all tests, in a phase's checkbox at `proportional` is finding 3 of `## Review`.

## Choosing the rung

Ask in this order and stop at the first yes:

1. Does any call from outside the perimeter get a different result, a different error or a different state? → `behaviour`
2. Does anything visible outside the perimeter appear, disappear or change its signature? → `surface`
3. Otherwise → `internal`

Answer from a **usage search** of what the phase changes, not from memory: a `behaviour` line names the dependents the search found, a `surface` line states that nothing outside calls what changed. How to search is the platform agent's business.

**Doubt raises one rung, never to `full`,** and the line says what the doubt is — a changed value written into a serialized format no code search reaches, say. Over-claiming costs a few dependents' tests; under-claiming costs a bisect.

| Phase | Rung |
|---|---|
| adds `Money.round`, nothing outside calls it yet | `surface` |
| changes the rounding mode inside `Money.add`, which Checkout and Cart call | `behaviour` — Checkout, Cart |
| renames a private helper | `internal` |

## The line

The first line of every phase's detail section in `Plan.md`:

```
**Verification:** <internal|surface|behaviour|full> — <what this phase changes for its dependents, one clause>
```

Under it, one checkbox per check the line names; the platform agent writes the commands. The line is *what*, the checkbox is *how*. The line is written at `full` too, so a phase without one means the plan predates this rule or was written outside the pipeline — never a project's choice.

A check that runs a module whole and green gets one more line under its checkbox, written after the phase commit (the tasks folder is no change) and committed with the next one: `ran: <repository> <module> HEAD <sha> tests <N> result "<result line>" log phase-evidence/phase-<id>/<module>.log`. `<sha>` is the phase commit; the log is the run's copy in the task folder, taken from `$TMPDIR` without its sidecars. A result line is quoted exactly as the log has it; which line of the log is one, and where its count stands, the platform's `test-frameworks` says for the stack's `tests` value (topic **testing**). A log with several result lines gets one `result` per line, in the log's order; a result line that counts no tests is not quoted. `<N>` is the sum of the counts of the quoted lines. A run of named classes, and a red run, get none. A line written before this form has `Executed <N>` where `tests <N>` stands, and no `result`: it is carried the same way, and a log that lacks the words is no finding against it. Validation carries the line (`## Validation's regression`).

## Who does what

- **Plan** chooses the rung and writes the line and its checkboxes.
- **The implementing stage** runs what the line names. A phase with no line resolves the switch below, derives its rung from its own diff by the questions above — or writes `full` — and adds the line before any check runs. A diff that reaches further than its line raises the line in the same phase commit and runs the higher check. Raising stays within `internal` → `surface` → `behaviour`; nobody lowers a rung.
- **Validation** runs the regression defined under `## Validation's regression`, not the whole workspace.

## Validation's regression

What Validation runs is the task's regression: everything the task's changes can reach.

1. every module the task changed: commits in its ranges, or uncommitted edits; a change to only a module's tests counts;
2. every module that depends on one of them, transitively, among the task's checkouts;
3. the application, or the build that ships them, when any module of the set is in its graph.

A module whose code and dependencies did not change is neither built nor tested: its result cannot differ from the last green run. A file several modules share (a dependency lock file, a common build or lint configuration) changes every module that reads it. A project without modules runs its whole suite. The unit is the module: tests inside a module are not picked.

**A re-run** recomputes the set from the task's ranges and runs only the modules no earlier green run covers. A green run of a whole module covers it when no commit after that run's sha, and no uncommitted edit, reaches the module or its dependencies. There are two sources: a phase's `ran:` line under its checkbox in `Plan.md`, written `carried <sha> (phase <N>)`, and a green `ran` row of an earlier `Validation.md`, the archived copy or the current file, whatever its status, written `carried <sha> (validation)`. Of several sources the latest wins. A `ran` row is green when its module's run had no failure other than those its `## Outside the task` records as `known` or `flaky`; a module with a `red` or an inside failure is red, and a module red in the latest Validation that ran it always runs again. A carried module keeps its source's count, HEAD and log. There is no separate list of when a full regression is needed: a changed build manifest or public API makes the module changed, its dependents join the closure, and the run widens by itself. The driver scenario repeats only when the new commits touch the UI layer or a path the scenario walks.

The owner's directive never narrows the regression. The owner may widen it: a run of the whole workspace is legitimate, but it is not Validation's and belongs before packages are released. The project's own whole-workspace script is not run by Validation without the owner asking.

### Failures outside the task

A failing test is **outside the task** when it does not reach the symbols the task's diff changed: neither its file nor anything it calls contains them. The module is not the boundary: every module of the set is reachable from the change by definition. Decide it by the same usage search the rungs ask for, and write the reason in one sentence. Doubt keeps it inside.

The registry of failures the owner has accepted is the file the contract names in `known_failures`; its form is `conventions/known-failures.md`, and a missing registry is an empty one. Read its first table only; a failure matches an entry by repository, module and test, and an entry that lists a class covers its methods. Validation never writes it.

The first row below leaves out the tests a TEST task adds: whether one of them is unstable is decided by the TEST profile's flake detection, and it gives `FLAKY`. A failure outside the task that is not a `permanent` entry gets a retry: its failed classes only, in a separate run, up to 3 times, and the first green stops. There is no second full run. That it failed under the load of the full regression is written as an observation, not a condition.

| Failure | Status | `outcome` |
|---|---|---|
| inside the task, a TEST task's added tests aside | `FAILED`, even when the test is in the registry | — |
| outside, a `permanent` entry, still failing | `PASSED`, known, `KF-<N>` | `known` |
| outside, a `flaky` entry, the retry green | `PASSED`, known flaky, `KF-<N>` | `known` |
| outside, no entry, the retry green | `PASSED_WITH_FLAKES` | `flaky` |
| outside, the retry red, no entry or a `flaky` one | `FAILED` | `red` |
| TEST: a test the task added is unstable | `FLAKY` | — |

The status is the worst of the rows: `FAILED` > `FLAKY` > `PASSED_WITH_FLAKES` > `PASSED`. `PASSED_WITH_FLAKES` names its failures, it does not hide them.

Every failure outside the task is a row of `## Outside the task` in `Validation.md` (`skills/task-documents/SKILL.md`) and an item of the return field `outside_failures`: `{repository, module, test, outcome, entry}`, `entry` the entry's ID or `—`. A test of a `permanent` entry that passed in this Validation is a line `KF-<N> no longer fails` under that table, and the ID goes into `known_failures_cleared`.

## Dependents with no aggregate build

Where no single build covers every dependent, build them one by one; there is no skipping. The saving comes from the `internal` phases, and `surface` is a build without tests. Never merge consecutive `surface` phases into one build at the last of them: adding a requirement to an interface breaks every implementer, the intermediate commit stops building, and bisect stops with it.

## The switch

The value arrives in the contract as `phase_verification`; `conventions/task-settings.md` holds the chain it was resolved along.

`proportional`, the default, is the rungs above. `full` runs the full regression in every phase — right where the whole suite takes a minute, or on a task whose author buys insurance against a wrong rung. `full` in a line is legal only when the switch resolves to `full`. There is no `off`: a planner choosing freely is the defect this skill exists for. `scale` does not move the switch.

## By profile

| Profile | Typical phases |
|---|---|
| FEATURE | new code nobody calls yet — `internal` or `surface`; wiring it into an existing flow — `behaviour` |
| BUG | the fix — `behaviour` when dependents see the repaired call, else `internal`; the regression test — `internal` |
| REFACTOR | a new primitive beside the old — `surface`; moving dependents onto it edits them, so their tests run as `internal`; the phase after which dependents it did not edit can see the change — `behaviour`; removing the old one — `surface` |
| TEST | a phase adding tests — `internal`; a change to a shared fixture or helper — `behaviour` |

## Review

Five findings, read against `Plan.md`, the diff and `Validation.md`:

1. a phase with no `**Verification:**` line;
2. an under-claimed rung — the questions above, asked of the phase's diff, give a higher rung than its line;
3. at `proportional`, a phase that repeats the full regression — a `full` line, or checkboxes that run the whole suite, a project without modules aside, where the whole suite is the perimeter's tests;
4. a module outside the set that Validation ran — Minor, with its cost in time from the log;
5. a module of the set that Validation did not run — Major.

None of the first four blocks, and none goes into `blocking_findings`. Review runs after Validation has passed, so the code is already proven; these say the plan chose badly, and they exist so the next plan and the measurement can see it. Finding 5 blocks and goes into `blocking_findings`: it is the one exception, because a module no run has touched is not proven.
