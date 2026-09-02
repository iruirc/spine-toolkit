---
name: manual-checks
description: "Use at Plan to enumerate what a task's automation will not be able to check, and at Validation to turn that list into `ManualChecks.md` — the hand-run script a person executes after the run: a state they can reach, steps they can follow, and a verdict they can settle. Governed by `[MANUAL_CHECKS]` in Task.md and `## Validation` in CLAUDE-spine-toolkit.md."
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

**Plan → `## Manual acceptance`.** A list, not procedures: one line per check this task's automation will not be able to make, stated as *what must be true*, never as *what to press*. It belongs here because here the task's acceptance criteria are still in front of the author. Nothing qualifies → the single line `Fully automatable.`

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
```

`[COVERS]` is the short sha the cases were written against. One line, and it answers the only question a reader has a month later: is this about that build or not.

| Section | Content | Budget |
|---|---|---|
| `## Scope` | What the automated pass already covered, named, so nothing green is re-walked by hand; and what this file is for | ≤ 8 lines |
| `## Preparation` | The one-time setup every case shares: how it is built, how it is configured, what data to load, how to reach the thing at all | ≤ 60 lines |
| `## Reading the verdict` | How to take the instrument's reading and how to read it: the commands in full, what the fields mean, what separates one run from the next | ≤ 40 lines |
| `## Cases` | Numbered, one per check | ≤ 25 lines each |
| `## Troubleshooting` | Symptom → cause → what to do, for the ways a doer misses that are not product defects | 1 row per symptom |
| `## Not covered` | Ground neither the automation nor these cases reach, one line each with its reason, or `none` | 1 line per item |

**`## Preparation`, `## Reading the verdict` and `## Troubleshooting` are conditional.** The first two appear when they would otherwise be repeated in more than one case — twelve cases must not each re-explain how to build with tracing on. The third appears when a case has a known way to go wrong that is not a product defect: the instrument was never switched on, the wrong device was picked, the settings were left shifted. A task with two simple cases is `## Scope` + `## Cases` + `## Not covered` and nothing else.

`## Not covered` is not a case list — nobody walks it. It exists so that a month later a missing case does not read as a passing one.

## The case

```
### N. <the observable behaviour, not the symbol behind it>

**What it checks:** the intent, in one line
**Scene:** the state this case starts from, as a delta on ## Preparation
**Steps:**
1. one action
2. one action
**By eye:** what a person sees when it works
**By instrument:** the criterion, and the value that carries it
**Failure looks like:** the signature of a failure
```

`**By instrument:**` appears only when an instrument settles the verdict. The other five are always there, and each earns itself:

- `**What it checks:**` is what lets a case be skipped knowingly. Without it the only way to learn what a case covers is to run it.
- `**By eye:**` and `**By instrument:**` are not alternatives. The eye answers "was the action performed at all?", the instrument answers "was it performed correctly?". A case carrying only the instrument cannot tell a defect from a fumbled step.
- `**Failure looks like:**` is the cheapest field and the strongest. A failure is recognised faster than a success is verified, and this is what turns "it did not add up" into "here is what is broken".

Three rules on top of the fields:

- **One step, one action.** A compound sentence is not a step. This is the artifact's floor, and the one that cannot be faked: splitting "grab it, drag it into the zone, hold two seconds, release" into four steps forces the author to say, on the third, how the doer knows the zone was reached.
- **A case names its delta, not its neighbour.** Reusing another case's steps is legal when the step number and the change are both named and the case carries its own `**Scene:**` — "repeat case 1, but hold four to five seconds at step 4" is executable. A bare "as in case 1" with no delta is not.
- **Data is named.** A case needing data the repository does not carry says how to get it. When there is a lot of it, it moves to `## Preparation` and `**Scene:**` names the set it wants.

## The instrument rule

An expectation is written in what a person can **see**. When the verdict comes from an instrument — a trace, a log, a parser, a profiler — that instrument has to be runnable from this file: the command in full, and the value in its output that decides.

The command is written **once**, in `## Reading the verdict`. A case's `**By instrument:**` names only its own criterion — the measurement and the threshold it is judged against. Twelve cases do not repeat one invocation twelve times. When there is a single case and no such section, the command lives in the case.

| | |
|---|---|
| Defect | `**By instrument:** the trace shows the engaged frames` — no command anywhere, no threshold |
| Case | `**By instrument:** drift/path for this scenario → under a quarter percent`, with `## Reading the verdict` carrying the invocation that prints it |

Naming the instrument is not carrying it: an instrument mentioned by filename, with no invocation and no field to read, is a defect.

## The symbol rule

Neither `**Scene:**` nor either expectation identifies a state by the name of a function, a file, or a variable. Nobody can reach *almost at the minimum-duration constant*; they can reach *compressed until it stops compressing*. A symbol is allowed in parentheses as a gloss, never as the instruction.

## Scale

The axis decides depth, not existence: whether this file appears at all is `manual_checks` (`Task.md [MANUAL_CHECKS]` → `CLAUDE-spine-toolkit.md ## Validation`). At either value of `scale` it is written when that switch says so — it is the only record of ground nothing verified, and `conventions/task-scale.md ## The floor` keeps what carries a guarantee.

`lite` halves the section ceilings and drops `## Troubleshooting`, and cuts no required field of a case. A case missing its `**Failure looks like:**` is not shorter, it is unusable. `## Manual acceptance` at `lite` is three lines, one when there is nothing to list.

## Review

This artifact is read at Review like any other the task produced. A case that cannot be executed as written is an ordinary finding, judged by the two rules above. That is the only check which runs against a real task: a test can hold the spec, never the artifact made from it.
