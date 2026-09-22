---
name: security-lens
description: "Use at the investigating stage of a FEATURE, BUG or REFACTOR task — or before Plan when its scale is lite — to decide whether the task touches the security perimeter and to run the security lens when it does, and at Review to check a skipped lens against the diff. Whether the lens runs follows from what the task touches, never from its size. Governed by `[SECURITY]` in Task.md and CLAUDE-spine-toolkit.md."
---

# Security Lens

The lens is the one look at security a task gets before its code is written: the reviewer sees the same change only as a diff. It costs a full dispatch, so it runs where the task touches something an attacker can reach, and nowhere else. **Whether it runs follows from the task's subject, never from its size.** A one-line change to where a secret is kept gets it on a `lite` task; a new screen of static text does not get it on a `full` one.

## The switch

`[SECURITY]` reaches a run as the contract's `security`.

| Value | What runs |
|---|---|
| `auto` (default) | the triage, then the lens only when the triage says the task touches the perimeter |
| `on` | the lens on every run, without a triage |
| `off` | neither; the run notes it |

`scale` does not move it. A platform that declares no agent for the `security` role runs neither and notes that.

The lens runs once per run, before the stage that first writes the task's analysis:

| Profile | `full` | `lite` |
|---|---|---|
| FEATURE | at Research, before the architect | before Plan; the findings go into its `## Research` section |
| BUG | at Diagnose, beside diagnostics and architect | before Plan, after Reproduce; the findings go into the plan's risks |
| REFACTOR | at Analyze, before the architect | before Plan; the findings go into its `## Analysis` section |

## Perimeter

A task touches the perimeter when it creates, changes or moves any of these:

- **credentials and secrets** — tokens, keys, passwords, and where they are kept;
- **network and transport** — the endpoints called, transport security settings, which certificates are trusted;
- **data at rest** — what is written to disk, a database, a cache or a shared container, and how it is protected;
- **external entry points** — deep links, URL schemes, HTTP endpoints, IPC: anything that takes input from outside the process;
- **authentication and authorization** — sign-in, sessions, token refresh, access checks;
- **personal data** — anything that identifies a person, including what reaches logs and analytics;
- **permissions and entitlements** — what the app asks the system or the user for;
- **third-party dependencies** — a library or SDK added, upgraded, or given new data.

The list is closed. A concern outside it is the reviewer's, not the lens's.

## Triage

A `light` dispatch of the `security` role's agent decides whether the lens runs.

- **It reads** `Task.md`, and `Reproduce.md` where the task has one. It may open the files and modules those name, to see what they touch. It does not audit the project.
- **It returns** `touches` (true or false); `perimeter`, the items of `## Perimeter` the task touches, by their bold names; and `reason`, one sentence in the output language.
- **When in doubt, `touches` is `true`.** A lens run for nothing costs one dispatch; a lens skipped over a secret costs the only look the task had before its code.
- `touches: true` with an empty `perimeter` means the whole list.

A triage that returns nothing runs the lens anyway.

## Lens

The lens assesses this task's perimeter, not the project. It writes no artifact and applies no patch: it returns `risks`, one finding per entry, and optional `notes`, and the writer of the analysis folds them in. Given a `perimeter` by the triage, it looks there; without one, at the whole list.

| Profile | What the lens is asked | What the writer does with the findings |
|---|---|---|
| FEATURE | what attack surface the feature adds | discusses every finding among the risks; none is dropped silently |
| BUG | whether the defect is itself a vulnerability, and which `## Perimeter` item it breaks; what the fix must not do — log a secret, widen a transport security exception, lower the protection of stored data to get past a crash; whether the same flaw sits on a neighbouring path | the synthesis weighs the findings against the other two lenses and names every disagreement |
| REFACTOR | which security properties the current code holds that the move must keep — the protection class of stored secrets, a single in-flight token refresh, transport trust settings, the visibility of an API that handles credentials | adds each property to the behaviour-preservation invariant that Validation and Review check |

## Verdict line

When the lens yields no findings, the writer of the analysis records why, as one line among the risks — in `Research.md` at `full`, in `Plan.md` at `lite`. The prefix stays English; the reason is in the output language.

| Case | Line |
|---|---|
| the triage found nothing to look at | `Security lens: skipped by triage — <reason>` |
| `[SECURITY]` is `off` | `Security lens: off by [SECURITY]` |
| the platform declares no agent for the role | `Security lens: no agent on this platform` |
| the lens returned nothing | `Security lens: returned nothing` |

No line is written when the lens returned findings: the findings are the record.

## Review rule

The reviewer reads the verdict line in `Research.md`, or in `Plan.md` where there is no `Research.md`. When the line says `skipped by triage` or `returned nothing` and the diff touches an item of `## Perimeter`, that is a finding: the file, the item, and a recommendation to rerun the stage the lens belongs to with `[SECURITY] = [on]`. It does not block, and it does not go into `blocking_findings`: the reviewer reads the diff for security anyway, and the rule exists so a skipped lens does not go unnoticed.

`off by [SECURITY]` and `no agent on this platform` raise nothing. The first is the owner's decision, and repeating it on every review is noise; the second is nothing the reviewer can fix.

## What this skill does NOT do

- It does not audit the project. A full audit is a direct request to the security agent, outside any task.
- It does not govern the RESEARCH profile's choice of `security` as its investigating agent.
- It adds no stage and writes no file of its own.
