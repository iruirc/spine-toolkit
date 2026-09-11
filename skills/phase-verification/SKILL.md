---
name: phase-verification
description: "Use at Plan to decide how much each phase checks before it commits, at the implementing stage to run exactly that, and at Review to judge the choice. The rung follows from what a phase changes for the modules that depend on it, never from how risky the edit feels, and the full regression belongs to Validation. Governed by `[PHASE_VERIFICATION]` in Task.md and `## Validation` in CLAUDE-spine-toolkit.md."
---

# Phase Verification

Every phase ends buildable, green and committed, so it can be reverted or bisected on its own. This skill decides how much "green" means. Too little, and a break surfaces at Validation across a dozen commits; too much, and every phase re-runs what Validation is about to run anyway. **The full regression belongs to Validation. A phase checks what it can break.**

## Terms

- **Perimeter** — the modules a phase edits.
- **Dependent** — a module the phase does not edit that builds from the perimeter's source in this task's checkouts. A consumer pinned to a published version cannot see the change and is not a dependent here.

## The rungs

Each rung includes the one above it.

| Rung | When | What runs |
|---|---|---|
| `internal` | nothing outside the perimeter can see the change | build and tests of the perimeter |
| `surface` | what dependents build against changes, but not what they observe: new API nobody calls yet, removal of something nobody calls any more, build configuration | + a build of every dependent — the narrowest build that covers them all |
| `behaviour` | what dependents observe changes: the semantics of an existing call, a default value, a shared test fixture | + the tests of the dependents that observe it, by name — not all dependents |

## Choosing the rung

Ask in this order and stop at the first yes:

1. Does any call from outside the perimeter get a different result, a different error or a different state? → `behaviour`
2. Does anything visible outside the perimeter appear, disappear or change its signature? → `surface`
3. Otherwise → `internal`

Answer from a **usage search** of what the phase changes, not from memory: a `behaviour` line names the dependents the search found, a `surface` line states that nothing outside calls what changed. How to search is the platform agent's business.

**Doubt raises one rung, never to `full`,** and the line says what the doubt is — a changed value written into a serialized format no code search reaches, say. Over-claiming costs a few dependents' tests; under-claiming costs a bisect.

| Phase | Rung |
|---|---|
| adds `Money.round`, nothing outside calls it yet | `surface` |
| changes the rounding mode inside `Money.add`, which Checkout and Cart call | `behaviour` — Checkout, Cart |
| renames a private helper | `internal` |

## The line

The first line of every phase's detail section in `Plan.md`:

```
**Verification:** <internal|surface|behaviour|full> — <what this phase changes for its dependents, one clause>
```

Under it, one checkbox per check the line names; the platform agent writes the commands. The line is *what*, the checkbox is *how*. The line is written at `full` too, so a phase without one means the plan predates this rule or was written outside the pipeline — never a project's choice.

## Who does what

- **Plan** chooses the rung and writes the line and its checkboxes.
- **The implementing stage** runs what the line names. A phase with no line resolves the switch below, derives its rung from its own diff by the questions above — or writes `full` — and adds the line before any check runs. A diff that reaches further than its line raises the line in the same phase commit and runs the higher check. Raising stays within `internal` → `surface` → `behaviour`; nobody lowers a rung.
- **Validation** is unchanged: it runs the full regression.

## Dependents with no aggregate build

Where no single build covers every dependent, build them one by one; there is no skipping. The saving comes from the `internal` phases, and `surface` is a build without tests. Never merge consecutive `surface` phases into one build at the last of them: adding a requirement to an interface breaks every implementer, the intermediate commit stops building, and bisect stops with it.

## The switch

```
Task.md [PHASE_VERIFICATION]  →  CLAUDE-spine-toolkit.md ## Validation → phase_verification  →  proportional
```

First hit wins; a missing key is the default, not an error. `proportional` is the rungs above. `full` runs the full regression in every phase — right where the whole suite takes a minute, or on a task whose author buys insurance against a wrong rung. `full` in a line is legal only when the switch resolves to `full`. There is no `off`: a planner choosing freely is the defect this skill exists for. `scale` does not move the switch.

## By profile

| Profile | Typical phases |
|---|---|
| FEATURE | new code nobody calls yet — `internal` or `surface`; wiring it into an existing flow — `behaviour` |
| BUG | the fix — `behaviour` when dependents see the repaired call, else `internal`; the regression test — `internal` |
| REFACTOR | a new primitive beside the old — `surface`; moving dependents onto it edits them, so their tests run as `internal`; the phase after which dependents it did not edit can see the change — `behaviour`; removing the old one — `surface` |
| TEST | a phase adding tests — `internal`; a change to a shared fixture or helper — `behaviour` |

## Review

Three findings, read against `Plan.md` and the diff:

1. a phase with no `**Verification:**` line;
2. an under-claimed rung — the questions above, asked of the phase's diff, give a higher rung than its line;
3. at `proportional`, a phase that repeats the full regression — a `full` line, or checkboxes that run the whole suite.

None of them blocks, and none goes into `blocking_findings`. Review runs after Validation has passed, so the code is already proven; these say the plan chose badly, and they exist so the next plan and the measurement can see it.
