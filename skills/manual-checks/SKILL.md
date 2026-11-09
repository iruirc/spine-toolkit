---
name: manual-checks
description: "Use at Plan to enumerate what a task's automation will not be able to check, and at Validation to turn that list into `ManualChecks.md` — the QA test cases a tester runs by hand after the run: a state they can reach, steps they can follow in the words of the screen, and a verdict they can settle. Governed by `[MANUAL_CHECKS]` and `[MANUAL_CHECKS_CHECK]` in Task.md and the project config."
---

# Manual Checks

`ManualChecks.md` is the only artifact of a task that a person **executes**. Every other one is read. That is the whole difference in how it has to be written: prose that is a tenth vague costs a re-read, a case that is a tenth vague cannot be run at all.

> **Related skills:**
> - `artifact-reader` — the style rules every task artifact follows; this skill sets this file's reader and its format
> - `ops-checklist` — the same late stage, the opposite direction: evidence for what WAS verified. A case deferred here is a Pending item there
> - `task-walkthrough` — narrative for a reader; this is a procedure a tester runs
> - `feature-requirements` — the Secondary list is where checks nothing can automate first become visible

## The reader

The reader is a tester who knows the product but not the code, and was not on this task. They install a build, use the app and record the screen. They do not open the sources, edit a configuration or run a terminal. Everything else in this skill follows from that:

- Steps, expectations, `**Preconditions:**` and `**What it checks:**` use only words from the screen: screen names, button labels, menu items, the text the app shows. No class name, no resource key, no file name.
- Code references live only in `**Code:**`. That field is for the developer who fixes a failure; the tester never needs it.
- Explain the product where a step depends on it: "the stepper is the minus button, the number and the plus button on an item row". The word table of `## Preparation` is where that goes.
- Do not assume the task. Which build to install, which account and data to use, what a failure looks like — none of that is in the tester's head.

The style rules every task artifact follows — one statement per sentence, a blank line before every field, list and table — are in the `artifact-reader` skill. This skill adds the reader and the format of this one file.

Before writing, read the example for the project's language: `examples/manual-checks.en.md` or `examples/manual-checks.ru.md`, and the English one for any other language. Match its density, not its content.

## Two stages, two halves

**Plan → `## Manual acceptance`.** A list, not procedures: one line per check this task's automation will not be able to make, stated as *what must be true — what changed*, never as *what to press*: "the cart icon's badge follows every quantity change — the badge now reads the cart's item count instead of its row count". The second half is the intent a case is built from; without it Validation guesses. It belongs here because here the task's acceptance criteria are still in front of the author. Nothing qualifies → the single line `Fully automatable.`

For BUG the reproduction replay is not listed: its steps are already in `Reproduce.md`, and Validation reads them from there.

**Validation → `ManualChecks.md`.** That list is the input; each line becomes a case. To it Validation adds what the plan could not know — what the automated pass actually covered, and what it could not reach at all. When the plan carries no such section, because the task entered mid-pipeline or predates this rule, say so in `## Scope` and derive the cases from the task file and the diff.

## Structure

```
# Manual Checks — <task>

[COVERS] = <sha>

## Run record
## Scope
## Preparation
## Reading the verdict
## Cases
## On failure — bug report
## Not covered
## Troubleshooting
## Charter
```

`[COVERS]` is the short sha the cases were written against. One line, and it answers the first question of anyone who opens the file later: is this about that build or not.

| Section | Content | Budget |
|---|---|---|
| `## Run record` | A table the tester fills in: Build (named from `[COVERS]`), Device / OS, Tester / date, and Summary as `PASS __ / FAIL __ / BLOCKED __` | 4 rows |
| `## Scope` | Current state only, no history of edits: in two or three plain sentences what the change does for the user; what the automated pass already covered, so nothing green is re-walked by hand; the number of cases and how long a run takes | ≤ 8 lines |
| `## Preparation` | The screen map and its word table, then the setup every case shares: the build (`**dev-only:**`), the device, and each shared scene | ≤ 60 lines |
| `## Reading the verdict` | For a verdict a developer reads from an instrument: the commands in full, what the fields mean, what separates one run from the next | ≤ 40 lines |
| `## Cases` | `### MC-<n>.`, one per check | ≤ 40 lines each |
| `## On failure — bug report` | The template a tester fills in for a failed case: Title, Build / device, Steps to reproduce, Actual, Expected, Attachments | 6 fields |
| `## Not covered` | Ground neither the automation nor these cases reach, one line each with its reason, or `none` | 1 line per item |
| `## Troubleshooting` | Symptom → cause → what to do, for the ways a tester misses that are not product defects | 1 row per symptom |
| `## Charter` | A timebox and what to look at: "10 minutes: change quantities in a long cart; a total that lags, a badge that disagrees, a row that jumps" | ≤ 3 lines |

**`[COVERS]`, `## Run record`, `## Scope`, `## Cases`, `## On failure` and `## Not covered` are always there.** The others are conditional. `## Preparation` appears as soon as a step uses a product word or a shared scene, which is nearly always. `## Reading the verdict` appears when an instrument command would otherwise be repeated in more than one case. `## Troubleshooting` appears when a case has a known way to go wrong that is not a product defect: the wrong account, a setting left changed, a cached build. `## Charter` appears when the change carries a gesture or a look the cases do not cover whole.

**`## Preparation`, in this order:**

1. `### Screen map` — a screen map for every screen the cases touch: an ASCII sketch in a fence, then a table headed `| Word in the cases | What it is on the screen |` with one row for every product word a step uses ("badge", "stepper", "total"). A word used in a step and missing from this table is a defect. Definitions live in this table, never inside a setup paragraph.
2. `### P0. Build` — how the build is made and installed. A developer does this, so it opens with `**dev-only:**`, and the tester never reads past that marker for it. Any other step that needs a code change, a configuration edit or a terminal is marked the same way.
3. `### P1. Device` — the device settings the cases rely on: interface language, permissions, account.
4. `### P2.` and on — each scene two or more cases start from, as a numbered table `| # | Action | Expected |`, ending with what to record as BLOCKED when the scene cannot be built.

A case names the scene it starts from in `**Preconditions:**`, and only what differs from it.

`## Not covered` is not a case list — nobody walks it. It exists so that later a missing case does not read as a passing one.

## The case

```
### MC-1. <the observable behaviour, not the symbol behind it>

**Priority:** P1 — the main scenario

**Traces to:** Plan.md, Manual acceptance, item 1

**What it checks:** the intent, in one line

**Preconditions:**

- The build from Run record is installed (Preparation, P0).
- The scene it starts from, and only what differs from it.

**Test data:** the concrete values the steps use

**Steps:**

| # | Action | Data | Expected | Actual |
|---|---|---|---|---|
| 1 | one action, on a named object in a named place | a value, or — | what the screen shows now | |

**Expected result:** the end state that passes the case

**By instrument:** (optional) the criterion and its threshold, for a developer-run verdict

**Failure looks like:** what is on the screen when it is broken

**Cleanup:** what to put back after the case, or —

**Code:** (cart/badge_counter.src:41)

**Status:** ☐ PASS ☐ FAIL ☐ BLOCKED — reason: ______

**Notes / attachments:** ______
```

The heading is `### MC-<n>. <observable behaviour>`. The id is stable: a refresh does not renumber the cases, and the id of a removed case is never reused. All twelve fields are always there; only `**By instrument:**` is optional, and it appears only when an instrument settles a verdict a developer reads. Each field earns itself:

- `**Priority:**` — P1 is the original defect or the main scenario, P2 an important side path, P3 a rare edge. It decides what is run when there is no time for all of it.
- `**Traces to:**` names the `## Manual acceptance` line or the acceptance criterion the case comes from.
- `**What it checks:**` is what lets a case be skipped knowingly. Without it the only way to learn what a case covers is to run it.
- `**Preconditions:**` is a state the tester can compare with the screen before the first step. A case that needs a fresh state says so in bold: "a **new** account, not the one from P1".
- `**Test data:**` carries every concrete value the steps use: names, prices, quantities, addresses.
- `**Steps:**` is the table above. `Expected` is what the screen shows right after that action; it is `—` only for a step that merely prepares the next one. `Actual` stays empty for the tester.
- `**Expected result:**` is the end state that passes the case, in one line.
- `**Expected result:**` and `**By instrument:**` are not alternatives. `**Expected result:**` answers "was the action performed at all?", the instrument answers "was it performed correctly?". A case carrying only the instrument cannot tell a defect from a fumbled step.
- `**Failure looks like:**` is the cheapest field and the strongest. A failure is recognised faster than a success is verified, and this is what turns "it did not add up" into "here is what is broken".
- `**Cleanup:**` puts back what the case changed: an item left in the cart, a setting switched. `—` when there is nothing.
- `**Code:**` holds the `(file:line)` references the case was grounded in. It is the only place in a case where code appears.
- `**Status:**` and `**Notes / attachments:**` are the tester's: a mark, a reason for BLOCKED, a screenshot or a recording.

Write a blank line before every field, list and table. Markdown joins consecutive lines into one paragraph, and a table with no blank line above it renders as plain text. The lint checks structure, not rendering, so open the preview before handing the file over.

**Language.** The section headings, `[COVERS]`, the table's column names and the field labels above stay English: they are the file's structure. So do the sub-headings of `## Preparation`: `### Screen map` and the scene ids `P0`…`Pn` are written in Latin letters in every language, and only a scene's title after its id is prose. A case's title after `### MC-<n>.`, the text after each label, the table's cells, and the text of every section — `## Scope`, `## Preparation`, `## Reading the verdict`, `## Troubleshooting`, `## Not covered`, `## Charter` — are prose in the project's `[LANG]` (`conventions/i18n.md` → Artifact authoring rule).

## Step rules

- **One row, one action.** An action on a named object in a named place, and what the screen shows right after it. "Then", "and then", "afterwards" or a semicolon inside `Action` mean two rows.
- **No "repeat steps".** "Repeat steps 3–5 twice" is not a step: write the rows out.
- **Cases are independent.** No case starts from "the state after case N": every case starts from its own `**Preconditions:**`, and a scene several cases share lives in `## Preparation`.
- **Every object is named and located.** "The plus button on the Green tea row", not "the add button".
- **An expectation is checkable.** A number, a text on the screen, an element present or absent. "Smoothly", "without a jump" or "about" only with a criterion a tester can apply by hand and eye: "before you can lift the finger", "wider than half the screen". A value that needs a tool goes to `**Test data:**` as a reference and to `**Notes / attachments:**` as "attach a screenshot, a developer checks it", or to `**By instrument:**`.
- **A case that cannot be run without a code change is BLOCKED for the tester**, and its `**Preconditions:**` say so.
- **Visible text is copied from the app verbatim.** Before writing, take every button, title and message from the app's string resources in the interface language that Run record names; the platform's validator says where those resources live. One language per file: never mix the label of one button in two languages.

## The lint

`scripts/lint-manual-checks.sh`, run on the file or on the task folder, is the executable definition of this format. The author runs it after writing the file and after every revision, repairs every finding it prints, and runs it again. Each finding is one line, `ManualChecks.md: <check>: <what> (<where>)`:

| Check | What it finds |
|---|---|
| `case` | a case heading that is not `### MC-<n>. <behaviour>`, a repeated id, a missing label, a `## Cases` with no `### MC-` case under it; a file of old `### <n>.` headings is named as the old format |
| `steps` | no steps table, a header other than the one in `## The case`, an empty `Action` or `Expected` (`—` is a value) |
| `compound` | two steps in one `Action`: "then", "and then", "afterwards", "repeat steps", a semicolon |
| `code` | code in `Action`, `Expected`, `**Preconditions:**` or `**What it checks:**`: a CamelCase word, a source file, a dotted name of three parts or more, a `(file:line)` |
| `codeslot` | a `**Code:**` with no `file:line` in it |
| `chain` | "after case N", "the state right after", or an edit history kept in the file |
| `scriptable` | a case in which every step is a command — a backticked command, or "run the command…": nothing in it needs a person, so it is a script, not a case (`## Does this check need a person?`) |
| `budget` | a case over 40 lines, `## Scope` over 8, `## Preparation` over 60 |
| `file` | no `[COVERS]`, no `## Run record`, no `## On failure` |

**How the budget counts.** A case's span runs from its heading to its last line, as raw lines: blank lines inside it count, and only the blank lines at either end do not. The twelve fields with their blank lines, a one-line `**Preconditions:**` list and two steps come to about 32 lines; each further step is one more line, so a case holds about ten steps. A case that needs more is two cases.

**Where the `code` check is wrong.** It reads a CamelCase product name (`YouTube`, `PayPal`) and a hostname or an address (`shop.example.com`) as code. There is no allow-list. Word around it: name the thing by what the screen shows ("the video service's red play logo", "the shop's address"), and put the literal name or address in the `Data` column or in `**Test data:**`, which the check does not read.

## Grounding

A case states what the code does, so it is written from the code, never from memory:

- Every claim about behaviour in `**Preconditions:**`, `Expected` and `**Failure looks like:**` — a direction, a limit, what a neighbouring element does — is checked against the code, and its reference goes into the case's `**Code:**`, never into the step. Advice from `Review.md` enters a case only after that check.
- A case about a resource or a style names, in `**Code:**`, the element that draws it and where it is used.
- A step uses only what exists in the build at `[COVERS]`; a check of what a later step of an epic adds is a `## Not covered` line with its reason.
- `scripts/lint-manual-checks.sh` names every case whose `**Code:**` carries no reference and every place code leaked out of it; `## The lint` says how its findings are repaired.
- **The empty case.** `**Failure looks like:**` is what the code before the change would show from the same preconditions. When it matches `**Expected result:**`, the case checks nothing: delete it, and give `## Not covered` a line with the reason.

## Refreshing

A Validation that finds `ManualChecks.md` with a `[COVERS]` behind HEAD refreshes it rather than rewriting it:

1. `git diff --name-only <COVERS>..HEAD` names the changed files.
2. A case with a code reference into one of them is checked again, and so is a case with no code reference at all; the others are left alone.
3. A new `## Manual acceptance` line becomes a case with the next unused id; a case automation now covers moves to `## Scope` with a reference to that evidence, and its id is not reused.
4. `[COVERS]` becomes HEAD.

## The instrument rule

A tester's verdict is written in what a person can **see**, and a tester's case needs no instrument. An instrument — a trace, a log, a parser, a profiler — settles a verdict a developer reads, from the build or from a snapshot the tester attaches. That instrument has to be runnable from this file: the command in full, and the value in its output that decides.

The command is written **once**, in `## Reading the verdict`. A case's `**By instrument:**` names only its own criterion — the measurement and the threshold it is judged against. Twelve cases do not repeat one invocation twelve times. When no command serves more than one case — a single case, or cases each measured differently — there is no such section and each command lives in its own case.

| | |
|---|---|
| Defect | `**By instrument:** the log shows the update` — no command anywhere, no threshold |
| Case | `**By instrument:** the badge refreshes within 300 ms of the tap`, with `## Reading the verdict` carrying the invocation that prints it |

Naming the instrument is not carrying it: an instrument mentioned by filename, with no invocation and no field to read, is a defect. The optional field is no way out of a criterion either: a case with no instrument still has an `**Expected result:**` a person can compare with the screen.

## The symbol rule

Neither `**Preconditions:**`, a cell of `**Steps:**`, nor `**Expected result:**` identifies a state by the name of a function, a file, or a variable. Nobody can reach *the quantity at the limit constant*; they can reach *ten Green tea in the cart*. A symbol belongs in `**Code:**`, never in the instruction.

## Check

`[MANUAL_CHECKS_CHECK]` decides whether the file is walked by someone who was not there before it is handed over; it reaches a run as the contract's `manual_checks_check`, `on` by default.

**When.** Validation returned `PASSED`, the file holds at least one case, and this Validation wrote or changed it — a case added, removed or rewritten; moving `[COVERS]` alone is no change. The author never checks its own file: the dispatcher does — the profile script under Method A, the workflow skill's main context under Method B.

**The reader** is a tester with no access to the code: a fresh dispatch of the validator's role, tuned `light`. Of the task and the repository it reads `ManualChecks.md` and nothing else — no other file of the task, no source file, no git — and returns two lists:

- `walk` — one line per step of every case, as the action it would take: "I press X there, and expect Y";
- `smells` — every place it could not execute as written, each with the case, the step, a quote of at most one line and what is missing, of one kind: `ambiguous` — an intent, or a step with no object and place; `unverified` — an action with no expectation, other than a preparing step; `precondition` — preconditions that cannot be compared with the screen; `tacit` — a term, a screen or data with no route to it; `oracle` — an expectation that cannot be compared with the screen; `access` — a step that cannot be done without the code or a terminal and is not marked `**dev-only:**`; `twofold` — an expectation that can be counted as passed in two ways; `chained` — a case that cannot be run alone.

**Revision.** An empty `smells` ends the check. Otherwise the author, with the code and the task, fixes in one pass every place named and every step `walk` retold wrongly, then runs the lint again. What is left is not checked again. The run notes one line — `ManualChecks.md check: N place(s), revised.` or `ManualChecks.md check: nothing unclear.` — and a failure of either dispatch is noted and stops nothing.

## Depth by task scale

The axis decides depth, not existence: whether this file appears at all is `manual_checks`. The value arrives in the contract as `manual_checks`; `conventions/task-settings.md` holds the chain it was resolved along. At either value of `scale` it is written when that switch says so — it is the only record of ground nothing verified, and `conventions/task-scale.md ## The floor` keeps what carries a guarantee.

`lite` halves `## Preparation` and `## Reading the verdict`, drops `## Troubleshooting`, and cuts no required field of a case; a case, `## Scope` and `## Charter` keep theirs. Twelve fields with two steps already fill about 32 lines, so a case keeps its 40 lines at `lite` too: a case missing its `**Failure looks like:**` is not shorter, it is unusable. `## Manual acceptance` at `lite` runs to about three lines, one when there is nothing to list — an expected size, not a ceiling: a task with five checks nothing can automate lists five.

## Review

This artifact is read at Review like any other the task produced. A case a tester cannot execute as written is an ordinary finding, judged by `## The case` and `## Grounding`; an empty case and a claim about behaviour with no code reference in `**Code:**` are findings too. Review and `## Check` are the only checks that run against a real task: a test can hold the spec, never the artifact made from it.
