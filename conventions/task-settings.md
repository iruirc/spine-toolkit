# Task Settings

`scripts/resolve-settings.sh` is the one reader of a task's settings — the only code that opens
`Task.md` and `CLAUDE-spine-toolkit.md` to decide what a run does. Every other surface takes the
value already resolved: from the Outbound Contract when it is a workflow script or a Method B
skill dispatched by the orchestrator, or from the script's own `json` / `show` / `raw`
subcommands when it is a standalone tool such as `docs-route.sh` or `lint-artifact-budget.sh`. A
consumer that walks `Task.md` or the config itself, instead of reading the value it was handed, is
a second reader — and the orchestrator-contract test suite treats that as a defect, not a style
choice.

## The chain

```
Task.md  →  the epic's Task.md for a .step/ folder  →  the nearest CLAUDE-spine-toolkit.md at or above the task dir  →  the default
```

First hit wins. `walkthrough` inserts one step between the task and the config, ahead of it rather
than instead of it:

```
Task.md [WALKTHROUGH]  →  off when scale resolved to lite  →  CLAUDE-spine-toolkit.md ## Reporting → walkthrough  →  deep
```

The task's own `[WALKTHROUGH]` is checked before the `lite` gate and wins outright; the project's
config is checked *after* the gate, so it never overrides `lite` the way the task's own line can
(the second decision below).

**A missing key is the default, not an error.** A task file that never names the field, a project
with no such block, a block with no such key — each is a link that contributes nothing and hands
the question to the next. Nothing stops because a setting was left unwritten, and a project that
has never opened its config runs on the defaults of the release it is on.

**An unrecognized value is reported, and the chain continues past it.** The resolver names the
entry on stderr and moves to the next link, so a typo in a task's `[DRIVE_APP]` lands on the
project's choice rather than on the built-in default. This is what the two map fields always did,
and it is the less surprising of the two outcomes: silently preferring the built-in default to the
value a project wrote down looks, from the project's side, like its config being ignored. The
warning is printed either way. Two entries are not covered by it: `progress`, whose resolved value
the opening block prints anyway, is skipped in silence; and `[WALKTHROUGH] = [on]`, the pre-depth
spelling, is read as `deep` and reported in words of its own, because a migration is not a typo.

## Fields

| Field | `Task.md` | Config | Values | Default |
|---|---|---|---|---|
| `lang` | — | `## Language`, first value line | `en` `ru` | `en` |
| `mode` | `[WORKFLOW_MODE]` | `## Mode`, first value line | `manual` `auto` | `manual` |
| `progress` | — | `## Progress`, first value line | `quiet` `normal` `live` | `normal` |
| `settings_report` | — | `## Progress` → `settings` | `diff` `full` `off` | `diff` |
| `scale` | `[SCALE]` | `## Scale`, first value line | `lite` `full` | `full` |
| `walkthrough` | `[WALKTHROUGH]` | `## Reporting` → `walkthrough` | `brief` `deep` `off` | `off` when `scale` is `lite`, else `deep` |
| `drive_app` | `[DRIVE_APP]` | `## Validation` → `drive_app` | `auto` `off` | `auto` |
| `manual_checks` | `[MANUAL_CHECKS]` | `## Validation` → `manual_checks` | `auto` `always` | `auto` |
| `driver` | `[DRIVER]` | `## Validation` → `driver` | a plugin name, `auto`, `—` | `auto` |
| `phase_verification` | `[PHASE_VERIFICATION]` | `## Validation` → `phase_verification` | `proportional` `full` | `proportional` |
| `docs_lever` | `[DOCS]` | `## Docs` → `enabled` | `on` `off` | `on` |
| `docs_map` | — | `## Docs` → `map` | a path | `DocsMap.md` |
| `docs_strictness` | — | `## Docs` → `strictness` | `blocking` `advisory` `off` | `advisory` |
| `docs_freshness` | — | `## Docs` → `freshness` | `on` `off` | `on` |
| `budgets` | — | `## Budgets`, one `<artifact>: <lines>` per line | a positive integer | the `CAPS` table |
| `models` | `[MODELS]` | `## Models`, one `<key>: <value>` per line | `opus` `sonnet` `haiku` `fable` `session` | `sonnet` for `light` and `validator`, `session` for the other seven roles |
| `effort` | `[EFFORT]` | `## Effort`, one `<role>: <value>` per line | `low` `medium` `high` `xhigh` `max` `session` | `session` |

`driver` walks this same chain but never rides the Outbound Contract: a workflow script must not
gate on it, so it stays a pre-flight concern of the orchestrator alone
(`conventions/driver-contract.md`; `tests/foundation/lib/orchestrator-contract.test.bats` — "the
driver does not travel").

## Two decisions

**A step inherits the epic, key by key.** A `.step/` folder's own `Task.md` overrides any field it
names; a field it does not name reaches it from the epic's own resolved value, not from the
project default directly — the epic is the step's config, one layer closer than
`CLAUDE-spine-toolkit.md`. `profile-epic.js`'s `stepArgs()` is this rule for the fields a script
forwards; a step's own `resolve-settings.sh` run is the same rule for the fields it reads for
itself.

**`walkthrough`'s task override beats `lite`; the project's config does not.** The chain above
checks the task's own `[WALKTHROUGH]` before it checks whether `scale` resolved to `lite` — an
explicit `[WALKTHROUGH] = [deep]` writes the file on a `lite` run. The project's `## Reporting` →
`walkthrough` sits *after* the `lite` step, not before it: a config that turns the file on cannot
out-rank the `lite` floor the way the task's own line can. Only the task's own word on its own file
beats the axis (`conventions/task-scale.md` → Explicit beats the axis).

An epic's `[WALKTHROUGH]` beats the gate at the same rank, for a step that names none of its own:
it is a task file, read before the gate, and the first decision above is what makes the epic the
step's own word rather than its config.
