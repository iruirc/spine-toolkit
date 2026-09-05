# Documentation Components

A **component** is a named unit of documentation a project declares once and refers to by name
ever after. The declaration lives in `DocsMap.md`; the levers live in `## Docs` of
`CLAUDE-spine-toolkit.md`; the matching is `scripts/docs-route.sh`.

## The record

```markdown
## Timeline

genre: state
strictness: blocking
places:
  - Documents/Timeline/
covers:
  - Sources/Timeline/**
```

| Field | Meaning |
|---|---|
| H2 | the component's name, unique across the project and every package it holds |
| `genre` | `state` or `tracker` |
| `strictness` | `blocking`, `advisory` or `off`; absent means the `## Docs` default |
| `places` | where the files are, one or more paths |
| `covers` | what a `state` component describes: code paths, globs or exact files |
| `fed_by` | what a `tracker` aggregates: task-folder patterns |

## Two genres, and why not three

`state` — how it works now and what must not break. It lives next to the code and is versioned
with it. `tracker` — what was done and in what order; a derived layer fed by task folders.

The third genre — the history of decisions, what was considered and rejected and why at the
time — is **not declarable**, because it is `Tasks/`, which the toolkit already owns. Two
declarable genres is the point: a fourth place for the same statement to live is a fourth place
for it to diverge.

## A name, not a path

The name is the only way to refer to a component. A path can move and a repository can change;
the name does not. The same reason a task is referred to by its full slug and not by
`Tasks/ACTIVE/<slug>` — the path breaks on the day the task closes.

## One component, one home

A component is not split along a repository boundary, even when its `covers` reach wider than
the repository holding its `places`. Splitting a single rule in half to satisfy a checkout
layout is how one rule becomes two rules that disagree. `places` may list several paths; they
are one document on one subject, never halves.

`scripts/docs-route.sh audit` reports a component none of whose coverage shares a repository
with its `places`. That is a finding, not an error: moving costs money, and knowing about the
wrong home is useful on its own, because routing names the touched document either way.

## One origin for every path

Every path the mechanism handles — in `places`, in `covers`, in a change set — is relative to the
**project root**. In a multi-repository project that root is the container the checkouts sit in,
and it is usually not a repository itself.

A diff is the one thing that does not arrive that way: `git` prints paths relative to the
checkout it ran in. Re-origin it before feeding it in:

```sh
{ git diff --name-status
  git -C <checkout> diff --name-status | scripts/docs-route.sh reorigin <checkout>
} | scripts/docs-route.sh check <project-root> --task-dir <dir> --phase <id>
```

One phase touching code in one checkout and its documentation in another is not an edge case —
it is the case the mechanism exists for, and it is the same shape in every ecosystem, whatever
the checkouts are called there.

## Declaration order

The registry is assembled project map first, then each package map in path order, and that
order is load-bearing: a task is fed to the **first** tracker whose `fed_by` pattern matched.
A catch-all tracker is declared last. There is no exception syntax — it would be a second way
to say the same thing.

## Patterns

List items are indented by two spaces. A bullet at column zero is prose, not a value — the file
is Markdown, and a format that reads every dash as data cannot carry a sentence.

A pattern with no glob character matches the path itself and everything under it, so a bare
directory need not remember its trailing slash. `**` crosses separators; `*` does not.

Globs and exact files mix in one `covers` list, and both are needed. A glob covers a domain cut
along directories. An explicit list of files covers an entity spread across someone else's
layout — three unrelated branches of one package, where a glob either misses or over-reaches.

## What the mechanism does not decide

Routing says a component **may** have been touched. Whether documentation is owed is a separate
question, answered per phase in the task's `Docs.md`, in the vocabulary `ops-checklist` already
uses: **Applicable** / **N/A (reason)** / **Pending**, defaulting to Applicable. The criterion,
and what makes a good reason, is the `docs-route` skill.

## Suspending the mechanism

`## Docs` → `enabled: off` stops the four commands a run invokes — `route`, `check`, `audit` and
`tracker` — while leaving `registry` able to read the file. That is the difference between a pause
and a deletion: the declarations survive, and a single task can still opt back in with
`[DOCS] = [on]`.

A registry that does not exist has the same effect and needs no lever, which is the state every
project starts in.

## Scale

`conventions/task-scale.md` does not move `strictness`. The floor is identical at both values.
