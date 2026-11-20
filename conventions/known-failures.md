# Known failures

The project's registry of tests that fail outside any task: a failure the owner has accepted once is
not asked about again by the next task. Validation reads it to classify a failure outside the task
(`skills/phase-verification/SKILL.md` → `### Failures outside the task`); the orchestrator writes it.
No script parses it.

## The file

One file per project, wherever its working copies are. The line `- Known failures: <path>` in the
project config's `## Paths` names it from the project root, a leading `/` included as in `External
packages`, or from the home folder with `~`; without the line it is
`<project root>/Tasks/KnownFailures.md`. The resolved absolute path reaches every stage as the
contract field `known_failures` (`conventions/task-settings.md`). A missing registry is an empty one,
never an error.

## Form

One table, one entry per row:

```
| ID | Repository | Module | Tests | Kind | Cause | Passes where | Accepted | Remove when |
|---|---|---|---|---|---|---|---|---|
| KF-1 | Packages/Core | Core | HostedViewTests | permanent | needs an app host | under the app host, 0 failures | owner, 2026-01-01, 0001/Questions.md | the tests move under the app host |
```

- `ID` — `KF-<N>`, never reused: `Validation.md` and `Questions.md` refer to it.
- `Repository` — the name `scripts/task-ranges.sh` prints, `.` for the project. `Module` — as in
  `## Regression set`.
- `Tests` — classes or `Class/method`, comma-separated. An entry covers only what it lists, a listed class
  all its methods; a failure matches it by repository, module and test.
- `Kind` — `permanent`, a test that fails on every run where the task's regression runs it, or
  `flaky`, one that fails under some runs and passes on a retry.
- `Cause` and `Passes where` — from the `Validation.md` that found it, its Summary and the failure's
  prose: why it fails, and the run in which it passes.
- `Accepted` — `owner, <date>, <task id>/Questions.md`, where the decision is logged.
- `Remove when` — the change that would let the test pass where the regression runs it, from the
  `Validation.md` that found it when it names one, else `—` for the owner to fill in later.

## Removed

A removed entry moves, as a row, into a `## Removed` section below the table, with the date and the
task that removed it. The next ID is one more than the highest in both sections. Validation reads
the first table only.

## Who writes it

Only the orchestrator writes the registry, with the owner's consent, in `manual`, after the
Validation stage, and commits it as a commit of its own in the repository that holds the file; a file
outside git is edited without a commit. The decision goes into the task's `Questions.md`. Validation
and the validators only read it. In `auto` the registry does not change: what Validation found stays
in `Validation.md` and in the run's report.

- **Adding.** After `PASSED_WITH_FLAKES`, the orchestrator offers to add the failures outside the
  task whose outcome is `flaky` as `flaky` entries. After `FAILED` where every failure is outside the
  task with outcome `red`, it offers to add them as `permanent` and repeat Validation, which runs
  only the failed modules again and carries the rest. A `red` failure that matched a `flaky` entry
  replaces it: the `flaky` entry moves to `## Removed` and the `permanent` one is added, so no two
  entries match the same repository, module and test.
- **Removing.** Only by observation. A test of a `permanent` entry that passed is named by Validation
  (`KF-<N> no longer fails`) and returned in `known_failures_cleared`; the orchestrator asks, as a question of
  its own, whether to move the entry to `## Removed`. A `flaky` entry is never removed this way: a green run of an unstable
  test proves nothing.
