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
| `[REVIEWED_COMMIT]` | `Review.md`, in its closing block | the reviewer, from `tips --kind reviewed` | every Review |
| `[DONE_COMMIT]` | `Done.md`, in its closing block | Done, from `tips --kind done` | every Done |
| `[VALIDATED_COMMIT]` | `Validation.md`, in its closing block | the validator, from `tips --kind validated` | every Validation that ends PASSED |
| `[REVIEW_FIXES]` | `Done.md`, in its closing block, after the `[DONE_COMMIT]` lines | Done, from `tips --kind done` | every Done |
| `[BASE_DIRTY]` | `Base.md`, after the `[BASE_COMMIT]` lines | the orchestrator, `record` | with `[BASE_COMMIT]`, for each repository that had uncommitted changes then |

`[BASE_DIRTY] = <repository>: <sha1>` is a fingerprint of what that repository held uncommitted
when the base was recorded: one sha1 over the path and content of every uncommitted path outside
the tasks folder, untracked files included, staged or not alike. It is how `dirty` tells an
environment the project keeps uncommitted — dependencies switched to local checkouts, say — from
work of the task.

`[REVIEW_FIXES] = <n>` is one line for the task, not per repository: the highest `Review fixes <n>`
phase in `Plan.md` when Done ran, `0` with none. The orchestrator counts a later loop's fix rounds
from it (its Gating).

A line with no repository — `[REVIEWED_COMMIT] = <sha>`, as reviewers wrote it before — is the
project's.

Writers put these lines in the closing block (`conventions/stage-dispatch.md` → Closing block);
readers take them at any position, the first match per repository, because files written before
carry them on top.

## Ranges

`ranges --since base|reviewed|done|validated` gives, per repository, `<sha>..HEAD` from the matching record
and the number of commits in it. `rewritten` means the recorded sha is no longer an ancestor of
`HEAD`; `unknown` means there is no record for that repository. With no `Base.md`, `base` falls back
to the nearest merge base with the repository's main branch, local or `origin`'s, so commits one
of them holds and the other does not stay out; a merge base that is `HEAD` itself — work
committed on the main branch — is `unknown` too. When a record has several lines for one
repository, the first wins. The orchestrator turns the result into the
`review_ranges` contract field; which `--since` it asks for, and what it does on `rewritten` or
`unknown`, is its Resolution Algorithm, step 5.6; `fix-review` always asks for `--since reviewed`.
`validated` reads `Validation.md` and has no fallback: with no `[VALIDATED_COMMIT]` line a
repository is `unknown`, never measured from a merge base, because a Validation that did not end
PASSED has validated nothing.

`dirty` prints the name of each repository that has uncommitted changes, untracked files included,
outside the tasks folder (a tasks folder inside the repository is left out of the check), one per
line, and nothing when every repository is clean. A repository whose uncommitted state is still the
one its `[BASE_DIRTY]` line recorded is left out: that state was there before the task. Any change to
it after `record` — a new path, a path with other content, one gone — names the repository again; so
does uncommitted state in a repository with no `[BASE_DIRTY]` line, a `Base.md` written before the
line existed, or no `Base.md`. `count <repo> <sha>` prints the number of commits
in `<sha>..HEAD` outside the tasks folder, counted the way `ranges` counts; `rewritten` when `<sha>`
is not a commit of that repository or is not an ancestor of `HEAD`, and exit 2 when `<repo>` is not
a repository of the task. They are what the validation-scope lint, `scripts/lint-validation-scope.sh`, measures with.
The lint judges a `carried` row per repository: modules of one repository may be carried from
different Validations, so it reports a repository only when every `carried` row of it has commits
after its sha and the repository has no `ran` row. A `carried` sha that is not an ancestor of `HEAD`
(`rewritten`) is a finding of its own row.

`unreachable <sha>…` prints each sha that no repository of the task holds in `base..HEAD` —
reachable from `HEAD` alone where `Base.md` has no line or the base is `rewritten`. A sha a local
branch holds is not reported while `HEAD` is elsewhere, nor one of the tasks repository's own. It is
what `scripts/lint-walkthrough.sh` checks `Walkthrough.md` against.

`names` prints `<name> <path>` for each repository of the task, the tasks repository included and
last. The name is the folder of the checkout, the project root's included; where two checkouts
share a folder name, each one's name is its path from the project root. It is the name a commit
reference in `Walkthrough.md` carries, `<name>@<sha>`. `owners <sha>…` prints each sha followed by
the names of the repositories whose history of the task holds it, by the test `unreachable`
applies, and the sha alone when none does. `scripts/lint-walkthrough.sh` checks the name of every
reference against it.

`commits <a>..<b>` prints the commits of that range, `a` included, oldest first, along the first
parent — a merge's upstream side is not the task's — from whichever repository of the task, the
tasks repository included, holds both ends. It is how `scripts/lint-walkthrough.sh` reads the
ranges `Walkthrough.md` declares.

`last` prints `<repository> <sha>` for each repository of the task that holds a commit of its own
in `base..HEAD` outside the tasks folder: the newest such commit along the first parent, or
`unknown` where the base is missing or `rewritten`. A repository with no such commit is left out.
It is what `scripts/lint-walkthrough.sh --current` checks `Walkthrough.md` against.

## Validation ranges

Validation reads the `validation_ranges` contract field, two ranges per repository, both from
`ranges`: `task`, the whole range of the task (`--since base`), and `rerun`, the range since the last
passing Validation (`--since validated`). `rerun` is null when there is nothing to narrow from — a
restart, a `redo` of the Validation stage, a repository whose record is rewritten or unknown — and
null means the whole set runs. The orchestrator computes both in its Resolution Algorithm, step 5.6,
next to `review_ranges`. A Validation that ends PASSED writes its
`[VALIDATED_COMMIT]` lines in its closing block, from `tips --kind validated`.

## Review and Done

Review reads exactly the ranges it is given. On a re-review it marks each Critical and Major of its
previous `Review.md` Resolved, Still open or Regressed — one still open or regressed is a finding of
this review too — and when no range holds a commit, and its own run committed no code before it, it
restates the open items instead of rescanning. A finding that editing files inside the task folder closes,
with no code commit, goes under `## For Done` in `Review.md` and never alone makes the verdict
`CHANGES_REQUESTED`. Done closes those items first and lists each under `## Review findings closed`.
