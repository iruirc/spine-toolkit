---
name: manual-checks
description: "Use at Plan to decide which checks need a person and route the rest into automation, and at Validation to turn the ones left into `ManualChecks.md` — the QA test cases a tester runs by hand after the run: a state they can reach, steps they can follow in the words of the screen, and a verdict they can settle. Governed by `[MANUAL_CHECKS]` and `[MANUAL_CHECKS_CHECK]` in Task.md and the project config."
---

# Manual Checks

`ManualChecks.md` is the only artifact of a task that a person **executes**. Every other one is read. That is the whole difference in how it has to be written: prose that is a tenth vague costs a re-read, a case that is a tenth vague cannot be run at all.

> **Related skills:**
> - `artifact-reader` — the style rules every task artifact follows; this skill sets this file's reader and its format
> - `ops-checklist` — the same late stage, the opposite direction: evidence for what WAS verified. A case deferred here is a Pending item there
> - `task-walkthrough` — narrative for a reader; this is a procedure a tester runs
> - `feature-requirements` — the Secondary list is where checks nothing can automate first become visible

## The reader

The reader is a tester who knows the product but not the code, and was not on this task. They install a build and use the app. They do not open the sources, edit a configuration or run a terminal. Everything else in this skill follows from that:

- Steps, expectations, `**Preconditions:**` and `**What it checks:**` use only words from the screen: screen names, button labels, menu items, the text the app shows. No class name, no resource key, no file name.
- Code references live only in `## Code references`, the last section of the file. That section is for the developer who fixes a failure; the tester never reads it.
- Explain the product where a step depends on it: "the stepper is the minus button, the number and the plus button on an item row". The word table of `## Preparation` is where that goes.
- Do not assume the task. Which build to install, which account and data to use, what a failure looks like — none of that is in the tester's head.

The style rules every task artifact follows — one statement per sentence, a blank line before every field, list and table — are in the `artifact-reader` skill. This skill adds the reader and the format of this one file.

Before writing, read the example for the project's language: `examples/manual-checks.en.md` or `examples/manual-checks.ru.md`, and the English one for any other language. Match its density, not its content.

## Two stages, two halves

**Plan → `## Manual acceptance`.** A list, not procedures: one line per check that needs a person by `## Does this check need a person?`, stated as *what must be true — what changed*, never as *what to press*: "the cart icon's badge follows every quantity change — the badge now reads the cart's item count instead of its row count — needs: visual judgment". The middle part is the intent a case is built from; without it Validation guesses. Each line ends with `needs:` and which of the three it needs — the tag is `needs: device action | visual judgment | external service`, one value or several. A line with no tag is not allowed: either the author can name why a person is needed, or no person is. It belongs here because here the task's acceptance criteria are still in front of the author. Nothing qualifies → the single line `Fully automatable.`

A check that needs no person is not listed. One worth automating (`automate`) is work for a phase: the script or the test that phase writes, named in its `**Verification:**` line. One not worth it (`drop`) is a line in `## Not automated`, under `## For the implementer`, with its reason — the gap the task accepts knowingly, and one `ManualChecks.md` never sees.

For BUG the reproduction replay is not listed: its steps are already in `Reproduce.md`, and Validation reads them from there.

**Validation → `ManualChecks.md`.** That list is the input, and each line goes through `## Does this check need a person?` again: the plan may predate this rule, or may have missed it. A line that needs a person becomes a case. One this run checked itself, with evidence, is `covered`: a line in `## Scope` naming the evidence. Any other is an automatable gap: a `## Not covered` line, "automatable, not automated by this task", or a part of the `manual checks: none —` line when there is no file — the validator writes no code. To it Validation adds what the plan could not know — what the automated pass actually covered, and what it could not reach at all; a check deferred because driving the app was suppressed goes through the same criterion. When the plan carries no such section, because the task entered mid-pipeline or predates this rule, say so in `## Scope` and derive the cases from the task file and the diff.

**No case, no file.** Under `auto`, when no case is left, there is no `ManualChecks.md`. `Validation.md` carries the line `manual checks: none — <why>`, naming what was covered and each automatable gap, and the Manual test pass item of `OpsChecklist.md` is N/A with that reason. `always` writes the file anyway; with no case left, its `## Cases` reads `none — <why>`.

## Does this check need a person?

Does the diff change this behaviour? Ask that first, before the three below, and take "change" as the `ops-checklist` skill defines touches: directly or through code on its path. When the diff does not change it, the check is neither a case nor a Pending: it is a line in `## Not covered` with its reason, or N/A in `OpsChecklist.md`. A constraint of the implementation ("no network is used") is not a behaviour the diff changes, so it gets no case. The same holds for a check deferred because of a driver that could not reach it: that is a reason the run could not do it, never a reason a person must.

A `## Manual acceptance` of `Fully automatable.` does not forbid a case. When Validation still writes one, its `**What it checks:**` names the change of the diff it checks.

When the diff does change it, a check needs a person only when it requires at least one of three things:

| Needs | Examples |
|---|---|
| device action — an action on a device or a system that a machine will not take | airplane mode, unplugging a cable, answering a system prompt, rotating the phone |
| visual judgment — a judgement by eye | "smooth", "readable", "not clipped", "matches the mockup" |
| external service — an account or a service outside the repository | a sandbox purchase, signing in with a real account |

A check that needs none of them is not a case. It gets one of three outcomes:

| Outcome | When | Where it is decided and recorded |
|---|---|---|
| `automate` | a sequence of commands with a result that can be checked | at Plan: work for a phase — a script or a test in the repository, named in that phase's `**Verification:**` line; Validation runs it |
| `covered` | Validation, or automation already run, checked it, and the evidence exists | `## Scope`, with a reference to the evidence; `Validation.md` when there is no file |
| `drop` | it costs more than it is worth, or its outcome changes nothing | at Plan: a line in `## Not automated` with its reason |

**A check deferred because nothing could drive the app in this run** — `drive_app` off, no driver, a driver that cannot reach the surface — and that the diff changes is a device action: driving the app is exactly what the run could not do, so it needs a person. The BUG reproduction replay is one, and it stays a case. "Automatable, not automated" is for a check a script could make, never for one only a driver could.

**A mixed check** — one or two actions of a person inside a check made of commands — is not written as a case of steps. Plan makes it work for a phase: a script that does everything itself, stops at a prompt where the person is needed ("turn on airplane mode, press Enter") and prints PASS or FAIL. It lives where the project keeps its scripts. In `ManualChecks.md` its launch is a `**dev-only:**` step in `## Preparation`; the case holds only the person's steps, and its `**Expected result:**` is the verdict the script prints.

The lint's `scriptable` check is the backstop: a case whose every step is a command is named, whatever the plan said.

## Structure

```
# Manual Checks — <task>

[COVERS] = <sha>

## Run record
## Scope
## Preparation
## Cases
## On failure — bug report
## Not covered
## Troubleshooting
## Charter
## Code references
```

`[COVERS]` is the short sha the cases were written against. One line, and it answers the first question of anyone who opens the file later: is this about that build or not.

| Section | Content | Budget |
|---|---|---|
| `## Run record` | A table the tester fills in: Build (named from `[COVERS]`), Device / OS, Tester / date, and Summary as `PASS __ / FAIL __ / BLOCKED __` | 4 rows |
| `## Scope` | Current state only, no history of edits: in two or three plain sentences what the change does for the user; what the automated pass already covered, so nothing green is re-walked by hand; the number of cases and how long a run takes | ≤ 8 lines |
| `## Preparation` | The screen map and its word table, then the setup every case shares: the build (`**dev-only:**`), the device, and each shared scene | ≤ 60 lines |
| `## Cases` | `### MC-<n>.`, one per check | ≤ 40 lines each |
| `## On failure — bug report` | The template a tester fills in for a failed case: Title, Build / device, Steps to reproduce, Actual, Expected, Attachments | 6 fields |
| `## Not covered` | Ground neither the automation nor these cases reach, one line each with its reason, or `none` | 1 line per item |
| `## Troubleshooting` | Symptom → cause → what to do, for the ways a tester misses that are not product defects | 1 row per symptom |
| `## Charter` | A timebox and what to look at: "10 minutes: change quantities in a long cart; a total that lags, a badge that disagrees, a row that jumps" | ≤ 3 lines |
| `## Code references` | A table headed `\| Case \| Code \|`, one row per case, `\| MC-<n> \| (file:line), … \|`; the tester never reads it | 1 row per case |

**`[COVERS]`, `## Run record`, `## Scope`, `## Cases`, `## On failure` and `## Not covered` are always there, and so is `## Code references` whenever the file holds a case.** A file whose `## Cases` reads `none — <why>` has no references section. The others are conditional. `## Preparation` appears as soon as a step uses a product word or a shared scene, which is nearly always. `## Troubleshooting` appears when a case has a known way to go wrong that is not a product defect: the wrong account, a setting left changed, a cached build. `## Charter` appears when the change carries a gesture or a look the cases do not cover whole.

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

**Failure looks like:** what is on the screen when it is broken

**Cleanup:** what to put back after the case, or —

**Status:** ☐ PASS ☐ FAIL ☐ BLOCKED — reason: ______

**Notes / attachments:** ______
```

The heading is `### MC-<n>. <observable behaviour>`. The id is stable: a refresh does not renumber the cases, and the id of a removed case is never reused. All eleven fields are always there. Each field earns itself:

- `**Priority:**` — P1 is the original defect or the main scenario, P2 an important side path, P3 a rare edge. It decides what is run when there is no time for all of it.
- `**Traces to:**` names the `## Manual acceptance` line or the acceptance criterion the case comes from.
- `**What it checks:**` is what lets a case be skipped knowingly. Without it the only way to learn what a case covers is to run it.
- `**Preconditions:**` is a state the tester can compare with the screen before the first step. A case that needs a fresh state says so in bold: "a **new** account, not the one from P1".
- `**Test data:**` carries every concrete value the steps use: names, prices, quantities, addresses.
- `**Steps:**` is the table above. `Expected` is what the screen shows right after that action; it is `—` only for a step that merely prepares the next one. `Actual` stays empty for the tester.
- `**Expected result:**` is the end state that passes the case, in one line.
- `**Failure looks like:**` is the cheapest field and the strongest. A failure is recognised faster than a success is verified, and this is what turns "it did not add up" into "here is what is broken".
- `**Cleanup:**` puts back what the case changed: an item left in the cart, a setting switched. `—` when there is nothing.
- The `(file:line)` references a case was grounded in are its row in `## Code references`, never a field of the case.
- `**Status:**` and `**Notes / attachments:**` are the tester's: a mark, a reason for BLOCKED, a screenshot of what failed.

Write a blank line before every field, list and table. Markdown joins consecutive lines into one paragraph, and a table with no blank line above it renders as plain text. The lint checks structure, not rendering, so open the preview before handing the file over.

**Language.** The section headings, `[COVERS]`, the table's column names and the field labels above stay English: they are the file's structure. So do the sub-headings of `## Preparation`: `### Screen map` and the scene ids `P0`…`Pn` are written in Latin letters in every language, and only a scene's title after its id is prose. A case's title after `### MC-<n>.`, the text after each label, the table's cells, and the text of every section — `## Scope`, `## Preparation`, `## Troubleshooting`, `## Not covered`, `## Charter` — are prose in the project's `[LANG]` (`conventions/i18n.md` → Artifact authoring rule).

## What a case must prove

A case earns a tester's time only when its verdict says something about this change. Five rules decide that.

**It tells the build before the change from the build after.** On the build before the change the case fails; on the build after it passes. Checks that pass the same on both fold into one case, "nothing broke", whose `**What it checks:**` says it is not a check of the fix. When automated tests or the driver already cover that regression, there is no such case, and `## Scope` names the evidence.

**It checks what the diff touches.** An item of `OpsChecklist.md` becomes a case only when the diff touches that behaviour, as the `ops-checklist` skill defines touches. Otherwise the item is N/A, with its reason, by that skill. The one nothing-broke case is the only case not built on changed code. Its row in `## Code references` names the code of the behaviour it guards.

**It is settled by eye when the difference shows at normal speed.** That is so when the defect was found by eye, or when the check is tagged `visual judgment`. When the eye is unsure, the case says what to look for, and the eye decides. The person never reads frames, traces or logs. When no eye can see the difference at all, the check is no case of this file: `## No instrument in the file` says where it goes.

**It holds no line for a developer.** Outside `**dev-only:**` steps and `## Code references`, no line is for a developer. Measurements, internal terms and the history of edits go to `Validation.md` or `Walkthrough.md`. Code references go to `## Code references`.

**It is one check, one case.** The conditions a check is run under — language, theme, text size, device, orientation — are a table of conditions in **Test data:**, and the steps are walked once per row. A check that differs from another only in its conditions is a row of that case, never a second case. The status is one, and a condition that broke is named in its reason. A case about how a screen looks reaches the screen and does not walk again what ## Scope calls covered.

The first two rules hold for a task that changes product behaviour. On a task whose diff changes no product behaviour — a TEST task, a change to docs or tests only — the first rule does not apply. There a case checks the behaviour the task targets that automation could not reach, which is what `[MANUAL_CHECKS]` `always` asks of such a run.

## Step rules

- **One row, one action.** An action on a named object in a named place, and what the screen shows right after it. "Then", "and then", "afterwards" or a semicolon inside `Action` mean two rows.
- **No "repeat steps".** "Repeat steps 3–5 twice" is not a step: write the rows out.
- **Cases are independent.** No case starts from "the state after case N": every case starts from its own `**Preconditions:**`, and a scene several cases share lives in `## Preparation`.
- **Every object is named and located.** "The plus button on the Green tea row", not "the add button".
- **An expectation is checkable.** A number, a text on the screen, an element present or absent. "Smoothly", "without a jump" or "about" only with a criterion a tester can apply by hand and eye: "before you can lift the finger", "wider than half the screen". A value that needs a tool is no step: it is a measurement the agent takes in `Validation.md`, or a `## Not covered` line (`## No instrument in the file`).
- **A case that cannot be run without a code change is BLOCKED for the tester**, and its `**Preconditions:**` say so.
- **Visible text is copied from the app verbatim.** Before writing, take every button, title and message from the app's string resources in the interface language that Run record names; the platform's validator says where those resources live. One language per file: never mix the label of one button in two languages.

## The lint

`scripts/lint-manual-checks.sh`, run on the file or on the task folder, is the executable definition of this format. The author runs it after writing the file and after every revision, repairs every finding it prints, and runs it again. Each finding is one line, `ManualChecks.md: <check>: <what> (<where>)`:

| Check | What it finds |
|---|---|
| `case` | a case heading that is not `### MC-<n>. <behaviour>`, a repeated id, a missing label, a `## Cases` with no `### MC-` case under it; a file of old `### <n>.` headings, or with a `**Code:**` field inside a case, is named once as the old format |
| `steps` | no steps table, a header other than the one in `## The case`, an empty `Action` or `Expected` (`—` is a value) |
| `compound` | two steps in one `Action`: "then", "and then", "afterwards", "repeat steps", a semicolon |
| `code` | code in `Action`, `Expected`, `**Preconditions:**` or `**What it checks:**`: a CamelCase word, a source file, a dotted name of three parts or more, a `(file:line)` |
| `codeslot` | a case with no row in `## Code references`, a row with no `file:line` in it, a row for a case not in `## Cases` |
| `instrument` | an instrument in the file a person walks: an instrument field in a case, a section of instrument commands, a step or a field that asks the tester to record the screen (`## No instrument in the file`) |
| `chain` | "after case N", "the state right after", or an edit history kept in the file |
| `scriptable` | a case in which every step is a command — a backticked command, or "run the command…": nothing in it needs a person, so it is a script, not a case (`## Does this check need a person?`). The repair routes the case — `covered` in `## Scope`, or an automatable gap — and under `auto` the last one routed away takes the file with it; rewording the steps is not a repair |
| `budget` | a case over 40 lines, `## Scope` over 8, `## Preparation` over 60 |
| `file` | no `[COVERS]`, no `## Run record`, no `## On failure`, no `## Code references` in a file that holds a case |

**How the budget counts.** A case's span runs from its heading to its last line, as raw lines: blank lines inside it count, and only the blank lines at either end do not. The eleven fields with their blank lines, a one-line `**Preconditions:**` list and two steps come to about 30 lines; each further step is one more line, so a case holds about twelve steps. A case that needs more is two cases.

**Where the `code` check is wrong.** It reads a CamelCase product name (`YouTube`, `PayPal`) and a hostname or an address (`shop.example.com`) as code. There is no allow-list. Word around it: name the thing by what the screen shows ("the video service's red play logo", "the shop's address"), and put the literal name or address in the `Data` column or in `**Test data:**`, which the check does not read.

## Grounding

A case states what the code does, so it is written from the code, never from memory:

- Every claim about behaviour in `**Preconditions:**`, `Expected` and `**Failure looks like:**` — a direction, a limit, what a neighbouring element does — is checked against the code, and its reference goes into the case's row in `## Code references`, never into the step. Advice from `Review.md` enters a case only after that check.
- A case about a resource or a style names, in its row of `## Code references`, the element that draws it and where it is used.
- A step uses only what exists in the build at `[COVERS]`; a check of what a later step of an epic adds is a `## Not covered` line with its reason.
- `scripts/lint-manual-checks.sh` names every case with no reference in `## Code references` and every place code leaked out of it; `## The lint` says how its findings are repaired.
- **The empty case.** `**Failure looks like:**` is what the code before the change would show from the same preconditions. When it matches `**Expected result:**`, the case checks nothing: delete it, and give `## Not covered` a line with the reason — or, when it guards a regression, make it part of the one nothing-broke case (`## What a case must prove`).

## Refreshing

A Validation that finds `ManualChecks.md` with a `[COVERS]` behind HEAD refreshes it rather than rewriting it:

1. `git diff --name-only <COVERS>..HEAD` names the changed files.
2. A case with a code reference into one of them is checked again, and so is a case with no code reference at all; the others are left alone.
3. A new `## Manual acceptance` line goes through `## Does this check need a person?`; one that needs a person becomes a case with the next unused id; a case automation now covers moves to `## Scope` with a reference to that evidence, and its id is not reused.
4. A file with `**Code:**` inside its cases is the old format: move each into `## Code references` as that case's row. A file no Validation refreshes stays as it is.
5. `[COVERS]` becomes HEAD.

## No instrument in the file

A tester's verdict is written in what a person can **see**, so the file a person walks holds no instrument: no instrument field in a case, no section of instrument commands, and no field, section or step of a case asks the person to record the screen, because nobody reads a recording. A measurement the agent can make itself is made in the run and recorded in `Validation.md`. A measurement it cannot make is a line in `## Not covered`, with its reason, so that its absence does not read as a pass. Naming a trace, a log or a profiler in a case is a defect all the same: the tester cannot run it.

## The symbol rule

Neither `**Preconditions:**`, a cell of `**Steps:**`, nor `**Expected result:**` identifies a state by the name of a function, a file, or a variable. Nobody can reach *the quantity at the limit constant*; they can reach *ten Green tea in the cart*. A symbol belongs in `## Code references`, never in the instruction.

## Check

`[MANUAL_CHECKS_CHECK]` decides whether the file is walked by someone who was not there before it is handed over; it reaches a run as the contract's `manual_checks_check`, `on` by default.

**When.** Validation returned `PASSED`, the file holds at least one case, and this Validation wrote or changed it — a case added, removed or rewritten; moving `[COVERS]` alone is no change. The author never checks its own file: the dispatcher does — the profile script under Method A, the workflow skill's main context under Method B.

**The reader** is a tester with no access to the code: a fresh dispatch of the validator's role, tuned `light`. Of the task and the repository it reads `ManualChecks.md`, except its `## Code references`, and nothing else — no other file of the task, no source file, no git — and returns two lists:

- `walk` — one line per step of every case, as the action it would take: "I press X there, and expect Y";
- `smells` — every place it could not execute as written, each with the case, the step, a quote of at most one line and what is missing, of one kind: `ambiguous` — an intent, or a step with no object and place; `unverified` — an action with no expectation, other than a preparing step; `precondition` — preconditions that cannot be compared with the screen; `tacit` — a term, a screen or data with no route to it; `oracle` — an expectation that cannot be compared with the screen; `access` — a step that cannot be done without the code or a terminal and is not marked `**dev-only:**`; `twofold` — an expectation that can be counted as passed in two ways; `chained` — a case that cannot be run alone; `redundant` — a repeat, a case that repeats another under other conditions, a caveat said a second time, text not for this reader: a measurement, an internal term, an edit history. `**dev-only:**` steps and `## Code references` are for a developer by design, and neither is ever a `redundant` place.

**Revision.** An empty `smells` ends the check. Otherwise the author, with the code and the task, fixes in one pass every place named and every step `walk` retold wrongly, then runs the lint again. The revision deletes a `redundant` place, never rewrites it. A place where something is missing is closed by rewording first, and by adding text only when rewording cannot close it. What is left is not checked again. The run notes one line — `ManualChecks.md check: N place(s), revised, A → B lines.`, A and B being the file's lines before and after the revision, or `ManualChecks.md check: nothing unclear.` When B is above A, the line goes on: `The revision lengthened the file.` A failure of either dispatch is noted and stops nothing.

## Depth by task scale

The axis decides depth, not existence: whether this file appears at all is `manual_checks`. The value arrives in the contract as `manual_checks`; `conventions/task-settings.md` holds the chain it was resolved along. At either value of `scale` it is written when that switch says so — it is the only record of ground nothing verified, and `conventions/task-scale.md ## The floor` keeps what carries a guarantee.

`lite` halves `## Preparation`, drops `## Troubleshooting`, and cuts no required field of a case; a case, `## Scope` and `## Charter` keep theirs. Eleven fields with two steps already fill about 30 lines, so a case keeps its 40 lines at `lite` too: a case missing its `**Failure looks like:**` is not shorter, it is unusable. `## Manual acceptance` at `lite` runs to about three lines, one when there is nothing to list — an expected size, not a ceiling: a task with five checks that need a person lists five.

## Review

This artifact is read at Review like any other the task produced. A case a tester cannot execute as written is an ordinary finding, judged by `## The case` and `## Grounding`; an empty case and a claim about behaviour with no reference in `## Code references` are findings too. So are a case that needs no person by `## Does this check need a person?` and a `## Manual acceptance` line with no `needs:`; neither blocks. By `## What a case must prove`, three more findings block nothing either: a case that does not tell the build before the change from the build after, a case on behaviour the diff did not touch, and a step that has a person measure what the eye can see. Review and `## Check` are the only checks that run against a real task: a test can hold the spec, never the artifact made from it.
