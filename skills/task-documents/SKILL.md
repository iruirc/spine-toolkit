---
name: task-documents
description: "Use when writing or rewriting a task's Task.md, Research.md or Plan.md: which of the three documents answers what, the rules every one follows, and what each carries. The reader never saw the research — an agent starting in a clean context is in the same position as a person opening the task a month later. Applied by task-new, by every investigating stage, and by every Plan stage."
---

# Task Documents

A task's documents are written by one agent and read by another. The reader never saw the investigation: an executor starts in a clean context, a person opens the task a month later. Density that saves the writer a sentence costs every reader a search, and a rule written as a formula gets implemented literally, contradiction included. **Write for the reader who was not there.**

## Layers

| Document | Answers | Carries | Never carries |
|---|---|---|---|
| `Task.md` | what and why | the problem on an example; decisions not reopened, one line each; expected behaviour; open questions; questions for Research; acceptance | code mechanics, the algorithm, where in the code, test lists, per-work-item done criteria |
| `Research.md` | how it works today and which outcomes exist | the mechanics; every outcome, a corrupted state included; answers to the task's questions for Research | a decision the task already made, re-decided |
| `Plan.md` | how to do it | the order and why; each step or phase with what it waits for and what is true after it; risks | a retelling of the research; the history of superseded revisions |

A layer is a boundary of responsibility, not a style. Without it a document grows with every reading: the reader asks what the next document answers, and the writer answers it here.

## Rules for every document

1. **Meaning first, the code in brackets.** "The client never limits the host (`P12`)" — never `P12` alone.
2. **A rule with branches is a table of cases with the expected result**, on numbers or commands. A formula alone hides the case it does not cover.
3. **Terms come from the project's glossary**; a code identifier's meaning is given once.
4. **A correction goes into the item it corrects**, never appended as a notice. When it concerns another document it goes there; the trace of the decision goes to `Questions.md`.
5. **An open question is written as one:** the options, a recommendation, who decides and by which stage. "Decided at this step" with no options is a defect — it reads as a decision and holds none.
6. **A document decides nothing its source did not.** A decision the writer reaches while writing becomes an open question, never a sentence stated as settled.
7. **Every count agrees with every other place that states it.** State a number once and refer to it rather than restating it.

## Task.md of a root task

Written from the owner's words, before any investigation. Keep the layer: what is wrong, why it matters, what done looks like. Give an example only when the owner gave one — never invent numbers. No requirement codes, no mechanics. What the owner left open is written as an open question.

## Task.md of a step

Written by the epic's planner from the epic's `Task.md`, `Research.md` and `Questions.md`.

- `## 2. [Description]` — the problem on one example with numbers, then the epic's decisions this step does not reopen, one line each.
- `## 3. [Task]` — what the step delivers, in plain words, then three anchors. The headings stay English; the text follows the project language.
  - `### Expected behaviour` — a table of cases, situation → result. A command and its outcome is a case.
  - `### Questions for Research` — what the step's own investigation must find out: mechanics, rare outcomes, where things live. Questions, not answers.
  - `### Acceptance` — what must be true when the step closes.
- An anchor that does not apply carries `— <reason>`, never a bare dash.
- `## 1. [Files]` names symbols, not line numbers: a line number drifts between writing the step and running it.
- Every requirement and constraint of the epic that lands on this step appears in it. Shorter is not better when it drops one.
- `scripts/lint-artifact-budget.sh --task-docs` measures the file against its line ceiling. A step over it moves mechanics into `### Questions for Research`; it never drops a requirement.

## Research.md

- Answer every question under the task's `### Questions for Research`, by name.
- For a function or an operation, list every outcome — not found, over a limit, an invalid or corrupted input — not only the normal ones.
- For every quantity a rule uses, say where it comes from: a stored field, or the result of another rule.
- Do not re-decide what the task already decided. A finding that contradicts a decision is an open question for the owner.

## Plan.md

- Describe each step or phase in plain words: the progress table is read by people skimming status.
- For each step or phase: what it waits for, and what is true after it.
- Say why the order is what it is.
- Write a risk as what a user would see, next to the step or phase that removes it.
- Say what happens when a step or phase fails.
- Carry no history of superseded revisions: the decision goes to `Questions.md`, the plan states the current one.

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
