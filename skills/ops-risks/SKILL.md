---
name: ops-risks
description: "Use at Plan, to lay the proof of each operational risk into the phase that gives it, and at Review, to check that proof against the diff. Seven operational risks a diff can show: startup work, lifecycle reactions, stored data, a changed contract, a rollout flag, a hot path, release settings. Whether a risk applies follows from what the diff touches, never from the task's size."
---

# Ops Risks

A short, closed list of operational risks that show in a diff. It replaces a checklist read item by item with one question per risk: does this diff trigger it, and if so, where is the proof that it is handled? The architect lays the proof into a phase at Plan; the reviewer looks for it in the diff at Review. **Whether a risk applies follows from what the diff touches, never from the task's size.** It writes no artifact.

Security is not repeated here: secrets, network, data at rest, entry points, authorization, personal data in logs and analytics, permissions and third-party dependencies are the perimeter of `security-lens`. The design questions that lead to these risks — a rollout switch, stored data, a performance-sensitive path — are asked earlier, in the Secondary list of `feature-requirements`; this skill checks in the diff that the risks which follow from the answers have proof.

## Touches

A diff touches a behaviour when it changes that behaviour directly or through code on its path: code the behaviour calls, or code that calls it. When in doubt, it touches. A risk is triggered only by behaviour the diff touches; behaviour it does not touch is not judged, and does not become a case in `ManualChecks.md` (`manual-checks` → `## What a case must prove`).

## Risks

The list is closed. Each risk has a label, the trigger in the diff, the proof, and who can give it. "Code or test" means the agent can give the proof; "measurement or owner" means it needs a measurement on a device or an action by a person.

| Label | The diff | Proof | Who can give it |
|---|---|---|---|
| `startup` | adds work that runs at launch, or unconditionally in a Release build: initializing a service, a debug or preview feature, a heavy resource | the work is deferred or closed by a build condition, visible in the code | code; otherwise a measurement |
| `lifecycle` | adds or changes a reaction to foreground and background, a background task, a timer, a subscription to a system notification | the subscription has a consumer and is removed; a test or a live check | code or test |
| `stored-data` | changes a schema, a persisted model, the keys of settings, a file format | a migration and a test that reads the previous format, or the reason no migration is needed | code or test |
| `contract` | changes how an API response is parsed, a registered deep link route, or the public API of a package that has consumers | a test that the previous calls or links still work | test |
| `rollout-flag` | implements a feature for which `Task.md` or `Plan.md` declares a flag | every entry point of the feature is closed by the flag | code |
| `hot-path` | changes code that Research or Plan names performance-sensitive, or adds work per frame or per element of a large collection | a measurement, a benchmark test, or the reason neither is needed | measurement or test |
| `release-settings` | changes the minimum OS version, the build configuration, signing, the privacy manifest or the data disclosure of the store listing | the changes agree: the disclosure is updated together with the code, the minimum version matches the API in use | owner |

Left out on purpose: a profiler run, "tests are green in CI", a manual pass with a real finger, an accessibility pass, analytics funnels, a staged rollout plan, flag TTLs, a crash-free threshold.

## Plan

The architect walks the seven risks against what the task will touch. For each risk that triggers:

- the proof goes into the phase that gives it, as a checkbox or in the phase's `**Verification:**` line;
- the risk goes into the list of risks in `## For the owner` of `Plan.md`, worded as what the user will see, next to the phase that removes it (`task-documents` → `## Plan.md`).

`Plan.md` gets no section of its own for this.

## Review

1. From the task's diff the reviewer decides which risks triggered, by `## Touches`.
2. For each triggered risk the reviewer looks for the proof: in the diff, in the tests, in `Validation.md`.
3. No proof is a finding under `### Findings`, with an `**Impact:**`:
   - **Major**, blocking, when code or a test can give the proof (`lifecycle`, `stored-data`, `contract`, `rollout-flag`; `startup` when the work can be deferred in code);
   - **Minor**, not blocking, when a measurement or the owner is needed (`startup` where nothing can be deferred, `hot-path` without a benchmark test, `release-settings`); the finding says what to measure or update.

   A reason such as "the proof is not needed" that is closed by editing the task's files, with no code, goes under `## For Done` and by itself does not give `CHANGES_REQUESTED`, like any such finding.
4. `Review.md` gets a section `## Ops risks`: one line per triggered risk, `- <label> — <the proof in words> (<ref>)`, or the single line `- none triggered — the diff touches <X>`, where `<X>` names what the diff touches.
5. There is no case in ManualChecks.md for a risk, no Pending state, and no ritual of accept or defer.

On a repeated review `## Ops risks` is written anew over `review_ranges`; a risk closed in an earlier pass is not checked again unless the new commits touch it.

**Language.** The labels, `none triggered` and the heading `## Ops risks` are in English; everything after the dash is in `[LANG]`.

## Where it applies

| Profile | `## Plan` | `## Review` |
|---|---|---|
| FEATURE, BUG, REFACTOR | yes | yes |
| QUICK, REVIEW | no Plan stage | yes |
| TEST | — | — (the diff is tests only) |
| RESEARCH | — | — (there is no diff) |
| EPIC | — | — (its steps apply it) |

At both scales, `full` and `lite`: the list is short, and, as with `security-lens`, a risk follows from the subject of the task, not from its size.

A direct request such as "is this ready to ship?" has no task diff; it checks the same seven risks against the product.
