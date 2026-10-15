# Task Settings

`scripts/resolve-settings.sh` is the one reader of a task's settings — the only code that opens
`Task.md` and the project config to decide what a run does. Every other surface takes the
value already resolved: from the Outbound Contract when it is a workflow script or a Method B
skill dispatched by the orchestrator, or from the script's own `json` / `show` / `raw`
subcommands when it is a standalone tool such as `docs-route.sh` or `lint-artifact-budget.sh`. A
consumer that walks `Task.md` or the config itself, instead of reading the value it was handed, is
a second reader — and the orchestrator-contract test suite treats that as a defect, not a style
choice.

## Project config

**project config** — `SPINE.md` in the nearest directory at or above the task that holds either
file, or `CLAUDE-spine-toolkit.md` in that same directory where no `SPINE.md` exists. Never both,
never merged. `CLAUDE-spine-toolkit.md` is the name every project carried before the toolkit ran in
more than one runtime; `setup` renames it on request, and a project that keeps it runs exactly as
before.

The lookup, in `scripts/resolve-settings.sh`:

1. From the task directory upward, the first directory holding `SPINE.md` **or**
   `CLAUDE-spine-toolkit.md` is the configuration boundary. Nothing above it is read.
2. In that directory: `SPINE.md` when present, else `CLAUDE-spine-toolkit.md`.
3. Both present: `SPINE.md`, and one stderr line —
   `project config: <abs>/SPINE.md selected, <abs>/CLAUDE-spine-toolkit.md ignored`. The two files
   are not compared: a project that keeps a stale copy beside the real one is told so, not stopped.
4. Neither, up to the filesystem root: no config, and every field is its default.

So a legacy file in the task's own directory beats a `SPINE.md` above it: the boundary is the
nearest directory holding either name. The resolver's `json` carries the selected file as
`project_config`, an absolute path or `null`; a consumer that needs the file itself — not a value
from it — takes the path from there rather than looking the name up a second time. `raw` reads the
same file `json` selects.

## Runtime

The runtime is the host the toolkit runs in — Claude Code, or another CLI that loads the same
skills. What differs between runtimes, as far as settings go, is the vocabulary of `models` and
`effort` and the model defaults, and that lives in one small file per runtime,
`runtimes/<id>.json`:

| Field | Meaning |
|---|---|
| `id` | the runtime id, equal to the file's name |
| `models` | the list of values `[MODELS]` may take, or the string `"any"`: any token matching `[A-Za-z0-9][A-Za-z0-9._:/+-]*` passes through as written, for the runtime to check when it spawns |
| `model_defaults` | the keys whose default is not `session`; every key absent here defaults to `session` |
| `effort` | the list of values `[EFFORT]` may take; the default is always `session` |

`session` is in every list and means what it always did: pass nothing, run on the session's own
model or effort. `scripts/resolve-settings.sh json|show|open <task-dir> --runtime <id>` selects the
file; without the flag the resolver answers as `claude-code`, so every caller that predates the
flag — the opening-block hook, `docs-route.sh`, the workflow scripts — gets the result it always
got. `raw` and `open --contract` take no flag. An id with no file is a usage error (exit 2) naming
the missing `runtimes/<id>.json`. The id is given by the caller, which knows the host it runs in —
the orchestrator passes `--runtime claude-code` in Claude Code; nothing infers a runtime from the
environment or a process name. A value outside the runtime's list is reported and skipped like any
other unrecognized value, and the chain goes on.

## The chain

```
run  →  Task.md  →  the epic's Task.md for a .step/ folder  →  the project config at or above the task dir  →  the default
```

First hit wins. `run` is what the owner said for this run alone — `--set <field>=<value>`, or
`--set <field>.<key>=<value>` for one key of a map, as many as the run names. A run may set exactly
the fields a task may: every field below with a `Task.md` column. Anything else is named on stderr
as `--set <field>: not a field a run can set, skipped`; a value the field does not take is reported
as a typo in `Task.md` is, and the chain goes on. Nothing here writes the value anywhere: it lives
in the run, and the orchestrator keeps it in `Run.json` until the range it was said for is done.
One exception: `--set scale=lite` never lowers a `[SCALE] = [full]` the task's or the epic's
`Task.md` carries (`conventions/task-scale.md` → The ratchet). `walkthrough` inserts one step between the task and the config, ahead of it rather
than instead of it:

```
run  →  Task.md [WALKTHROUGH]  →  off when scale resolved to lite  →  the project config [WALKTHROUGH]  →  deep
```

The task's own `[WALKTHROUGH]` is checked before the `lite` gate and wins outright; the project's
config is checked *after* the gate, so it never overrides `lite` the way the task's own line can
(the second decision below).

`walkthrough_check` follows the depth it checks. Its chain is the ordinary one and ends at `auto`,
but only `on` or `off` leaves the resolver: `auto` becomes `on` where `walkthrough` resolved to
`deep` and `off` where it resolved to `brief`. Wherever `walkthrough` resolves to `off` — the `lite`
gate included — `walkthrough_check` is `off` as well, there being no file to check. Where that
overrode a chosen `on`, or where the value came from `auto`, the source reads `walkthrough`, and
`show` names the value that was displaced.

**A missing field is the default, not an error.** A task file that never names the field, a config
that does not name it either — each is a link that contributes nothing and hands the question to
the next. Nothing stops because a setting was left unwritten, and a project that has never opened
its config runs on the defaults of the release it is on.

**An unrecognized value is reported, and the chain continues past it.** The resolver names the
entry on stderr and moves to the next link, so a typo in a task's `[DRIVE_APP]` lands on the
project's choice rather than on the built-in default. This is what the two map fields always did,
and it is the less surprising of the two outcomes: silently preferring the built-in default to the
value a project wrote down looks, from the project's side, like its config being ignored. The
warning is printed either way. Two entries are not covered by it: `progress`, whose resolved value
the opening block prints anyway, is skipped in silence; and `[WALKTHROUGH] = [on]`, the pre-depth
spelling, is read as `deep` and reported in words of its own, because a migration is not a typo.

## Fields

Both files spell a field the same way; a `—` in the `Task.md` column is a field the config alone
answers.

| Field | `Task.md` | Config | Values | Default |
|---|---|---|---|---|
| `lang` | — | `[LANG]` | `en` `ru` | `en` |
| `mode` | `[WORKFLOW_MODE]` | `[WORKFLOW_MODE]` | `manual` `auto` | `manual` |
| `progress` | — | `[PROGRESS]` | `quiet` `normal` `live` | `normal` |
| `settings_report` | — | `[SETTINGS_REPORT]` | `diff` `full` `off` | `diff` |
| `scale` | `[SCALE]` | `[SCALE]` | `lite` `full` | `full`; always `lite` for a `QUICK` task |
| `walkthrough` | `[WALKTHROUGH]` | `[WALKTHROUGH]` | `brief` `deep` `off` | `off` when `scale` is `lite`, else `deep` |
| `walkthrough_check` | `[WALKTHROUGH_CHECK]` | `[WALKTHROUGH_CHECK]` | `auto` `on` `off` | `auto`: `on` at `deep`, `off` at `brief`; `off` wherever `walkthrough` is `off` |
| `drive_app` | `[DRIVE_APP]` | `[DRIVE_APP]` | `auto` `off` | `auto` |
| `manual_checks` | `[MANUAL_CHECKS]` | `[MANUAL_CHECKS]` | `auto` `always` | `auto` |
| `manual_checks_check` | `[MANUAL_CHECKS_CHECK]` | `[MANUAL_CHECKS_CHECK]` | `on` `off` | `on` |
| `driver` | `[DRIVER]` | `[DRIVER]` | a plugin name, `auto`, `—` | `auto` |
| `device` | `[DEVICE]` | `[DEVICE]` | `auto`, or a device in the platform's own terms | `auto` |
| `phase_verification` | `[PHASE_VERIFICATION]` | `[PHASE_VERIFICATION]` | `proportional` `full` | `proportional` |
| `fix_rounds` | `[FIX_ROUNDS]` | `[FIX_ROUNDS]` | a whole number ≥ 0 | `2` |
| `security` | `[SECURITY]` | `[SECURITY]` | `auto` `on` `off` | `auto` |
| `docs_lever` | `[DOCS]` | `[DOCS]` | `on` `off` | `on` |
| `docs_map` | — | `[DOCS_MAP]` | a path | `DocsMap.md` |
| `docs_strictness` | — | `[DOCS_STRICTNESS]` | `blocking` `advisory` `off` | `advisory` |
| `docs_freshness` | — | `[DOCS_FRESHNESS]` | `on` `off` | `on` |
| `device_source` | — | `[DEVICE_SOURCE]` | a command run from the project root, `—` | `—` |
| `budgets` | — | `[BUDGETS]`, entries `<artifact>: <lines>` | a positive integer | the `CAPS` table |
| `models` | `[MODELS]` | `[MODELS]`, entries `<key>: <value>` | the runtime's `models` list (`runtimes/<id>.json`); `session` always | the runtime's `model_defaults`, `session` elsewhere: in Claude Code `sonnet` for `light` and `validator` |
| `effort` | `[EFFORT]` | `[EFFORT]`, entries `<key>: <value>` | the runtime's `effort` list (`runtimes/<id>.json`); `session` always | `session` |
| `long_run` | `[LONG_RUN]` | `[LONG_RUN]`, entries `<key>: <minutes>` | keys `stall` `max`, a whole number of minutes > 0 | `stall: 5, max: 30` |

`driver` walks this same chain but never rides the Outbound Contract: a workflow script must not
gate on it, so it stays a pre-flight concern of the orchestrator alone
(`conventions/driver-contract.md`; `tests/foundation/lib/orchestrator-contract.test.bats` — "the
driver does not travel").

`fix_rounds` is the orchestrator's alone too: how many `fix-review` rounds `auto` runs by itself
after Review returns `CHANGES_REQUESTED`, `0` for none. It never rides the Outbound Contract; the
loop is in the orchestrator's Gating.

## Two decisions

**A step inherits the epic, key by key.** A `.step/` folder's own `Task.md` overrides any field it
names; a field it does not name reaches it from the epic's own resolved value, not from the
project default directly — the epic is the step's config, one layer closer than
the project config. `profile-epic.js`'s `stepArgs()` is this rule for the fields a script
forwards; a step's own `resolve-settings.sh` run is the same rule for the fields it reads for
itself.

**`walkthrough`'s task override beats `lite`; the project's config does not.** The chain above
checks the task's own `[WALKTHROUGH]` before it checks whether `scale` resolved to `lite` — an
explicit `[WALKTHROUGH] = [deep]` writes the file on a `lite` run. The project's own
`[WALKTHROUGH]` sits *after* the `lite` step, not before it: a config that turns the file on cannot
out-rank the `lite` floor the way the task's own line can. Only the task's own word on its own file
beats the axis (`conventions/task-scale.md` → Explicit beats the axis).

An epic's `[WALKTHROUGH]` beats the gate at the same rank, for a step that names none of its own:
it is a task file, read before the gate, and the first decision above is what makes the epic the
step's own word rather than its config.
