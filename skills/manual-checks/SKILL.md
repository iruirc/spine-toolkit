---
name: manual-checks
description: "Use at Plan to decide which checks need a person and route the rest into automation, and at Validation to turn the ones left into `ManualChecks.md` — the QA test cases a tester runs by hand after the run: a state they can reach, steps they can follow in the words of the screen, and a verdict they can settle. Governed by `[MANUAL_CHECKS]` and `[MANUAL_CHECKS_CHECK]` in Task.md and the project config."
---

# Manual Checks

`ManualChecks.md` is the only artifact of a task that a person **executes**. Every other one is read. That is the whole difference in how it has to be written: prose that is a tenth vague costs a re-read, a case that is a tenth vague cannot be run at all.

The file comes in two styles, and the contract's `manual_checks_style` decides which one a run writes: `brief`, the default, for a tester who knows the app but not the task, or `full`, which also explains the product and carries a run record. The file names its style in the line `[STYLE] = <value>` after `[COVERS]`. Where the rest of this skill describes the file, it describes `full`; `## Brief` says what `brief` keeps of it and what it changes.

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

Does the diff change this behaviour? Ask that first, before the three below, and take "change" as the `ops-checklist` skill defines touches: directly or through code on its path. When the diff does not change it, the check is neither a case nor a Pending: it is a line in `## Not covered` with its reason, or N/A in `OpsChecklist.md`. A constraint of the implementation ("no network is used") is not a behaviour the diff changes, so it gets no case. The same holds for a check the diff does not change that was deferred because a driver could not reach it: that alone is a reason the run could not do it, never a reason a person must. On a task whose diff changes no product behaviour, the question reads: does automation leave the behaviour the task targets unchecked? The one nothing-broke case is the exception: it guards a regression on a path the diff touches, so it is not behaviour the diff does not change.

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

**A check deferred because nothing could drive the app in this run** — `drive_app` off, no driver, a driver that cannot reach the surface — and that the diff changes is a device action: driving the app is exactly what the run could not do, so it needs a person. The BUG reproduction replay is one, and it stays a case. Under `manual_checks_pass` = `end` the check is deferred to a collective pass, where a driver is usually there: such a check that was deferred only because of the driver is marked `**Runner:** agent` instead of being a device action (`## Marks for a collective pass`); it stays a case of the step's `ManualChecks.md` and counts as a case when `[MANUAL_CHECKS]` = `auto` decides whether the file is written. A check that needs a person for another reason stays a device action. Under `per-step` the deferred check is a device action, whatever the reason. "Automatable, not automated" is for a check a script could make, never for one only a driver could.

**A mixed check** — one or two actions of a person inside a check made of commands — is not written as a case of steps. Plan makes it work for a phase: a script that does everything itself, stops at a prompt where the person is needed ("turn on airplane mode, press Enter") and prints PASS or FAIL. It lives where the project keeps its scripts. In `ManualChecks.md` its launch is a `**dev-only:**` step in `## Preparation`; the case holds only the person's steps, and its `**Expected result:**` is the verdict the script prints.

The lint's `scriptable` check is the backstop: a case whose every step is a command is named, whatever the plan said.

## Structure

```
# Manual Checks — <task>

[COVERS] = <sha>

[STYLE] = full

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

`[COVERS]` is the short sha the cases were written against. One line, and it answers the first question of anyone who opens the file later: is this about that build or not. `[STYLE]` is the style the file is written in.

| Section | Content |
|---|---|
| `## Run record` | A table the tester fills in: Build (named from `[COVERS]`), Device / OS, Tester / date, and Summary as `PASS __ / FAIL __ / BLOCKED __` |
| `## Scope` | Current state only, no history of edits: in two or three plain sentences what the change does for the user; what the automated pass already covered, so nothing green is re-walked by hand; the number of cases and how long a run takes |
| `## Preparation` | The screen map and its word table, then the setup every case shares: the build (`**dev-only:**`), the device, and each shared scene |
| `## Cases` | `### MC-<n>.`, one per check |
| `## On failure — bug report` | The template a tester fills in for a failed case: Title, Build / device, Steps to reproduce, Actual, Expected, Attachments |
| `## Not covered` | Ground neither the automation nor these cases reach, one line each with its reason, or `none` |
| `## Troubleshooting` | Symptom → cause → what to do, one row per symptom, for the ways a tester misses that are not product defects |
| `## Charter` | A timebox and what to look at: "10 minutes: change quantities in a long cart; a total that lags, a badge that disagrees, a row that jumps" |
| `## Code references` | A table headed `\| Case \| Code \|`, one row per case, `\| MC-<n> \| (file:line), … \|`, and one per scene from `P2` on, `\| P<n> \| (file:line), … \|` (`## Grounding`); the tester never reads it |

**`[COVERS]`, `[STYLE]`, `## Run record`, `## Scope`, `## Cases`, `## On failure` and `## Not covered` are always there, and so is `## Code references` whenever the file holds a case.** A file whose `## Cases` reads `none — <why>` has no references section. The others are conditional. `## Preparation` appears as soon as a step uses a product word or a shared scene, which is nearly always. `## Troubleshooting` appears when a case has a known way to go wrong that is not a product defect: the wrong account, a setting left changed, a cached build. `## Charter` appears when the change carries a gesture or a look the cases do not cover whole.

**`## Preparation`, in this order:**

1. `### Screen map` — a screen map for every screen the cases touch: an ASCII sketch in a fence, then a table headed `| Word in the cases | What it is on the screen |` with one row for every product word a step uses ("badge", "stepper", "total"). A word used in a step and missing from this table is a defect. Definitions live in this table, never inside a setup paragraph.
2. `### P0. Build` — how the build is made and installed. A developer does this, so it opens with `**dev-only:**`, and the tester never reads past that marker for it. Any other step that needs a code change, a configuration edit or a terminal is marked the same way.
3. `### P1. Device` — the device settings the cases rely on: interface language, permissions, account.
4. `### P2.` and on — each scene two or more cases start from, as a numbered table `| # | Action | Expected |`, ending with what to record as BLOCKED when the scene cannot be built.

A case names the scene it starts from in `**Preconditions:**`, and only what differs from it.

**A scene is a state.** It names the state a case starts from and the shortest way to reach it, and nothing else. That state is checked like any claim of a case (`## Grounding`). It is built without the behaviour the diff changes: when that state can be reached only through the changed behaviour, those actions are preparing steps of the case, so a broken change is the case's FAIL and never a scene that would not build. A scene that starts where another one ends says so, "P2, then…", and does not repeat it.

`## Not covered` is not a case list — nobody walks it. It exists so that later a missing case does not read as a passing one. Its reader is the file's reader, the one who walks the cases: each line says in the words of the screen what is left unchecked and, in one clause, why — "no safe way to make the disk fail". When automated tests hold it, "automated tests" is enough; how they hold it — the doubles, the temporary folders, the environments — goes to `Validation.md`.

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
- `**Test data:**` carries every concrete value the steps use: names, prices, quantities, addresses, and the table of conditions the steps are walked over.
- `**Steps:**` is the table above. `Expected` is what the screen shows right after that action; it is `—` only for a step that merely prepares the next one. `Actual` stays empty for the tester.
- `**Expected result:**` is the end state that passes the case, in one line.
- `**Failure looks like:**` is the cheapest field and the strongest. A failure is recognised faster than a success is verified, and this is what turns "it did not add up" into "here is what is broken".
- `**Cleanup:**` puts back what the case changed: an item left in the cart, a setting switched. `—` when there is nothing.
- The `(file:line)` references a case was grounded in are its row in `## Code references`, never a field of the case.
- `**Runner:**`, `**Device:**` and `**Order:**` are the three optional marks of `## Marks for a collective pass`; they follow `**What it checks:**` and are no part of the eleven.
- `**Status:**` and `**Notes / attachments:**` are the tester's: a mark, a reason for BLOCKED, a screenshot of what failed.

Write a blank line before every field, list and table. Markdown joins consecutive lines into one paragraph, and a table with no blank line above it renders as plain text. The lint checks structure, not rendering, so open the preview before handing the file over.

**Language.** The section headings, `[COVERS]`, the table's column names and the field labels above stay English: they are the file's structure. So do the sub-headings of `## Preparation`: `### Screen map` and the scene ids `P0`…`Pn` are written in Latin letters in every language, and only a scene's title after its id is prose. A case's title after `### MC-<n>.`, the text after each label, the table's cells, and the text of every section — `## Scope`, `## Preparation`, `## Troubleshooting`, `## Not covered`, `## Charter` — are prose in the project's `[LANG]` (`conventions/i18n.md` → Artifact authoring rule).

## What a case must prove

A case earns a tester's time only when its verdict says something about this change. Five rules decide that.

**It tells the build before the change from the build after.** On the build before the change the case fails; on the build after it passes. Checks that pass the same on both fold into one case, "nothing broke", whose `**What it checks:**` says it is not a check of the fix. When automated tests or the driver already cover that regression, there is no such case, and `## Scope` names the evidence.

**It checks what the diff touches.** An item of `OpsChecklist.md` becomes a case only when the diff touches that behaviour, as the `ops-checklist` skill defines touches. Otherwise the item is N/A, with its reason, by that skill. The one nothing-broke case is the only case not built on changed code. Its row in `## Code references` names the code of the behaviour it guards.

**It is settled by eye when the difference shows at normal speed.** That is so when the defect was found by eye, or when the check is tagged `visual judgment`. When the eye is unsure, the case says what to look for, and the eye decides. The person never reads frames, traces or logs. When no eye can see the difference at all, the check is no case of this file: `## No instrument in the file` says where it goes.

**It holds no line for a developer.** Outside `**dev-only:**` steps and `## Code references`, no line is for a developer. Measurements, internal terms and the history of edits go to `Validation.md` or `Walkthrough.md`. Code references go to `## Code references`.

**It is one check, one case.** The conditions a check is run under — language, theme, text size, device, orientation — are a table of conditions in **Test data:**, and the steps are walked once per row. A check that differs from another only in its conditions is a row of that case, never a second case. The status is one, and a condition that broke is named in its reason. A case about how a screen looks starts from a scene or its preconditions and does not re-run the covered flow to get there, and it does not walk again what ## Scope calls covered. A condition earns a step walked again only when that step's result depends on the condition: under another language the text is walked again, because it may not fit, but a button that closes a window closes it in any language. A case about a condition walks to the screen it judges and the steps whose result that condition can change, and stops there.

The first two rules hold for a task that changes product behaviour. On a task whose diff changes no product behaviour — a TEST task, a change to docs or tests only — the first rule does not apply, and the question of `## Does this check need a person?` reads as it says for such a task. There a case checks the behaviour the task targets that automation could not reach, which is what `[MANUAL_CHECKS]` `always` asks of such a run.

## Marks for a collective pass

The contract's `manual_checks_pass` says when the cases of a task are walked: `per-step`, the default, walks each step's file after that step, and `end` collects the cases of all steps into one collective pass at the end. Under `end` a case may carry three marks that tell the pass who walks it, on what, and when. They are written right after `**What it checks:**`, in `full` and in `brief`, and each is optional:

- `**Runner:** agent` marks a case the diff changes that this run did not walk only because the driver was off, was not found or did not reach the surface. The agent walks it in the pass; when it cannot, the case goes to a person with the reason. The value is always `agent`: a case a person walks has no `**Runner:**` line. A `**Runner:** agent` check stays a case of the step's `ManualChecks.md`, and it counts as a case when `[MANUAL_CHECKS]` = `auto` decides whether the file is written: a step whose only deferred checks are driver-only still writes its file.
- `**Device:** real` or `**Device:** <model>` marks a case that by its nature needs a real device, a named model: speed, a gesture with inertia, the camera, a sensor. A case that any device can show, a simulator included, has no such line.
- `**Order:** first — <why>` or `**Order:** last — <why>` marks a case that needs a state nothing has touched or that changes it for good: a case that needs access not yet granted is `first`, a case that unloads the app is `last`. The reason follows the dash, in one clause. A case that can run at any point has no such line.

No field means a person, any device and any order. A case that only a particular person can judge has no mark for it: `**What it checks:**` says so.

Under `per-step` none of the three is written, and a `**Runner:** agent` in a file of such a task is a finding at Review (`## Review`). The file does not know its own `manual_checks_pass`, so the lint checks only the shape of the marks (`## The lint`).

## Collective pass

Under `manual_checks_pass` = `end` the steps of an epic keep their own `ManualChecks.md` unwalked, and the epic's `Acceptance` stage writes one more at the epic's root, `<epic>/ManualChecks.md`: the collective pass, the one file a person walks at the end. The epic's `[validator]` writes it by this section and by the rest of the skill, in the epic's `manual_checks_style`. Before writing, read `examples/manual-checks.pass.en.md` or `examples/manual-checks.pass.ru.md`, and the English one for any other language.

**Where the cases come from.** `scripts/manual-checks-pass.sh collect <epic_dir>` lists the cases of every step that carry no mark yet, with their `**Runner:**`, `**Device:**` and `**Order:**`. A step id is the name of its `.step` folder up to the first `-` (`06-editor.step` is `06`); when two or more `.step` folders resolve to the same id (`address-form.step` and `address-list.step` are both `address`), each of them takes its full name without `.step` (`address-form`, `address-list`), and the other steps keep the short id. A case of the pass is `<step>/MC-<n>`. A step that sets `[MANUAL_CHECKS_PASS] = per-step` for itself in its own `Task.md`, such as a bug step created from a failed case, walks its own cases and is not collected.

**What the agent walks.** The agent walks through the driver every `**Runner:** agent` case and every other case the driver reaches whole, with no device action, visual judgment or external service. The agent part is not in the file: its verdicts are rows of the table `## Agent verdicts` in the epic's `Validation.md`, `| Case | Mark | Evidence |`, one row per case, the case keyed `<step>/MC-<n>`. A case the agent did not reach goes to a person with the reason in `## Scope`, and is written into the file like any other.

**The file.** After `[STYLE]` it carries the line `[PASS] = <step>, <step>, …`, the steps whose cases it holds; that line is what makes it a pass file to the lint.

- `## Scope` names the steps, the interface language, how many cases and how long, and then two things nobody else records: every difference between the scenes that were merged, and every case that went back from the agent, with its reason. There is one language per pass: the interface language is the same for every case, and a step that was written in another is rewritten in it.
- `## Preparation` holds the scenes the cases start from. Scenes of different steps that describe one state are merged into one scene, `### S1.` and on, built from the wording of the steps; where the steps disagree about that state (a different account, a different amount, a different order of taps), the scene takes one and `## Scope` names every difference. A scene no case of the pass starts from is not carried over.
- `## Cases` is split into sessions, `### Session <n>. <device>`, one per device: a case with `**Device:** real` or `**Device:** <model>` goes into the session of that device, and the cases with no `**Device:**` go into one session for any device, which a simulator may be. Each session carries a time estimate, in the heading or in the line under it. Inside a session the cases run in this order: those with `**Order:** first`, then the rest, then those with `**Order:** last`.
- Each case is copied whole from its step, with its marks, under the heading `#### <step>/MC-<n>. <behaviour>`, with its own token in `**Result:**`. Two cases are never merged into one, not even when they differ only in conditions or device: a case for another device goes into that device's session. A case is rewritten only to bring its scene or its language to the pass's, and a case's text is never shortened. A case `collect` lists that is neither in the pass file nor a row of `## Agent verdicts` is lost: `marks` reports it as unmarked and Done stops on it. A copied full case keeps its `**Status:**` line as it was; the mark of the pass is the one in `**Result:**`.
- `## Code references` carries the rows of the steps with the same ids, `| <step>/MC-<n> | (file:line) |`, and one row per scene of the pass, `| S<n> | (file:line) |` with no step prefix. A merged scene's row is grounded for the state the scene takes (`## Grounding`): a row copied from a step whose state the scene did not take points at the wrong code.
- The last line is `**Result:**`, one token per case: `<id> PASS`, `<id> FAIL (<why>)`, `<id> BLOCKED (<why>)`, `<id> DROPPED (<why>)` for a case the owner took off during the pass, and `<id> __` while there is none. The author writes every token as `<id> __`. A reason is written without an unbalanced parenthesis: the reader of the line cannot read past one, and every later token is lost.

A pass file is read by `## The lint` like any other: each case is an ordinary case of its style, named by its heading as written (`#### 01/MC-1.`), and `## Code references` and `**Result:**` are keyed by `<step>/MC-<n>`, the scene rows by `S<n>`. Then `## Check` reads it with a fresh reader, as it reads every `ManualChecks.md`. The stage ends with the list of cases for a person and waits for `/task-continue`.

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
| `field` | a mark of `## Marks for a collective pass` with a wrong value: `**Runner:**` that is not `agent`, `**Device:**` with no value, `**Order:**` that is not `first — <why>` or `last — <why>`; a missing mark is no finding, and a label in another letter case is no mark |
| `steps` | no steps table, a header other than the one in `## The case`, an empty `Action` or `Expected` (`—` is a value) |
| `compound` | two steps in one `Action`: "then", "and then", "afterwards", "repeat steps", a semicolon |
| `code` | code in `Action`, `Expected`, `**Preconditions:**` or `**What it checks:**`: a CamelCase word, a source file, a dotted name of three parts or more, a `(file:line)` |
| `codeslot` | a case with no row in `## Code references`, a row with no `file:line` in it, a row for a case not in `## Cases`; a scene with no row (`P2` and on in `full`, every `S<n>` in `brief` and in a pass file, none for a scene that is all `**dev-only:**`), a scene row with no `file:line`, a row for a scene not in `## Preparation` |
| `instrument` | an instrument in the file a person walks: an instrument field in a case, a section of instrument commands, a step or a field that asks the tester to record the screen (`## No instrument in the file`) |
| `chain` | "after case N", "the state right after", or an edit history kept in the file |
| `scriptable` | a case in which every step is a command — a backticked command, or "run the command…": nothing in it needs a person, so it is a script, not a case (`## Does this check need a person?`). The repair routes the case — `covered` in `## Scope`, or an automatable gap — and under `auto` the last one routed away takes the file with it; rewording the steps is not a repair |
| `file` | no `[COVERS]`, no `## Run record`, no `## On failure`, no `## Code references` in a file that holds a case |
| `pass` | in a file with a `[PASS] = <step>, …` line (`## Collective pass`): a case outside a session, a case id that is not `<step>/MC-<n>`, `**Order:** first` after a case without it and `**Order:** last` before a case without it (once per session), a case with no token in `**Result:**`, a file with no `**Result:**` line in `full` too; the case is named by its heading as written |

**No check counts lines.** The file has no line limit in either style, for a case, a section or the whole of it. Its length is held by the format of a case and by the fresh reader's `redundant` (`## Check`).

**In `brief`.** A file whose `[STYLE]` line reads `brief` is read by `## Brief`; a file with no such line is read as `full`, so a file written before the styles existed gains no finding. There `case` asks for `**What it checks:**`, `**Start:**` and `**Failure looks like:**` and names, once per case, a field of the full case; `steps` names a case with no numbered step whose expectation follows `→`; `file` asks for `[COVERS]` and the `**Result:**` line and names each section of the full file the brief one does not carry. `compound`, `code`, `codeslot`, `chain`, `instrument` and `scriptable` read the brief case as they read a full one, `**Start:**` in place of `**Preconditions:**`.

**Where the `code` check is wrong.** It reads a CamelCase product name (`YouTube`, `PayPal`) and a hostname or an address (`shop.example.com`) as code. There is no allow-list. Word around it: name the thing by what the screen shows ("the video service's red play logo", "the shop's address"), and put the literal name or address in the `Data` column or in `**Test data:**`, which the check does not read.

## Grounding

A case states what the code does, so it is written from the code, never from memory:

- Every claim about behaviour in `**Preconditions:**`, `Expected` and `**Failure looks like:**` — a direction, a limit, what a neighbouring element does — is checked against the code, and its reference goes into the case's row in `## Code references`, never into the step. Advice from `Review.md` enters a case only after that check.
- The starting state of every scene — what is on the screen, and which values — is checked against the code the same way, because the cases count from it: `P2` and on in `full`, `S1` and on in `brief` and in a pass file, each with its own row in `## Code references`, keyed `S<n>` or `P<n>`. `P0`, `P1` and a scene that is all `**dev-only:**` need none.
- A scene the driver opened in this run records what the screen showed, never what it was expected to show, and is checked against its row. A screen and a code that disagree are a finding in `Validation.md`, and the scene is written from neither.
- A value the run's data sets — what recognition found, a file's length, a system setting, the clock — is written relative to a landmark on the screen: "the cursor reads the start of the first line of the list", "a tenth past the start of the phrase". An absolute value is written only where the code fixes it, and that reference is in the row.
- A case about a resource or a style names, in its row of `## Code references`, the element that draws it and where it is used.
- A step uses only what exists in the build at `[COVERS]`; a check of what a later step of an epic adds is a `## Not covered` line with its reason.
- `scripts/lint-manual-checks.sh` names every case and every scene with no reference in `## Code references` and every place code leaked out of it; `## The lint` says how its findings are repaired.
- **The empty case.** `**Failure looks like:**` is what the code before the change would show from the same preconditions. When it matches `**Expected result:**`, the case checks nothing: delete it, and give `## Not covered` a line with the reason — or, when it guards a regression, make it part of the one nothing-broke case (`## What a case must prove`).

## Refreshing

A Validation that finds `ManualChecks.md` with a `[COVERS]` behind HEAD refreshes it rather than rewriting it:

1. `git diff --name-only <COVERS>..HEAD` names the changed files.
2. A case with a code reference into one of them is checked again, and so is a case with no code reference at all; the others are left alone. A scene is read the same way by its row, and a scene with no row gains one.
3. A new `## Manual acceptance` line goes through `## Does this check need a person?`; one that needs a person becomes a case with the next unused id; a case automation now covers moves to `## Scope` with a reference to that evidence, and its id is not reused.
4. A file with `**Code:**` inside its cases is the old format: move each into `## Code references` as that case's row. A file no Validation refreshes stays as it is.
5. The style: a file whose `[STYLE]` differs from this run's `manual_checks_style` is rewritten whole in the run's style, where a file with no `[STYLE]` line reads as `full`; its case ids are kept, and a removed id is not reused. When a file is rewritten whole — this way or by hand under newer rules — every factual claim of every scene and every case is checked again: a change of form is no exemption from `## Grounding`.
6. `[COVERS]` becomes HEAD.

## No instrument in the file

A tester's verdict is written in what a person can **see**, so the file a person walks holds no instrument: no instrument field in a case, no section of instrument commands, and no field, section or step of a case asks the person to record the screen, and no scene of `## Preparation` does either, because nobody reads a recording. A measurement the agent can make itself is made in the run and recorded in `Validation.md`. A measurement it cannot make is a line in `## Not covered`, with its reason, so that its absence does not read as a pass. Naming a trace, a log or a profiler in a case is a defect all the same: the tester cannot run it.

## The symbol rule

Neither `**Preconditions:**`, a cell of `**Steps:**`, nor `**Expected result:**` identifies a state by the name of a function, a file, or a variable. Nobody can reach *the quantity at the limit constant*; they can reach *ten Green tea in the cart*. A symbol belongs in `## Code references`, never in the instruction.

## Brief

`[STYLE] = brief` is the file for a tester who knows the app but not the task. Its screens, its buttons and how it behaves are theirs already. What they do not know is this task: which state to start from, which data to use, which conditions to walk, and what a failure looks like. The file gives them that and nothing else. Before writing, read `examples/manual-checks.brief.en.md` or `examples/manual-checks.brief.ru.md`, and the English one for any other language.

**The file**, in this order: the title, `[COVERS]`, `[STYLE] = brief`, then five sections and one closing line.

| Part | Content |
|---|---|
| `## Scope` | Two or three sentences: what the change does for the user, what automation covered, and how many cases there are |
| `## Preparation` | Only the scenes cases start from, `### S1. <title>` and on, each with one or two sentences that build it: a state, by `## Structure`, with no `→` and no condition for BLOCKED |
| `## Cases` | `### MC-<n>.`, one per check |
| `## Not covered` | As in `full` |
| `## Code references` | As in `full`, when the file holds a case, with a row `\| S<n> \| (file:line), … \|` for each scene; the tester never reads it |
| `**Result:**` | The last line of the file: `**Result:** MC-1 __ · MC-2 __ …` |

The `**Result:**` line carries one mark per case: PASS, FAIL or BLOCKED, with its reason after a FAIL or a BLOCKED. Under `[MANUAL_CHECKS]` = `always` with no case left, `## Cases` reads `none — <why>` and the `**Result:**` line reads `**Result:** none`. A brief case has no status field, so that mark is the one status of `## What a case must prove`, and a failing condition is named in that mark's reason.

**The case:**

```
### MC-1. <the observable behaviour>

**What it checks:** the intent, in one line

**Runner:** agent   <only under end>

**Device:** real   <only under end>

**Order:** first — <why>   <only under end>

**Start:** S1, and only what differs from it

**Test data:** the values the steps use, or the table of conditions they are walked over

1. one action, on a named object in a named place
   → what the screen shows now

**Failure looks like:** what is on the screen when it is broken
```

`**What it checks:**`, `**Start:**` and `**Failure looks like:**` are always there. `**Runner:**`, `**Device:**` and `**Order:**` are the optional marks of `## Marks for a collective pass`: the template shows where they stand, and a case keeps only the ones it needs, and only under `manual_checks_pass` = `end`; at `per-step` a case carries none. The `<only under end>` notes of the template are no part of a case. `**Test data:**` is there when a step uses a value or the case walks conditions. Each step is a numbered line with one action, and its expectation follows `→`, on the line under it or on the same line. A preparing step is a numbered step with no `→` line, allowed only when the next step's expectation covers it. A case starts from a scene and never from another case. It carries no other field than these and the marks: priority, traces, preconditions, an expected result, cleanup, status and notes belong to `full`.

**What holds from `full`.** **A scene is a state** of `## Structure`, `## Does this check need a person?`, `## What a case must prove`, `## Grounding`, the `## Code references` section, `## Refreshing`, `## No instrument in the file` and `## The symbol rule`. `## Step rules` hold too, except the steps table: one action per step, no "repeat steps", independent cases, every object named and located, a checkable expectation, the app's text copied verbatim. They read in brief terms: where a rule names `**Preconditions:**`, read `**Start:**`; where it names `**Expected result:**`, read the last step's expectation; the interface language is named in `## Scope` or in `S1`; and a step that needs a code change or a terminal goes in a scene marked `**dev-only:**`.

**What does not.** The screen map and its word table (`### Screen map`), `## Run record`, `## On failure`, `## Troubleshooting` and `## Charter`. The reader knows the app, so the file does not explain the product: it names only the task's scenes, data and conditions.

**Length.** There is no line limit, in `brief` or in `full`, for a case, a section or the file. Four fields and the steps hold a brief case short, and the fresh reader's `redundant` holds the rest.

**Language.** The labels, `[STYLE]` and the scene ids `S1`…`Sn` stay English and Latin in every language. A title after an id, the text after a label, a step, an expectation and every section's text are prose in the project's `[LANG]`.

## Check

`[MANUAL_CHECKS_CHECK]` decides whether the file is walked by someone who was not there before it is handed over; it reaches a run as the contract's `manual_checks_check`, `on` by default.

**When.** Validation returned `PASSED`, the file holds at least one case, and this Validation wrote or changed it — a case added, removed or rewritten; moving `[COVERS]` alone is no change. The author never checks its own file: the dispatcher does — the profile script under Method A, the workflow skill's main context under Method B.

**The reader** is a fresh dispatch of the validator's role, tuned `light`, and the style decides who it plays. In `full` it is a tester with no access to the code. In `brief` it is a tester who knows the app but not the task: the app's screens and buttons are theirs, the task's scenes, data and conditions are not. Of the task and the repository it reads `ManualChecks.md`, except its `## Code references`, and nothing else — no other file of the task, no source file, no git — and returns two lists:

- `walk` — one line per step of every case, as the action it would take: "I press X there, and expect Y";
- `smells` — every place it could not execute as written, each with the case, the step, a quote of at most one line and what is missing, of one kind: `ambiguous` — an intent, or a step with no object and place; `unverified` — an action with no expectation, other than a preparing step; `precondition` — preconditions that cannot be compared with the screen; `tacit` — a term, a screen or data with no route to it; `oracle` — an expectation that cannot be compared with the screen; `access` — a step that cannot be done without the code or a terminal and is not marked `**dev-only:**`; `twofold` — an expectation that can be counted as passed in two ways; `chained` — a case that cannot be run alone; `redundant` — a repeat, a case that repeats another under other conditions, a step walked again under a condition that cannot change its result, a scene that repeats another scene, a caveat said a second time, text not for this reader: a measurement, an internal term, an edit history. `**dev-only:**` steps and `## Code references` are for a developer by design, and neither is ever a `redundant` place. In `brief`, `tacit` is named only for the task's scenes, data and conditions, never for the name of a screen or a button of the app. `## Not covered` is read like every other section, and its words are held to the same reader.

**Revision.** An empty `smells` ends the check. Otherwise the author, with the code and the task, fixes in one pass every place named and every step `walk` retold wrongly, then runs the lint again. The revision deletes a `redundant` place, never rewrites it. A place where something is missing is closed by rewording first, and by adding text only when rewording cannot close it. In `brief` the revision adds no explanation of the product: its reader knows the app. What is left is not checked again. The run notes one line — `ManualChecks.md check: N place(s), revised, A → B lines.`, A and B being the file's lines before and after the revision, or `ManualChecks.md check: nothing unclear.` When B is above A, the line goes on: `The revision lengthened the file.` A failure of either dispatch is noted and stops nothing.

## Depth by task scale

The axis decides depth, not existence: whether this file appears at all is `manual_checks`. The value arrives in the contract as `manual_checks`; `conventions/task-settings.md` holds the chain it was resolved along. At either value of `scale` it is written when that switch says so — it is the only record of ground nothing verified, and `conventions/task-scale.md ## The floor` keeps what carries a guarantee.

`lite` drops `## Troubleshooting` and cuts no required field of a case: a case missing its `**Failure looks like:**` is not shorter, it is unusable. A `brief` file carries nothing `lite` would drop, so it is written the same at either value. `## Manual acceptance` at `lite` runs to about three lines, one when there is nothing to list — an expected size, not a ceiling: a task with five checks that need a person lists five.

## Review

This artifact is read at Review like any other the task produced. A case a tester cannot execute as written is an ordinary finding, judged by `## The case` and `## Grounding`, and in `brief` by `## Brief` in place of `## The case`; an empty case and a claim about behaviour with no reference in `## Code references` are findings too, and so are a scene with no row in `## Code references` and a scene whose starting state was not checked against the code; neither blocks. So are a case that needs no person by `## Does this check need a person?` and a `## Manual acceptance` line with no `needs:`; neither blocks. By `## What a case must prove`, three more findings block nothing either: a case that does not tell the build before the change from the build after, a case on behaviour the diff did not touch, and a step that has a person measure what the eye can see. A `**Runner:** agent` mark in a file of a task whose `manual_checks_pass` is `per-step` is a finding too: that mark is written only under `end`. Review and `## Check` are the only checks that run against a real task: a test can hold the spec, never the artifact made from it.
