# Task ranges

Where every repository of a task stood at three moments, and which commits Review reads because of
it. `scripts/task-ranges.sh` is the only thing that finds the repositories, writes the records'
values and computes the ranges; agents paste what it prints and never run `git rev-parse` for a
record themselves.

## Repositories of a task

The git toplevel of the project root, and of every folder `## Paths` names under `External
packages` or `Roots`; a listed folder that is not a repository contributes the checkouts directly
inside it. A repository is named by its toplevel relative to the project root — `.` for the
project itself. A repository at or inside the tasks folder is never one of them: the task's own
artifacts are not work to review. For the same reason a commit that touches only files inside the
tasks folder is never counted, when the project repository tracks that folder.
Every checkout those globs reach counts, touched by the task or not, so pulling a dependency after
Done offers a catch-up.

## Records

One line per repository, in this form:

```
[BASE_COMMIT] = .: 1a2b3c4d5e6f…
[BASE_COMMIT] = Packages/Core: 4d5e6f7a8b9c…
```

| Record | File | Written by | When |
|---|---|---|---|
| `[BASE_COMMIT]` | `Base.md` | the orchestrator, `record` | once, when a run first includes a stage that changes code and no phase has landed yet |
| `[REVIEWED_COMMIT]` | `Review.md`, directly under `[REVIEW_STATUS]` | the reviewer, from `tips --kind reviewed` | every Review |
| `[DONE_COMMIT]` | `Done.md`, its first lines | Done, from `tips --kind done` | every Done |
| `[REVIEW_FIXES]` | `Done.md`, after the `[DONE_COMMIT]` lines | Done, from `tips --kind done` | every Done |

`[REVIEW_FIXES] = <n>` is one line for the task, not per repository: the highest `Review fixes <n>`
phase in `Plan.md` when Done ran, `0` with none. The orchestrator counts a later loop's fix rounds
from it (its Gating).

A line with no repository — `[REVIEWED_COMMIT] = <sha>`, as reviewers wrote it before — is the
project's.

## Ranges

`ranges --since base|reviewed|done` gives, per repository, `<sha>..HEAD` from the matching record
and the number of commits in it. `rewritten` means the recorded sha is no longer an ancestor of
`HEAD`; `unknown` means there is no record for that repository. With no `Base.md`, `base` falls back
to the nearest merge base with the repository's main branch, local or `origin`'s, so commits one
of them holds and the other does not stay out; a merge base that is `HEAD` itself — work
committed on the main branch — is `unknown` too. When a record has several lines for one
repository, the first wins. The orchestrator turns the result into the
`review_ranges` contract field; which `--since` it asks for, and what it does on `rewritten` or
`unknown`, is its Resolution Algorithm, step 5.6; `fix-review` always asks for `--since reviewed`.

## Review and Done

Review reads exactly the ranges it is given. On a re-review it marks each Critical and Major of its
previous `Review.md` Resolved, Still open or Regressed — one still open or regressed is a finding of
this review too — and when no range holds a commit, and its own run committed no code before it, it
restates the open items instead of rescanning. A finding that editing files inside the task folder closes,
with no code commit, goes under `## For Done` in `Review.md` and never alone makes the verdict
`CHANGES_REQUESTED`. Done closes those items first and lists each under `## Review findings closed`.
