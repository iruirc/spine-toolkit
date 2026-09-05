---
name: docs-route
description: "Use at Plan, at the end of every implementing phase, and at Done to decide whether a change altered what a declared documentation component asserts, and to record the answer in the task's `Docs.md`. Governed by `[DOCS]` in Task.md and `## Docs` in CLAUDE-spine-toolkit.md; the registry format is `conventions/docs-components.md`."
---

# Docs Route

`scripts/docs-route.sh` computes what a change set **may** have touched. This skill holds the
part computation cannot reach: whether it actually moved anything a component asserts, and what
to write when it did.

> **Related skills:**
> - `ops-checklist` — the same three-state vocabulary, at a different question
> - `task-walkthrough` — the per-task account that feeds a tracker
> - `manual-checks` — the other artifact whose shape a skill owns and a config block only levers

## The criterion

**Documentation is owed when the change altered what the component asserts** — an invariant, a
contract, a rule, a mapping. Not when the code changed.

Path overlap is a question, never an obligation. Fixing a typo under a component's `covers`
overlaps exactly as much as changing its resolution rule, and in the reference corpus 6.3% of
commits carry documentation at all: a mechanism deriving the obligation from the overlap would
be wrong by an order of magnitude and routed around within a week.

Neither does the task type decide it. Among commits carrying both code and documentation there,
fixes outnumber features five to one — a bug can deliberately weaken an invariant, and a feature
can add a screen without moving a single rule.

## The three answers

Fill the `Verdict` cell of every row `route` opened in `Docs.md`:

| Verdict | When | What else |
|---|---|---|
| **Applicable** | a rule moved; the record is part of this phase's result | write it into the component's `places`, in the same phase, and name the file in `Note` |
| **N/A** | nothing the component asserts was touched | a reason in `Note`, one line, required |
| **Pending** | not done yet | surfaces as a blocker at Review; on a `blocking` component the phase does not close |

Default to **Applicable** unless there is a concrete reason not to. The conservative bias is
deliberate and identical to `ops-checklist`'s: a false Applicable costs one line of reasoning, a
false N/A costs a rule nobody can find.

Reasons that are good `N/A`, from what the corpus actually contains:

- `behaviour unchanged` — a rename or a refactor under existing tests
- `invariant untouched` — a change inside an already-documented rule
- `nothing to describe` — flags, strings, tooling, build files
- `lives in <component>` — the statement belongs to another component, named

A reason that is not good: restating the diff. `N/A — changed the resolver` says nothing about
whether the resolver's contract moved.

## What to write

Only what a reader must not break: the invariant, the contract, the rule, the mapping, and the
one line of why it is that way. Rejected alternatives that must outlive the task get **one line
each, without their argument** — the argument stays in `Tasks/`. Never copy an investigation
artifact into a component; that produces a second home for a statement, which is the failure the
whole mechanism exists to prevent.

Write nothing before the rule exists in the code. A component file written ahead of the
behaviour is a forecast that reads as a fact and is wrong from its first day.

## Freshness header

When `## Docs` → `freshness` is `on`, every file of a `state` or `tracker` component opens with:

```
> **Status:** LIVE | SNAPSHOT | ARCHIVE
> **Synced:** YYYY-MM-DD
> **Owner:** <who keeps it current>
> **Source of truth:** <where to go for the truth>
```

`LIVE` — maintained, plan against it. `SNAPSHOT` — a photograph of its date, deliberately not
updated; not a defect but a declared shelf life. `ARCHIVE` — closed or not accepted, reference
only.

Each field carries what the others do not: a date without an owner does not say who is
responsible, a status without a date does not say when it went stale.

**`Synced` is a date, not a journal.** Replace the value; never append to it. Left to grow, this
field becomes a recursive chain of previous dates — which is history, and history has its own
home in the tracker.

## New components

A component the task creates is named in `Task.md` `[DOCS_NEW]`, and `route` opens its row even
though nothing covers it yet. **Declaring is not creating.** Add the record to `DocsMap.md` and
write the first file at the phase that first answers Applicable — that is, when the rule is
already in the code and under test.

The reverse signal comes from `docs-route.sh audit`: files created outside every `covers` are
what a subsystem being born looks like. Always advisory — coverage is knowingly partial, and
most of a mature tree is outside every component.

## The run

| Point | Command | What you do with it |
|---|---|---|
| Plan | `route … --phase <first>` with the paths the plan intends to touch | the affected components go into the phase rows of `Plan.md` |
| End of an implementing phase | `route … --phase <id>` with `git diff --name-status` for the phase | answer every row before the phase's commit |
| Before the commit | `check … --phase <id>` with the same change set | exit 1 means a blocking question is still open and the phase does not close; exit 2 means the registry or the table itself is malformed — fix that, it is not a question anyone can answer |
| Done | `audit …` with the task's change set | names the wrong homes and the uncovered new files; both advisory |
| Done | `tracker <project-root>` | regenerate every declared tracker's step table between its markers; a malformed marker pair is refused and left untouched, its name printed, while every other tracker still regenerates — exit 1 when at least one was refused |
| Review | `check …` with no `--phase` | name every row still open across all phases; report, do not enforce |

The core root is the directory holding `workflows/` (`conventions/agent-tooling.md` → Plugin
Roots And Templates).

A change set spanning more than one checkout is assembled before it is fed in: each checkout's
`git diff --name-status` goes through `reorigin <checkout>` so every path speaks the project
root's language, and the concatenation is what `route` and `check` read. A phase that changes
code in one repository and its documentation in another is the ordinary case, not the exception.

A `blocking` component whose `places` cannot be written from here — another repository, a
checkout that is not present — degrades to `advisory` and says so. Stopping the work on a
requirement that cannot be met where the work is happening is a trap, not discipline.

## On a redo

A phase that is redone must answer its questions again. `route` never reopens a row it already
wrote — it skips any phase-and-component pair already present, whatever the verdict — so delete
that phase's rows from `Docs.md` before routing the redo. An `Applicable` row would re-fail on its
own, being re-checked against the fresh change set; an `N/A` would not, and a reason that was true
of the first attempt is not evidence about the second.

## Not this skill's job

- Deciding the registry's content — that is the project's, in `DocsMap.md`.
- Moving a component that lives in the wrong repository — `audit` reports, nothing moves.
- Consolidating deltas into a single per-domain document — a layer above this one, not built.
- Writing the prose. The mechanism forces the record and names its home; what it says is the
  work of whoever knows what changed.
