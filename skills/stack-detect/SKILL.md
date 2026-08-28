---
name: stack-detect
description: |
  Pure side-effect-free per-axis Stack resolver. Computes needed axes (workflow envelope ∩ task scope) and runs the per-axis resolution chain, returning {needed, resolved, unresolved}. Activated by spine-toolkit:orchestrator; not invoked by the user directly.
  Use when (en): orchestrator resolves the Stack for a dispatched task
  Use when (ru): оркестратор резолвит Stack для диспетчеризуемой задачи
---

# Stack Detect

Pure resolver invoked by `spine-toolkit:orchestrator` during Resolution. It
performs **no** user questions, writes **no** files, and mutates **no**
`Task.md`. It returns structured data; the orchestrator owns all user-facing
interaction and caching.

## Input

```
task_files = [path, ...]      # the task's file scope (may be empty)
envelope   = {may: [axis...] | all, never: [axis...] | all}
task_id    = string
```

## Axes and signals come from the platform

This skill owns the algorithm and nothing else. Which axes exist and which values
each one allows is the `## Axes` table of the platform manifest; how a value is
read off a repository is its `## Heuristics` table. Both are obtained by invoking
`<platform>:manifest` — `<platform>` being the first non-empty line of the
`## Platform` block of the project config the orchestrator reads. The format of
both tables is `conventions/platform-contract.md`.

`ecosystem` is the one axis core requires every manifest to declare, and the only
one whose meaning core fixes. It is never detected and never asked about: a
project names the plugin that serves it outright in `## Platform`, so the value
is a property of the chosen platform rather than of the task's files. Hence its
exclusion in step 0 — which is what keeps it out of the empty-scope fallback of
step 3, where every other axis of the catalog is needed by default.

## Algorithm

```
0. platform := first non-empty line of ## Platform in CLAUDE-spine-toolkit.md
              # absent or empty → the orchestrator already stopped at Routing check 4
              #                   or step 5.7; this skill is never reached without it
   catalog  := ## Axes of <platform>:manifest       # axis → allowed values
   rules    := ## Heuristics of the same manifest
   axes     := keys of catalog − ecosystem

1. if envelope.never == all:
       return {needed: [], resolved: {}, unresolved: []}
       # orchestrator handles the ambient-info case; stack-detect is a no-op

2. scan := one pass over task_files producing:
       paths_implied   := axes flagged by the `path:` rows of rules
       imports_implied := values pinned by the `import:` / `token:` / `file:`
                          rows of rules
   (the scan result is computed once and reused in step 4)

3. may := (envelope.may == all) ? axes : (envelope.may ∩ axes)
   never := (envelope.never == all) ? axes : envelope.never
   needed := (may ∩ (paths_implied ∪ imports_implied)) − never
   if task_files is empty:
       needed := may          # early-stage fallback; AUQ deferred by orchestrator

4. for axis in needed, resolve via the per-axis chain (first hit wins):
       a. Task.md → ## 4. [Stack] line for axis
       b. project config → ## Modules (if a module entry matching a task file
          overrides the axis)
       c. project config → ## Stack line for axis
       d. imports_implied[axis] from step 2 (only axes some rule pins)
   resolved[axis]   := first hit
   unresolved       := needed axes with no hit

5. return {needed, resolved, unresolved}
```

## Reading the rules

- A file matching no `path:` row implies no axis, and forces no question on its
  own.
- A `path:` row's conditional add-on (`+ <axis> if …`) joins `paths_implied` only
  for a file the scan of step 2 shows to satisfy the condition — corroborated,
  never asserted. Where the condition names a signal some `import:` or `token:`
  row pins, that row is the check.
- Multi-module repo with no `## Modules` block: an axis takes the value fitting
  the majority of the changed files; on a tie it is returned unresolved. A tie is
  how the orchestrator's question happens — this skill never asks.

## Output

```
needed     = [axis, ...]
resolved   = {axis: value, ...}     # value ∈ catalog[axis]
unresolved = [axis, ...]            # subset of needed with no chain hit
```

## Invariants

- Never asks the user. Never writes files.
- `resolved` values are always members of the manifest's `## Axes` values for
  that axis: a heuristic hit outside them is discarded, leaving the axis
  unresolved rather than returning something the catalog does not list.
- `resolved.keys ∪ unresolved == needed` (every needed axis is accounted for).
- `task_files` empty ⇒ `needed == may`, resolution still attempted from
  `Task.md`/project config; AUQ deferral is the orchestrator's responsibility.
