---
name: task-walkthrough
description: "Use at the end of an implementing stage (Execute / Fix / Refactor / Write), and again at Done, to write or refresh `Walkthrough.md` — the human-facing account of what a task actually landed. It opens with what changed, before and after, then goes to the depth the axis resolves to: `deep`, a section per commit with the failure each one is written against; `brief`, a summary with a commit log; or `off`, not written at all. Governed by `[WALKTHROUGH]` and `[WALKTHROUGH_CHECK]` in Task.md and CLAUDE-spine-toolkit.md."
---

# Task Walkthrough

`Walkthrough.md` is what a person reads to learn what a task did. It is not the closing report — that is `Done.md`, which exists for the toolkit's own bookkeeping: the estimate retrospective that feeds calibration, the objections, the review loop's `## Awaiting changes` anchor. This artifact has a different reader and a longer life; it is what becomes a PR description, a changelog entry, or a handover to someone who was not there.

It is written at the **end of the implementing stage** — before anything has been validated or reviewed — because that is when "what did you build?" is actually asked. It also survives the bad path: a `FAILED` validation stops the run before `Done`, and then this file is the only account of the work that exists.

Commit messages do not make this artifact redundant. `conventions/commit-messages.md` deliberately strips them of exactly what a reader needs: the body carries WHY and not WHAT ("the diff shows WHAT"), and provenance — task, phase, ticket — is banned outright.

> **Related skills:**
> - `feature-landscape` — the design-time picture of the same feature; this is the after-the-fact one
> - `feature-estimation` — `Done.md ## Estimate retrospective` accounts for effort; this accounts for substance
> - `ops-checklist` — verification evidence with proof; this is narrative

## When to use

- End of the implementing stage: `Execute` (FEATURE), `Fix` (BUG), `Refactor` (REFACTOR), `Write` (TEST)
- Again at `Done`, but only when that stage did not run in the same invocation — a run that reached Done through a passing Validation and Review has added no commits since, one that entered at Review or Done has
- At `Done` only, for EPIC — see **EPIC**
- Not for RESEARCH or REVIEW — see **Not applicable**

## Reader

**An engineer who did not write this code and was not on this task.** Not a reviewer, who has the diff; not the author, who has the context. Someone who arrives months later with a question about this area and finds this file.

Every rule below is derived from that one sentence, and it settles the arguments the budgets cannot. A term this reader does not know gets defined. An alternative this reader would ask about gets named. A sentence this reader cannot parse without opening the repository gets a second, plainer sentence after it — at `deep`; see `## Style`. Writing for the author's own future self is the failure mode: it produces a file that is accurate, short, and useless to everyone else.

`brief` addresses the same reader with the area already known — the depth choice is an assumption about the reader's starting knowledge, not a second reader.

## The switch

`[WALKTHROUGH] = [brief|deep|off]` in `Task.md` → `off` when the run's `scale` is `lite` → `[WALKTHROUGH]` in `CLAUDE-spine-toolkit.md` → `deep`. First hit wins; a missing field is not an error, it is the default. The axis moves the default only, so an explicit `[WALKTHROUGH] = [deep]` writes this file on a `lite` run (`conventions/task-scale.md`).

| Value | Meaning |
|---|---|
| `deep` | What changed, item by item. Then a section per commit: what appeared, the failure it is written against, how that is closed, which alternative was rejected. Plus a glossary and a commit order. The default. |
| `brief` | What changed, one line per item; then a summary, divergences and a commit log of one bullet each. The account for that reader when the area is already familiar. |
| `off` | Not written. |

`on` is the pre-depth value and resolves to `deep` — it said *whether*, never *how deep*, and the depth this artifact needs to be worth reading is the deep one; a project that wanted the old shape says `brief`. The substitution is announced by the orchestrator, which is the only component that sees the raw value.

The value applies to the whole file. There is no per-section override: a document half-explained is worse than either consistent depth, because the reader cannot tell which half to trust.

Whether a reader with none of the writer's context reads the file back is a second switch, `[WALKTHROUGH_CHECK]` — see `## Check`.

## Inputs

- `Plan.md` — the intent: the phase table and the per-phase checkboxes
- The task's own git commits — the fact: `git log` for the range, and at `deep` a `git show --stat` **and** a read of the substantive hunks of every commit, because a section per commit cannot be written from subjects
- `Task.md` `## 2. [Description]` and `## 3. [Task]` — what was asked for
- The file's own previous content, when it already exists

## Coverage anchor

Second line of the file, byte-for-byte:

```
[COVERS] = <first-sha>..<last-sha>
```

Short shas of the task's own commits. This is what makes a refresh decidable without reading the whole file: the range already ends at the task's last commit → change nothing and say so; it is behind → refresh. The line is parsed by `scripts/docs-route.sh`, so its shape is fixed at both depths — a range spanning several repositories is described in the header's perimeter table, never by bending this line.

## Structure

The file opens with a header block rather than a title line, and the block holds four things and
nothing else:

1. the title, and the `[COVERS]` anchor as its second line;
2. one line `**Stage:** … · **Date:** … · **Branch:** …`;
3. the perimeter, one row per repository the task committed to:

   ```markdown
   | Repository | Range | Commits | ± lines |
   |---|---|---|---|
   | `app` | `a1b2c3d..f6e5d4c` | 9 | +2358/−72 |
   ```

4. one line naming where the statement and the verdicts live — `Task.md`, `Validation.md`,
   `Review.md`, `Done.md` — by name, never restated. The build verdict has one home and this is not
   it.

What the header never holds is the bookkeeping of the run: which finding a later commit closed,
which edit is not committed yet, why the file was refreshed. A finding closed by a commit is already
a row of `## Plan vs. outcome` with the trigger `Review`; the rest belongs to `Done.md`.

| Section | Content | `brief` | `deep` |
|---|---|---|---|
| header | The perimeter and where the verdicts live, as above | the four parts above | the four parts above |
| `## What changed` | Every observable change, before and after on one concrete case | 1 line per change | 1 item per change |
| `## Glossary` | Every domain term the document uses that the reader would not already know | absent | 1–4 lines per term |
| `## Summary` | Why the task existed, and the idea of the solution | ≤ 8 lines | no count: not a list of changes, not a retelling of commits |
| `## Commit order` | Why the commits are in this order and what depends on what | absent | prose + 1 diagram |
| `## Plan vs. outcome` | One row per divergence, with its trigger | 1 row per divergence | same |
| `## Commits` | The log | 1 bullet, 1–3 sentences each | 1 section each |
| `## How it works` | Diagrams, and only the prose that connects them | ≤ 2 diagrams | ≤ 2 diagrams |
| `## Out of scope` | What was deliberately left out, and where it went instead | absent | ≤ 5 bullets |
| `## Follow-ups` | Deferred work, each pointing at the task that carries it, or `none` | ≤ 5 bullets | ≤ 5 bullets |

The budgets bound **scope**, not comprehension. When a section is at its ceiling and one more claim still belongs in it, the three moves are ranked, and the order is what decides:

1. **Never compress.** Packing two or three claims into one sentence so they fit the count is the wrong move at either depth, always. It buys back a line and charges the reader a re-read for it.
2. **Go over rather than drop.** A line or two past the ceiling costs less than a claim the reader needed and did not get. The ceiling is what yields first.
3. **Consistently far over means the scope is wrong.** Not one line on one section — half again, section after section. Then the section is covering more than it should, and the fix is to drop claims until what remains fits, never to shrink the sentences that remain.

A `deep` section with no number in the table — `## Summary`, the prose of `## Commit order`, a
commit's sub-heading — is bounded by its scope alone. The first move holds there as everywhere. The
third is the only test left: a section that grows run after run covers more than its row says, and
the fix is fewer claims, never shorter sentences.

See `## Style`.

### `## What changed`

The first section after the header, at both depths. It answers "what did this task do" without the
reader opening anything below it. One numbered item per observable change:

```markdown
## What changed

1. **A promo code no longer discounts the delivery fee**
   - **Before:** a 10% code came off the whole total — an order of 1000 with a delivery fee of 300
     cost 1170.
   - **After:** the code comes off the goods alone — the same order costs 1200.
   - **Commits:** 3, 4.
```

- It is written in the words of the user or of the domain, with no identifier from the code. It
  stands before `## Glossary` because it has to be readable without it.
- `**Before:**` and `**After:**` describe one and the same concrete case — numbers, or the steps a
  user takes. The pair is the example; a change stated without one is a category, not a change.
- `**Commits:**` names the sections of `## Commits` that build the change.

What counts as a change depends on the profile:

| Profile | An item describes |
|---|---|
| FEATURE, BUG | observable behaviour |
| REFACTOR | structure, before and after, plus a `**Behaviour:** unchanged` line naming what proves it |
| TEST | a breakage that now fails a test where it used to pass unnoticed |
| EPIC | a change of the delivery as a whole, with `**Steps:**` in place of `**Commits:**` |

At `brief` every item keeps its before and after, on one line:
``1. A promo code no longer discounts the delivery fee: 1170 → 1200 on the same order (commits `a1b2c3d`, `e4f5a6b`).``

At `brief` the log is not numbered, so an item cites its commits by short sha.

### `## Glossary` (`deep`)

The single largest clarity win, and the one most often skipped. A term earns an entry when the reader would have to grep the repository to follow the next paragraph — a domain noun, a role in a relationship, a state that has a name in the code. A term earns nothing when it is general engineering vocabulary.

Per entry: what it is, and why it matters *here*. Ordinary-language name first, identifier second.

```markdown
**Reservation (`CartHold`)** — a claim on stock that a cart makes before payment. Not the order
line itself: it expires on its own after fifteen minutes, and an expired one leaves the cart intact
while the stock goes back. That expiry is where commit 3 gets its trouble.
```

The section is omitted entirely when the task introduces no such term. A glossary of words the document never uses is worse than none.

### `## Commit order` (`deep`)

Why this order and not another — dependency, not importance. One `graph TD` when the task has more than four commits, showing which commit each one needs; below that, prose alone. A sentence naming which node collects most of the edges, and why that is not a coincidence, is worth more than the diagram.

### `## Plan vs. outcome`

Each row names its **trigger**: `implementation` (reality differed once the code was open), `Validation` (a check forced the change), `Review` (a finding forced it). This is the section the artifact exists for — the plan is intent, the commits are fact, and nothing else in the task folder reconciles the two. Nothing diverged → the single line `Landed as planned.`

```markdown
| Planned | Landed | Why | Trigger |
|---|---|---|---|
| One `CartRepository` | Split into `CartReader` / `CartWriter` | The write path needed its own actor isolation | implementation |
| Optimistic delete | Delete waits for the server ack | Rollback raced the list diff | Review |
```

### `## Commits` — `brief`

Per commit: short sha, subject, then what it does, which files carry it, and what it unlocks for the next one. Not a re-reading of the diff — the reason the commit exists. The bullet ends on `**Changes:**`, the items of `## What changed` it serves. A bullet that serves none ends on `**Changes:** —` and says why the commit exists.

```markdown
- `a1b2c3d` `feat(domain): add CartReader` — introduces the read side as a protocol over the existing
  store, so the UI can move off `CartService` before the write side is touched. `Sources/Domain/Cart*`.
  **Changes:** 1.
```

### `## Commits` — `deep`

One `###` section per commit. Four parts are always present: the heading, which names what the commit did *in the reader's words* rather than repeating the subject; the subject itself on its own line; the files with their line counts; and `**Changes:**` — the items of `## What changed` the commit serves, or `—` when it serves none, and then its section says why it exists: preparation, a characterisation, a guard.

```markdown
### 3. `d770f52` — the one door untrusted data comes through

`feat(domain): sanitise untrusted cart payloads deterministically`

**Files:** `CartSanitizer` (+140), `CartStore` (+12), tests (+310).

**Changes:** 2.
```

Below that the sub-headings are a **menu, not a checklist**:

| Sub-heading | Earned when |
|---|---|
| `#### What appeared` | The commit introduces a type, a method or a field the reader has not met |
| `#### What failure this is written against` | The commit exists to prevent something — the usual case, and the most valuable section in the file |
| `#### How it is closed` | The mechanism is not obvious from the name |
| `#### Why <X> and not <Y>` | A reader would ask why the obvious alternative was rejected. One heading per alternative |
| `#### What is deliberately absent` | Something a reader would expect to be here is missing on purpose |

A commit that renames a symbol earns none of them and gets three sentences under the files line; a commit that introduces a subsystem earns all five. The depth of a section is a property of the commit, not of the document.

Two of these carry the weight, and both are usually missing when this artifact disappoints:

- **The failure** is written as a chain the reader can follow to its consequence, not as a category. `a malformed price in the stored cart → the user opens the cart → the process crashes`, and then the part that matters: it crashes *every time*, because the stored value does not go away, so that cart is unopenable forever. "Guards against invalid input" says none of that.
- **The rejected alternative** is what the reader actually came for. `Why the store is not the gate` beats any amount of description of the gate.

### Bookkeeping commits

A commit that carries no engineering decision gets no section and no bullet of its own: ticking the
plan, closing a phase in the task repository, a documentation commit that mirrors a code commit
already described. The test is whether the reader would ask "why" about it; if not, it is
bookkeeping. At both depths these close `## Commits`, one line per commit or per series:

```markdown
### Bookkeeping

- `1a2b3c4..9f8e7d6` — nine phase-closing commits in the task repository: plan checkboxes, `Docs.md` rows.
```

### `## How it works`

A diagram only where prose is genuinely worse than a picture. One file changed does not earn one.

| Shape | Diagram |
|---|---|
| Components / layers and their dependencies | `graph TD` |
| A flow crossing several objects | `sequenceDiagram` |
| A state machine, a lifecycle | `stateDiagram-v2` |
| Schema or migration shape | `erDiagram` |

### `## Out of scope` (`deep`)

What the task could plausibly have contained and deliberately did not, with where it went instead. Distinct from `## Follow-ups`, which is work this task created; this is work this task *declined*. A reader who cannot tell which of the two a missing piece falls into will open the wrong task to look for it.

## Style

The budgets say how much. This says how, and it is the half that decides whether the file gets read twice.

- **One claim per sentence.** Three facts stacked into one sentence with subordinate clauses fit the line count and cost the reader a re-read each. Prefer three sentences over the line you saved.
- **Define before use.** An identifier appearing for the first time in the middle of an explanation stops the reader dead. At `deep`, define it where it appears or link it to `## Glossary`; at `brief`, where that section is absent, name what the identifier is and move on.
- **An identifier is a reference, never the subject.** A test case, a review finding, a decision, a question, a phase or a neighbouring step is never what a sentence is about. Say the thing in words, then cite the identifier in parentheses: "a separate test proves the cart keeps its reservation through a second payment (`CH4`)", not "`CH4` proves the reservation is kept". A neighbouring step is named by what it did — "the delivery price formula (step `04`)". `## Glossary` gets no entry for an identifier: what needs defining is the thing it points at.
- **After any sentence that needs the repository open to parse, write a plainer one.** "Put simply: …". This is not padding; it is the difference between a document that transfers understanding and one that proves the author had it. At `brief` this one does not apply — a commit bullet of one to three sentences has no room for a second pass at the same sentence.
- **Name the alternative.** Every non-obvious decision is written as "X and not Y, because …". A decision presented without its rejected sibling reads as arbitrary, and gets undone by the next person.
- **A failure is a causal chain, then its consequence.** See `## Commits` — `deep`.
- **Code excerpts are allowed and are not diff-restating.** A signature, a doc comment, or the one line that carries the invariant — ≤ 12 lines, and only when the shape *is* the point. A hunk-by-hunk retelling is a different thing and is banned below.

## Feeding a progress component

A project may declare a `progress` component whose `fed_by` matches this task's folder
(`conventions/docs-components.md`). Then this file is one entry in a longer line of work, and
the progress component is regenerated at Done from every task folder that matched.

The split is fixed and worth stating, because getting it wrong is what makes a progress file rot:

- **Between `<!-- spine:steps:begin -->` and `<!-- spine:steps:end -->`** — generated: which
  steps exist, their status, when they opened, which commits they cover. Never hand-edited; the
  next regeneration overwrites it.
- **Everywhere else** — handwritten, and never touched by the toolkit: the intent, the limits,
  the lessons, the shapes that were tried and rejected, the cost of finishing. `## Plan vs.
  outcome` here is where the material for it comes from; a generator can produce neither.

Nothing in this skill changes because a progress component exists. Write the walkthrough the same way; the
aggregation reads it.

## Refreshing

The file is living, not append-once. On a stage that runs it when the file already exists:

1. Read `[COVERS]`. Its end already at the task's last commit → change nothing, report that.
2. Otherwise refresh, and treat the sections differently:
   - `## Commits` — **append only**, at both depths, except when the resolved depth changed — see below. It is a log; a rework commit arrives with its own reason (`addresses Review finding 2`) and does not overwrite its predecessors. New bookkeeping commits join `### Bookkeeping`.
   - `## Plan vs. outcome` — **accumulates**, each new row carrying its trigger. A round of fixes after Review is precisely the divergence worth keeping.
   - `## What changed`, `## Glossary`, `## Summary`, `## Commit order`, `## How it works`, `## Out of scope`, `## Follow-ups` — **rewritten** to the current state. The reader needs what is true now, not archaeology.
3. Update `[COVERS]`.

A refresh that finds the file at the other depth rewrites it to the resolved one rather than mixing the two. Raising `brief` to `deep` means going back to `git show` for the commits already logged — the existing bullets are not enough to expand from, and expanding them from memory invents content.

## Check

`[WALKTHROUGH_CHECK]` decides whether the file is read back by someone who was not there; it reaches
a run as the contract's `walkthrough_check`, `on` or `off`. `auto`, its default, is `on` at `deep`
and `off` at `brief`, and nothing is checked where `[WALKTHROUGH]` wrote nothing.

When it is `on`, every write that changed the file is followed by one read. A refresh that changed
nothing is not checked. The writer never checks its own file: the dispatcher does — the profile
script under Method A, the workflow skill's main context under Method B.

**The reader** is a fresh dispatch of the writer's own role; the fresh dispatch is where its lack of
context comes from. Of the task and the repository it reads `Walkthrough.md` and nothing else — no
other file of the task, no source file, no git — and returns two lists:

- `retelling` — one sentence in its own words for each item of `## What changed`;
- `unclear` — every place it had to guess, each as a quote of at most one line and what was
  missing: a term or an identifier nobody explained; a sentence it had to read twice; a
  `## What changed` item no commit builds; a commit whose section does not say which item it serves,
  or, at `**Changes:** —`, why it exists.

The role is the writer's because the reader this file is for is an engineer of the same stack who
was not on the task. The `reviewer` is not the reader: its job is the diff, and the author's story is
kept away from it (see **Feeding it to the Review stage** below).

**Revision.** An empty `unclear` ends the check. Otherwise the writer gets both lists and fixes every
place named; where the retelling misreads a change, the text that led it there is fixed as well.
`[COVERS]` stays. `## Commits` is edited in place — this is the same version of the file, not a
refresh, so the append-only rule does not apply.

**One round.** What is left after the revision is not checked again. The run notes one line: how
many places were named and whether the file was revised. A failure of either dispatch is noted and
stops nothing, as a failure of the write does.

## Not applicable

- **REVIEW** — the profile is `['Review']`; there is no implementing stage and no Done stage to write from, and the task produces no commits of its own.
- **RESEARCH** — its commits are commits of its own artifacts, and the account of what was done is `Research.md` itself. A walkthrough would be a copy.
- **EPIC on the `pure_research` branch** — same reason: no steps ran, no implementation followed.

In these three, `[WALKTHROUGH]` set by hand is reported once and not executed, never silently dropped.

## EPIC

An epic makes no commits of its own; its steps do, each writing its own `Walkthrough.md`. It is written at `Done` rather than at the end of Execute: the epic has no Validation or Review to precede, and a walk that stopped on a failed, cancelled or pending step has no delivery to describe yet. The epic-level file sits a layer above: how the steps compose into one delivery, in what order and why, what changed in the intent along the way — linking to the steps' walkthroughs rather than restating them.

The depth switch reads the same, with the step standing in for the commit: at `deep`, `## Commit order` becomes the order of the steps and their dependencies, and `## Commits` becomes a section per step — what that step made possible for the next one, and which of the epic's intentions moved while it ran. Both headings keep their names: what the section holds changes, not what it is called. The glossary belongs here more than anywhere: an epic is where a reader meets the domain vocabulary first. `## What changed` lists the changes of the delivery as a whole, each naming the steps that built it under `**Steps:**`.

## Localization

Prose in the project's language, structure in English — headings, the `[COVERS]` anchor, the trigger values. The English half covers `## What changed`, `## Glossary`, `## Commit order`, `## Out of scope`, `### Bookkeeping`, the five `####` sub-headings of a `deep` commit section, and the labels `**Before:**`, `**After:**`, `**Behaviour:**`, `**Commits:**`, `**Steps:**`, `**Changes:**` and `**Files:**`: later tasks cite them by their exact spelling, and a translated heading breaks that citation.
`conventions/i18n.md`, Artifact authoring rule.

## Anti-patterns to avoid

- **Telegraphic compression.** Packing three claims into one sentence to stay inside a budget. The budget bounds how much this section may cover, never how hard it may be to read; go a line over rather than a comprehension short, and when a section runs far over line after line, follow the ranked rule under the `## Structure` table — the answer there is fewer claims, never shorter sentences. This is the failure that makes an accurate file useless.
- **Restating the diff.** A hunk-by-hunk retelling. The diff is readable and does not rot; prose about it does. Quoting a signature or a doc comment is not this — see `## Style`. The test: does the excerpt carry the *why*, or is it there because it was in the change?
- **Deep by reflex.** A five-part section for a commit that renamed a constant. The sub-headings are a menu; an empty one filled to look complete is noise the reader has to wade through.
- **A glossary of unused terms.** Entries earn their place by appearing later in the document.
- **Feeding it to the Review stage.** The `reviewer` agent exists to read the diff independently; the author's narrative anchors it. `OpsChecklist.md` is fine as its input — that is evidence, not story. The reader of this file is a person.
- **Copying the validation verdict in.** It lives in `Validation.md` and `Done.md`. Link, do not duplicate.
- **A diagram per commit.** Two diagrams is the ceiling in `## How it works`, plus the one in `## Commit order`, and most tasks want fewer.
- **Rewriting `## Commits` on refresh.** That erases the rework, which is the part worth having. The one exception is a refresh at a depth the file was not written at — see `## Refreshing`.
- **Bookkeeping in the header.** Which finding which commit closed, what is not committed yet, why the file was refreshed. The header is the perimeter; the run's history belongs to `Done.md`, and a finding a commit closed is already a row of `## Plan vs. outcome`.
- **An identifier as the subject.** "`CH4` proves …", "closes Minor 3". The reader was not there when the label was handed out. Say what it is, then cite it.
- **A change list that is a commit list.** A `## What changed` in commit order, or one restating the subjects, answers "what was committed" — the question the log below it already answers.

## What this skill does NOT do

- Does NOT judge the work — that is the `reviewer` agent, and the verdict is `Review.md`.
- Does NOT account for effort — that is `Done.md ## Estimate retrospective` via `feature-estimation`.
- Does NOT replace `Done.md`. The two are written by the same agent at Done and answer different questions.
- Does NOT participate in State Detection. Its presence or absence never moves a `start_stage`.
- Does NOT read itself back. `## Check` is another dispatch's work, never the writer's.
