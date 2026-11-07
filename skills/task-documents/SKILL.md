---
name: task-documents
description: "Use when writing or rewriting the documents a task leaves — Task.md, Research.md, Plan.md, Done.md, Review.md, Questions.md, Validation.md: which document answers what, the rules every one follows, and the template each carries. The reader never saw the research — an agent starting in a clean context is in the same position as a person opening the task a month later. Applied by task-new, by every investigating stage, by every Plan stage, and by the stages that write the report, the review, the decision log and the validation record."
---

# Task Documents

The documents a task leaves are written by one agent and read by another. The reader never saw the investigation: an executor starts in a clean context, a person opens the task a month later. Density that saves the writer a sentence costs every reader a search, and a rule written as a formula gets implemented literally, contradiction included. **Write for the reader who was not there.**

The reader and the style rules every task artifact follows are in the `artifact-reader` skill, and every document below follows them; this skill does not repeat them. What this skill adds is what each document answers and the template it carries.

## Layers

Three of the documents plan the work, and each answers its own question:

| Document | Answers | Carries | Never carries |
|---|---|---|---|
| `Task.md` | what and why | the problem on an example; decisions not reopened, one line each; expected behaviour; open questions; questions for Research; acceptance | code mechanics, the algorithm, test lists, per-work-item done criteria |
| `Research.md` | how it works today and which outcomes exist | the mechanics; every outcome, a corrupted state included; answers to the task's questions for Research | a decision the task already made, re-decided |
| `Plan.md` | how to do it | the order and why; each step or phase with what it waits for and what is true after it; risks | a retelling of the research; the history of superseded revisions |

A layer is a boundary of responsibility, not a style. Without it a document grows with every reading: the reader asks what the next document answers, and the writer answers it here.

The others record what happened: `Done.md` reports the task, `Review.md` judges it, `Questions.md` keeps the decisions taken on the way, and `Validation.md` says how it was checked. Each has its section below.

## Rules for every document

1. **Meaning first, the code in brackets.** "The client never limits the host (`P12`)" — never `P12` alone (`artifact-reader` → Style, rules 2 and 3).
2. **A rule with branches is a table of cases with the expected result**, on numbers or commands. A formula alone hides the case it does not cover.
3. **Terms come from the project's glossary**; a code identifier's meaning is given once.
4. **A correction goes into the item it corrects**, never appended as a notice. When it concerns another document it goes there; the trace of the decision goes to `Questions.md`.
5. **An open question is written as one:** the options, a recommendation, who decides and by which stage. "Decided at this step" with no options is a defect — it reads as a decision and holds none. Each option is a sub-item of the question, and the recommended one carries `(recommended)` — literally, at any `[LANG]`: the open-questions gate offers that sub-item as a one-click answer.
6. **A document decides nothing its source did not.** A decision the writer reaches while writing becomes an open question, never a sentence stated as settled.
7. **Every count agrees with every other place that states it.** State a number once and refer to it rather than restating it.

## Task.md of a root task

Written from the owner's words, before any investigation. Keep the layer: what is wrong, why it matters, what done looks like. Give an example only when the owner gave one — never invent numbers. No requirement codes, no mechanics. What the owner left open is written as an open question.

## Task.md of a step

Written by the epic's planner from the epic's `Task.md`, `Research.md` and `Questions.md`.

- `## 2. [Description]` — the problem on one example, with numbers where the source gives them. Then the epic's decisions this step does not reopen, one line each, and the step's open questions, written as rule 5 says. An epic decision that carries a label is written as the sentence first, the label in brackets. For example "the discount never exceeds the campaign cap (`u3`)", never "as decided in `u3`".
- `## 3. [Task]` — what the step delivers, in plain words, then three anchors. The headings stay English; the text follows the project language.
  - `### Expected behaviour` — a table of cases, situation → result. A command and its outcome is a case.
  - `### Questions for Research` — what the step's own investigation must find out: mechanics, rare outcomes, where things live. Questions, not answers.
  - `### Acceptance` — what must be true when the step closes.
- An anchor that does not apply carries `— <reason>`, never a bare dash.
- `## 1. [Files]` names where the work starts, by symbol, not by line number: a line number drifts between writing the step and running it. How the code works there is a question for Research.
- Every requirement and constraint of the epic that lands on this step appears in it. Shorter is not better when it drops one.
- `scripts/lint-artifact-budget.sh --task-docs` measures the file against its line ceiling. A step over it moves mechanics into `### Questions for Research`; it never drops a requirement.

## Research.md

`Research.md` opens with `## Short answer`: one or two sentences per question of `### Questions for Research`, in words, each naming the question it answers. A root task has no anchors; there the short answer takes the questions its `Task.md` asks. The sections below the short answer hold the evidence for it. Folded into another document at `lite`, the research section opens with the same answers.

- Answer every question under the task's `### Questions for Research`, by name.
- For a function or an operation, list every outcome — not found, over a limit, an invalid or corrupted input — not only the normal ones.
- For every quantity a rule uses, say where it comes from: a stored field, or the result of another rule.
- In a table of properties or risks, the "how it is ensured" cell is words, the identifier in brackets: "the total is computed in one place (`CartTotals`)", never `CartTotals` alone.
- Do not re-decide what the task already decided. A finding that contradicts a decision is an open question for the owner.

## Plan.md

`Plan.md` is two parts, in this order: what the owner needs to approve the plan, then what the implementer needs to carry it out.

`## For the owner` carries:

- the goal, in two sentences;
- the progress table, one line per phase (per step, in an epic), each described in plain words, because the table is read by people skimming status;
- the risks, each written as what a user would see, next to the phase that removes it;
- the decisions the owner must take, each an open question with its options and a recommendation, as rule 5 says.

`## For the implementer` is everything below its heading: the detail section of each phase with its checkboxes and its `**Verification:**` line, the files, the commands, `## Estimation` and `## Manual acceptance`.

- For each phase: what it waits for, what is true after it, and what happens when it fails.
- Say why the order is what it is.
- A decision is stated in words, its label in brackets: "the cart keeps its items after sign-out (`u3`)", never "per `u3`".
- Carry no history of superseded revisions: the decision goes to `Questions.md`, the plan states the current one.

Phases added later keep this shape: the progress table stays a top-level table in the first part. A review-fix round (`Review fixes <n>`) or a catch-up (`Catch-up: commits after Done`) adds its row there, and its detail section under `## For the implementer`. A `full` plan has no line ceiling. At `lite` the ceiling that `scripts/lint-artifact-budget.sh` measures still holds, and the folded research section is the first section under `## For the implementer`.

## Done.md

`Done.md` is the report a reader opens instead of the task. Its sections, in this order:

1. `## Summary` — two to four sentences with no identifiers: what changed and for whom; then one sentence on whether the user sees anything new.
2. `## Why` — the problem the task solved, as a chain whose last step is what the user saw.
3. `## What is left and risks` — what the task did not do and what could still go wrong, written as what a user would see; when nothing is left, one sentence says so.
4. `## Objections` — a contested decision the owner insisted on, with the alternative the agents proposed; only when there is one.
5. `## Estimate retrospective` — when `Plan.md` carries an estimation section, by the `feature-estimation` skill.
6. The service sections. First the phase table, whose `What` column is words with the identifier in brackets. Then what the profile's Done stage adds, such as the regression test or the coverage reached. Last the artifacts the task produced, the validation status and `## Review findings closed`.
7. The closing block: the `[DONE_COMMIT]` and `[REVIEW_FIXES]` lines, `**Run:**`, `**Device:**` (`conventions/stage-dispatch.md` → Closing block).

At `lite` the sections stay in the same order, inside the line ceiling that `scripts/lint-artifact-budget.sh` measures. `## Objections` and `## Estimate retrospective` are left out when they would be empty. The phase table keeps one line per phase, and each section is a few sentences, never a list of commits.

When `Done.md` already exists, every claim in it is checked against the current artifacts and the git log before it is kept, as the workflow skill's Done stage says. This template does not change that reconciliation.

## Review.md

The status line `[REVIEW_STATUS] = …` stays line 1, and the verdict is unchanged. The sections are the reviewer's own; three rules hold in them:

- Every finding carries `**Impact:**`: one sentence, what breaks and for whom, with no code. "**Impact:** a shopper who removes the last item still pays for it at checkout."
- The Summary and Previous findings name a finding in words, its ID in brackets: "the total no longer goes below zero (`M1`)", never "`M1` fixed".
- The `[REVIEWED_COMMIT]` lines go in the closing block.

## Questions.md

`Questions.md` keeps the decisions taken on the way. An entry of its log (`## Open Questions Log`) holds the question itself, not only its ID: the question, then the option chosen, then the rejected ones, then who decided and when.

```markdown
- [<stage>] <id> — **Question:** <text>
  **Decision:** <the option chosen, in words>
  **Rejected:** <the other options, each with why>
  **Decided by:** <who>, <ISO date>
```

For example:

```markdown
- [Plan] q2 — **Question:** does a promo code apply to items that are already discounted?
  **Decision:** no, the code applies to full-price items only.
  **Rejected:** applying it to every item, because two discounts on one item can break the campaign cap.
  **Decided by:** owner, 2026-11-07
```

The old form, an ID followed by `— RESOLVED: …` with no question, is not valid for a new entry; entries already written stay as they are. `scripts/lint-artifact-readability.sh` reports a log entry without its question.

## Validation.md

`Validation.md` is written by the platform's validator, and its structure is the validator's. The status line `[VALIDATION_STATUS] = …` stays line 1. Two rules hold below it:

- The Summary is plain language: what was built and run, what passed, what failed, and what that means for the user. It names no contract field — not `validation_status`, `VALIDATION_STATUS` or `manual_checks_changed`: those travel in the validator's return, not in the prose.
- A log is cited by its copy in the task folder, `validation-evidence/<timestamp>/<name>.log`, never by a temporary path that does not outlive the session. The platform validators already copy the logs there.

## Worked example

One step, a promo code.

Before — the language of the research:

> **WI-7 — applying a promo code (R3, S4).** Rule: `total = cart ∩ conditions ∩ campaign window`. The discount is capped (P9). An empty intersection is an explicit state. The decision on a negative total is taken here.

After — the what-and-why layer:

> **A promo code lowers the order total, never below zero and never by more than the campaign cap.** Today a code worth 500 on an order of 300 gives −200, and the payment fails.
>
> Epic decisions: the discount never exceeds the campaign cap; a code outside the campaign dates does not apply.
>
> ### Expected behaviour
>
> | Order | Code | Campaign cap | Total |
> |---|---|---|---|
> | 1000 | 200 | 300 | 800 |
> | 1000 | 500 | 300 | 700 |
> | 300 | 500 | 1000 | 0 |
> | 1000 | 200, campaign over | 300 | 1000 |
>
> ### Questions for Research
>
> Where the total is computed today — once, or in every place that shows it.
>
> ### Acceptance
>
> Every row of the table is covered by a test; the total is never negative.

"The decision on a negative total is taken here" became a row of the table: the question it pretended to settle now has an answer a reader can check.
