---
name: manual-checks
description: "Use at Plan to enumerate what a task's automation will not be able to check, and at Validation to turn that list into `ManualChecks.md` — the hand-run script a person executes after the run: a state they can reach, steps they can follow, and a verdict they can settle. Governed by `[MANUAL_CHECKS]` and `[MANUAL_CHECKS_CHECK]` in Task.md and CLAUDE-spine-toolkit.md."
---

# Manual Checks

`ManualChecks.md` is the only artifact of a task that a person **executes**. Every other one is read. That is the whole difference in how it has to be written: prose that is a tenth vague costs a re-read, a case that is a tenth vague cannot be run at all.

> **Related skills:**
> - `ops-checklist` — the same late stage, the opposite direction: evidence for what WAS verified. A case deferred here is a Pending item there
> - `task-walkthrough` — narrative for a reader; this is procedure for a doer
> - `feature-requirements` — the Secondary list is where checks nothing can automate first become visible

## The reader

Someone who knows the product and the codebase and does not remember this task — in practice its author, a month later. The two consequences cut in opposite directions:

- Do not explain the product. No tour of what the screen is for, no glossary.
- Do not assume the task. Which project to open, which data to prepare, which command settles the verdict, what a failure looks like — none of that is in their head any more.

## Two stages, two halves

**Plan → `## Manual acceptance`.** A list, not procedures: one line per check this task's automation will not be able to make, stated as *what must be true — what changed*, never as *what to press*: "the track icon in the header is the new one — the picture was replaced in the resource catalog". The second half is the intent a case is built from; without it Validation guesses. It belongs here because here the task's acceptance criteria are still in front of the author. Nothing qualifies → the single line `Fully automatable.`

For BUG the reproduction replay is not listed: its steps are already in `Reproduce.md`, and Validation reads them from there.

**Validation → `ManualChecks.md`.** That list is the input; each line becomes a case. To it Validation adds what the plan could not know — what the automated pass actually covered, and what it could not reach at all. When the plan carries no such section, because the task entered mid-pipeline or predates this rule, say so in `## Scope` and derive the cases from the task file and the diff.

## Structure

```
# Manual Checks — <task>
[COVERS] = <sha>

## Scope
## Preparation
## Reading the verdict
## Cases
## Troubleshooting
## Not covered
## Charter
```

`[COVERS]` is the short sha the cases were written against. One line, and it answers the only question a reader has a month later: is this about that build or not.

| Section | Content | Budget |
|---|---|---|
| `## Scope` | What the automated pass already covered, named, so nothing green is re-walked by hand; what this file is for; and one line: a case whose scene will not come together is BLOCKED — write down what shows instead | ≤ 8 lines |
| `## Preparation` | The environment every case shares — how it is built, how it is configured, how to reach the screen at all — and the dictionary of actions: each frequent interface action under a name, with the exact way to perform it. No project content | ≤ 60 lines |
| `## Reading the verdict` | How to take the instrument's reading and how to read it: the commands in full, what the fields mean, what separates one run from the next | ≤ 40 lines |
| `## Cases` | Numbered, one per check | ≤ 40 lines each |
| `## Troubleshooting` | Symptom → cause → what to do, for the ways a doer misses that are not product defects | 1 row per symptom |
| `## Not covered` | Ground neither the automation nor these cases reach, one line each with its reason, or `none` | 1 line per item |
| `## Charter` | A timebox and what to look at: "10 minutes: trim and reorder clips on a long project; jitter, sticking, lost selection" | ≤ 3 lines |

**`## Preparation`, `## Reading the verdict`, `## Troubleshooting` and `## Charter` are conditional.** The first two appear when they would otherwise be repeated in more than one case — twelve cases must not each re-explain how to build with tracing on. The third appears when a case has a known way to go wrong that is not a product defect: the instrument was never switched on, the wrong device was picked, the settings were left shifted. The fourth appears when the change carries a gesture or a look the cases do not cover whole. A task with two simple cases is `## Scope` + `## Cases` + `## Not covered` and nothing else.

A named scene in `## Preparation` is allowed once three cases or more refer to it; each of them still builds it from scratch by that description.

`## Not covered` is not a case list — nobody walks it. It exists so that a month later a missing case does not read as a passing one.

## The case

```
### N. <the observable behaviour, not the symbol behind it>

**What it checks:** the intent, in one line
**Scene:** the state to check from — screen, objects, values — and the short route to it
**Steps:**
| # | Action | Data | You see |
|---|---|---|---|
| 1 | one action | a concrete value, or — | what is on screen now |
**By eye:** the outcome, in one line
**By instrument:** the criterion, and the value that carries it
**Failure looks like:** what is on screen when it is broken
**Wrap-up:** what to put back after the case
```

`**By instrument:**` appears only when an instrument settles the verdict; `**Wrap-up:**` only when the case leaves a state that gets in the way of the next case or of a repeat a month later — a test project, a shifted setting. The other five are always there, and each earns itself:

- `**What it checks:**` is what lets a case be skipped knowingly. Without it the only way to learn what a case covers is to run it.
- `**Scene:**` is a state the doer can compare with the screen before the first step, and the route to it in interface actions with their values, or by the name of a `## Preparation` action. At most three lines.
- `**Steps:**` is a table. `You see` is what the screen shows right after that action; it is `—` only for a step that merely prepares the next one.
- `**By eye:**` and `**By instrument:**` are not alternatives. The eye answers "was the action performed at all?", the instrument answers "was it performed correctly?". A case carrying only the instrument cannot tell a defect from a fumbled step.
- `**Failure looks like:**` is the cheapest field and the strongest. A failure is recognised faster than a success is verified, and this is what turns "it did not add up" into "here is what is broken".

Three rules on top of the fields:

- **One step, one action, on a named object in a named place.** Not "find the start of the cell" but "press the left edge of the cell at 00:05". A compound sentence is not a step: splitting "grab it, drag it into the zone, hold two seconds, release" into four rows forces the author to say, in the third row's `You see`, how the doer knows the zone was reached.
- **Cases are independent.** None starts from the state another left. Reusing another case's steps is legal when the steps and the change are both named — "steps 1–3 of case 1, but hold four seconds at step 4"; its scene never is.
- **The route to data is named in actions.** Data the repository does not carry is reached through the interface, with values, in `**Scene:**`.

**Language.** The section headings, `[COVERS]`, the table's column names and the field labels above stay English: they are the file's structure. A case's title after `### N.`, the text after each label, the table's cells, and the text of every section — `## Scope`, `## Preparation`, `## Reading the verdict`, `## Troubleshooting`, `## Not covered`, `## Charter` — are prose in the project's `[LANG]` (`conventions/i18n.md` → Artifact authoring rule).

## Grounding

A case states what the code does, so it is written from the code, never from memory:

- Every claim about behaviour in `**Scene:**`, `You see` and `**Failure looks like:**` — a direction, a target, how neighbours react, a threshold — is checked against the code and carries its reference as a gloss, under the symbol rule: `the edge snaps to the cursor line (snap_resolver:88)`. Advice from `Review.md` enters a case only after that check.
- A case about a resource or a style names the element that draws it, with a reference to where it is used.
- A step uses only what exists in the build at `[COVERS]`; a check of what a later step of an epic adds is a `## Not covered` line with its reason.
- **The empty case.** `**Failure looks like:**` is what the code before the change would show on the same scene. When it matches `You see`, the case checks nothing: delete it, and give `## Not covered` a line with the reason.

## Refreshing

A Validation that finds `ManualChecks.md` with a `[COVERS]` behind HEAD refreshes it rather than rewriting it:

1. `git diff --name-only <COVERS>..HEAD` names the changed files.
2. A case with a code reference into one of them is checked again, and so is a case with no code reference at all; the others are left alone.
3. A new `## Manual acceptance` line becomes a new case; a case automation now covers moves to `## Scope` with a reference to that evidence.
4. `[COVERS]` becomes HEAD.

## The instrument rule

An expectation is written in what a person can **see**. When the verdict comes from an instrument — a trace, a log, a parser, a profiler — that instrument has to be runnable from this file: the command in full, and the value in its output that decides.

The command is written **once**, in `## Reading the verdict`. A case's `**By instrument:**` names only its own criterion — the measurement and the threshold it is judged against. Twelve cases do not repeat one invocation twelve times. When no command serves more than one case — a single case, or cases each measured differently — there is no such section and each command lives in its own case.

| | |
|---|---|
| Defect | `**By instrument:** the trace shows the engaged frames` — no command anywhere, no threshold |
| Case | `**By instrument:** drift/path for this scenario → under a quarter percent`, with `## Reading the verdict` carrying the invocation that prints it |

Naming the instrument is not carrying it: an instrument mentioned by filename, with no invocation and no field to read, is a defect.

## The symbol rule

Neither `**Scene:**` nor either expectation identifies a state by the name of a function, a file, or a variable. Nobody can reach *almost at the minimum-duration constant*; they can reach *compressed until it stops compressing*. A symbol is allowed in parentheses as a gloss, never as the instruction.

## Check

`[MANUAL_CHECKS_CHECK]` decides whether the file is walked by someone who was not there before it is handed over; it reaches a run as the contract's `manual_checks_check`, `on` by default.

**When.** Validation returned `PASSED`, the file holds at least one case, and this Validation wrote or changed it — a case added, removed or rewritten; moving `[COVERS]` alone is no change. The author never checks its own file: the dispatcher does — the profile script under Method A, the workflow skill's main context under Method B.

**The reader** is a fresh dispatch of the validator's role, tuned `light`. Of the task and the repository it reads `ManualChecks.md` and nothing else — no other file of the task, no source file, no git — and returns two lists:

- `walk` — one line per step of every case, as the action it would take: "I press X there, and expect Y";
- `smells` — every place it could not execute as written, each with the case, the step, a quote of at most one line and what is missing, of one kind: `ambiguous` — an intent, or a step with no object and place; `unverified` — an action with no `You see`, other than a preparing step; `precondition` — a scene that cannot be compared with the screen; `tacit` — a term, a screen or data with no route to it; `oracle` — an expectation that cannot be compared with the screen.

**Revision.** An empty `smells` ends the check. Otherwise the author, with the code and the task, fixes in one pass every place named and every step `walk` retold wrongly. What is left is not checked again. The run notes one line — `ManualChecks.md check: N place(s), revised.` or `ManualChecks.md check: nothing unclear.` — and a failure of either dispatch is noted and stops nothing.

## Depth by task scale

The axis decides depth, not existence: whether this file appears at all is `manual_checks`. The value arrives in the contract as `manual_checks`; `conventions/task-settings.md` holds the chain it was resolved along. At either value of `scale` it is written when that switch says so — it is the only record of ground nothing verified, and `conventions/task-scale.md ## The floor` keeps what carries a guarantee.

`lite` halves the section ceilings — a case to 20 lines — and drops `## Troubleshooting`, and cuts no required field of a case. A case missing its `**Failure looks like:**` is not shorter, it is unusable. `## Manual acceptance` at `lite` runs to about three lines, one when there is nothing to list — an expected size, not a ceiling: a task with five checks nothing can automate lists five.

## Review

This artifact is read at Review like any other the task produced. A case that cannot be executed as written is an ordinary finding, judged by `## The case` and `## Grounding`; an empty case and a claim about behaviour with no code reference are findings too. Review and `## Check` are the only checks that run against a real task: a test can hold the spec, never the artifact made from it.
