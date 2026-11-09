---
name: task-report
description: "Use at Plan to decide whether a task leaves a topic report — one document in a documentation component's `places` that holds the task's numbers and conclusions whole — and where it goes; at the end of the implementing stage to write or update it; at Done to link the task's artifacts to it and lint those links; and at Review to check that no artifact carries a number the report does not. Governed by `[REPORT]` in Task.md and the project config."
---

# Task Report

Some tasks end with results that do not fit one artifact: a measurement over several sizes, a comparison of variants, findings that decide what later steps do. Left alone, those results spread over `Plan.md`, `Research.md`, `Done.md` and the documentation, numbers get copied by hand from one to the next, and the copies drift. The reader who asks "what did we find out, and where is the evidence" gets five answers. The report is the one answer.

**The principle.** Every fact has one place where it is written whole. Everywhere else it is a link and the conclusion.

The report is a topic document in the `places` of a documentation component, never in the task folder: the task folder moves to `DONE/` and stops being read, the topic stays. Its numbers and conclusions are written whole only there; `Done.md`, `Research.md` and `Plan.md` link to it and do not repeat its numbers.

The setting is `[REPORT]` in `Task.md` (an epic step inherits it from the epic) or in the project config, and it reaches a run as the contract's `report`: `auto` (the default — Plan decides by `## When`), `on` (the report is written), or `off` (nothing in this skill applies). After a decision of `not-needed`, nothing in this skill applies either, except the ratchet in `## Links`.

> **Related skills:**
> - `docs-route` — the component registry and `Docs.md`; this skill picks a file inside a component's `places` and answers its row
> - `task-documents` — the documents a task leaves; with a report, their numbers become links to it
> - `artifact-reader` — the style rules the report follows, as every artifact does
> - `task-walkthrough` — the account of what the task landed in the code; the report is the account of what it found

## When

Under `auto`, a report is needed when at least one of these holds:

- the results are written in three or more of the task's artifacts;
- the result holds more than one table of numbers — several sizes, variants or scenarios;
- the results decide something for other steps or tasks.

Plan judges by what the phases will produce, since nothing is produced yet. A judgement that turns out wrong is caught at Done by the ratchet (`## Links`, step 2).

Under `on`, the answer `not-needed` is not available: Plan only decides where the report goes.

QUICK, BUG and REFACTOR reach this section only with an explicit `on`: for them `auto` resolves to `off`. REVIEW never reaches it: it has no Plan, and its `report` is always `off`. TEST, FEATURE, RESEARCH and EPIC keep `auto`, and Plan decides.

An epic's Plan decides only about the epic's own report. Each `.step/` decides about its own by its own Plan, under its own profile and its own `report`.

## Where

The report goes in the `places` of the state component of `DocsMap.md` (`[DOCS_MAP]`) whose `covers` the task touches. `scripts/docs-route.sh route` with the paths the plan intends to touch names the candidate components.

- The file is named by its topic (`PerfBaseline.md`), never by the task's number.
- A report on this topic already in those `places` → the decision is `update`, and `## Updating` applies.
- No registry, `[DOCS] = [off]`, or no component fits → the decision is `unplaced`, and Plan writes a question in `Questions.md`, in the format of the `task-documents` skill: which component to create, or where to put the file.

There is no fallback folder for reports, and the report never goes in the task folder. A report is a file in the component's `places`: the component's existing row in `Docs.md` records it, marked `Applicable` with the file name in `Note`, and no new kind of row is added.

## The decision

Plan writes two machine-readable fields under `## For the owner` of `Plan.md`. A RESEARCH task has no Plan: its Research stage writes them at the top of `Research.md`. Below them goes one line with the reason, in the task's language:

```
[REPORT_DECISION] = needed | update | not-needed | unplaced
[REPORT_PATH] = <path from project root>
```

For example:

```
[REPORT_DECISION] = needed
[REPORT_PATH] = Documents/Notes/PerfBaseline.md
Three scenario tables over three sizes, and steps 03–12 take their inputs from them.
```

- `[REPORT_PATH]` is required for `needed` and `update`, and absent for `not-needed` and `unplaced`.
- The path is from the project root, as every path of `docs-route` is.
- The field is `[REPORT_DECISION]`, not `[REPORT]`: `[REPORT]` is the setting in `Task.md`, and the decision in `Plan.md` is a different field.

`scripts/lint-report-links.sh` reads these fields from `Plan.md`, else from `Research.md`, and exits 2 on a value outside the four or on `needed` or `update` with no path.

## The document

The agent of the implementing stage's role writes the report, in a call of its own after the phases and before `Walkthrough.md`. It writes the file by this section (or by `## Updating`), marks the component's row in `Docs.md` `Applicable` with the file name in `Note`, and commits it as `docs(<scope>): …` in the repository that holds the file. For RESEARCH the agent of the Research stage writes it at the end of Research, with the fields. For an epic it is the architect, once, before Done: after the walk of the steps, or after the pure-research branch.

The required minimum, eight parts:

1. **The conclusion**, in 5–7 points.
2. **The terms** — every word the table needs, explained.
3. **One summary table** — scenario | number against its threshold | where the time goes | decision | link to its section.
4. **Why**, per scenario.
5. **Where sources disagree** — both numbers and where each comes from, or the single word "none". The heading carries these words, or their Russian form in a Russian report; the lint looks for either.
6. **What was not measured, and why.**
7. **How to reproduce it, and where the raw data is.**
8. **Sources.**

The source task is named by its **full slug** (`conventions/docs-components.md` → "A name, not a path"), never by a path `Tasks/<STATUS>/…`: that path breaks the day the folder moves to `DONE/`. The lint checks that the report names the task folder.

The project owns everything beyond the minimum: a header (`Status`, `Synced`, `Owner`, `Source of truth`), further sections, the style of the tables. The style rules every task artifact follows are in the `artifact-reader` skill, and the report follows them too.

Before writing, read the example for the project's language: `examples/report.en.md` or `examples/report.ru.md`, and the English one for any other language. Each is a real measurement report cut down to the eight parts. Match its density, not its content.

## Updating

When the decision is `update`, the report already holds numbers from an earlier step.

- New numbers are written next to the old ones, never over them.
- Each new column or section is labelled with the slug of the step that measured it.
- Old numbers are not rewritten. One the new step makes stale is named in `Where sources disagree`, both numbers with where each comes from.
- The conclusion and the summary table say which numbers they now rest on.

## Links

What Done does. Under Method A the profile script runs steps 1–2 as one call to an agent of the implementing stage's role, before the Done agent; that agent answers `changed: false` when there is nothing to change, and that is no failure. The Done agent then does steps 3–6. Under Method B the workflow skill's Done stage does the same: steps 1–2 by dispatching that role's agent per `conventions/stage-dispatch.md`, as for `Walkthrough.md`, then steps 3–6 itself.

1. If Validation or Review changed a number, the implementing role's agent adds it to the report, by `## Updating`.
2. **The ratchet.** If the decision is `not-needed` and a criterion of `## When` turned out to hold, the fields are rewritten to `needed` or `update`, with the reason, and the implementing role's agent writes the report. There is no way back: a `needed` never becomes `not-needed`.
3. `Done.md` links to the report by a relative path and takes its conclusions from it. `ACTIVE/` and `DONE/` sit at the same depth, so the link survives the move. A number in `Done.md`, if there is one, matches the report.
4. The first line under the title of `Research.md` and of `Plan.md` is a link to the report.
5. Run `scripts/lint-report-links.sh <task-dir>`. Fix each finding once and run it again; name what is left in the run's summary.
6. `unplaced` with no answer in `Questions.md`: no report is written and the lint is not run. `Done.md` and the run's summary carry the line "report not written: no place — question Q<n>".

## Review

The reviewer reads the report against the task's artifacts.

- A number in `Done.md`, `Research.md` or `Plan.md` that the report does not carry, or that disagrees with it, is a **blocking** finding. It is closed by editing the documents, so it goes in `## For Done`.
- Not blocking: no `[REPORT_DECISION]` field while `report` is not `off`; a disagreement between sources the report does not name in `Where sources disagree`; `not-needed` when a criterion of `## When` held.
