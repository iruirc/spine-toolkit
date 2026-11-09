# Model tiers: one `[MODELS]` for Claude Code and Codex

**Date:** 2026-11-10
**Case:** `spine-todo-cases/spine-codex-runtime-model-defaults.md`
**Type:** FEATURE. Changes the meaning of `[MODELS]` and the Claude Code model defaults.

## Problem

The `SPINE.md` template gives the `light` and `validator` keys the model `sonnet`. In Codex,
`runtimes/codex-cli.json` reads Claude names as `session` (`as_session`), and the resolver prints
`'validator: sonnet' is not a codex-cli model, read as session`. The intent — a lighter model for these
roles — is lost in Codex, and a shared config cannot express it without a Claude name. The message does
not tell the owner what happened or what to do.

## The decision in one paragraph

`[MODELS]` gains the value `fast`, a tier. What `fast` becomes in each runtime the owner writes in a new
project-only block, `[MODEL_TIERS]` (`fast@claude-code: sonnet`, `fast@codex-cli: <model>`). No line
for the runtime → the key runs on `session`. Spine never picks a model on its own. Claude names keep
working as today; `setup` offers to move `sonnet` entries to `fast`.

## 1. Format and resolution

### `[MODEL_TIERS]`

```
[MODEL_TIERS] = [fast@claude-code: sonnet, fast@codex-cli: gpt-5-mini]
[MODELS] = [light: fast, validator: fast, developer: session, ...]
```

- Key `<tier>@<runtime id>`. The only tier is `fast`.
- Value: a value of that runtime's `models` in `runtimes/<id>.json`, or `session`. Under `"any"`
  (Codex), any `TOKEN`, kept as written.
- Project-only: Task.md, an epic and `--set` do not set it (like the `PROJECT_ONLY` fields).
- Lines for every runtime are checked against their own runtime file on every run. A bad entry is
  skipped with the usual `'<entry>' not recognized, skipped`:
  - the tier is not `fast`;
  - no `runtimes/<id>.json` for the runtime;
  - the value is outside that runtime's `models` (`fast@claude-code: gpt-5-mini`);
  - the value is in that runtime's `as_session` (`fast@codex-cli: opus`).

### Resolving a key

1. The `[MODELS]` chain is unchanged: `--set` → Task.md → epic → project config → `model_defaults`.
2. `fast` is a valid `[MODELS]` value in every runtime, for every key (roles, `light`, `walkthrough`,
   `done`).
3. A key resolved to `fast` → the `fast@<RUNTIME>` line of `[MODEL_TIERS]`. No line → `session`, plus
   a stderr line (section 2).
4. `session` is always `session`. A plain model name passes as today. A name in `as_session` →
   `session`, as today.

### Defaults

- `runtimes/claude-code.json`: `model_defaults` = `{light: fast, validator: fast}`.
- `runtimes/codex-cli.json`: `model_defaults` stays empty.
- `load_runtime` accepts tiers as well as `models` values in `model_defaults`.
- **Behavior change:** in Claude Code, a project with no `[MODELS]` entry for `light`/`validator` and
  no `[MODEL_TIERS]` moves from `sonnet` to `session`. Projects made from the old template are not
  affected: they carry `sonnet` explicitly. The release notes say so.

### Output

- `json`: `models` holds the final values (what dispatch receives; format unchanged). New field
  `model_tiers`: for each key resolved through `fast`, `{"tier": "fast", "model": <final>,
  "source": "project" | "unset"}`.
- `show` and the opening block: `validator: fast → sonnet`, or
  `validator: fast → session, no fast@codex-cli`. Config syntax, not prose, so not localized. A key
  whose tier has no line is always in the column, chosen or not.

## 2. Messages

### Resolver stderr — a protocol for the orchestrator

- `<source> [MODELS]: '<entry>' has no fast@<runtime> in [MODEL_TIERS], read as session` — new.
- `<source> [MODELS]: '<entry>' is not a <runtime> model, read as session` — unchanged.
- `<CFG> [MODEL_TIERS]: '<entry>' not recognized, skipped` — the shared `warn` format.

A line about a key is printed only by the source that decided the key, as today.

### Texts for the owner

The orchestrator maps the stderr lines to locale keys (`skills/orchestrator/SKILL.md`, the table row
next to `is not a <runtime> model`). Each text names the source, the reason, the result and the action.

- New key `warn_model_tier_unset` (en/ru). English sense: "`{entry}` in {source}: `[MODEL_TIERS]` has
  no `fast@{runtime}` line, so that role runs on the session's model. To choose a model, add
  `fast@{runtime}: <model>` to `[MODEL_TIERS]`."
- `warn_model_read_as_session` rewritten: "`{entry}` in {source} names a Claude Code model, which
  {runtime} does not have, so that role runs on the session's model. To choose a model for this
  runtime, set the value to `fast` and add `fast@{runtime}: <model>` to `[MODEL_TIERS]`; `setup`
  offers to do it."
- `warn_tuning_unrecognised` (which lists the valid model values) gains `fast`.

### Where they show

- Source Task.md or `--set`: one line when the task starts, as today.
- Source the project config: no separate warning at task start; the result is in the model line of
  the opening block. The full explanation and the migration come from `setup`.
- `runtimes/codex-cli.md` gains a rule: the resolver's stderr is never relayed to the user as is,
  only the locale texts the orchestrator's table names.

## 3. Template, setup, migration

### Template

`templates/spine-md/en.md`:

```
[MODEL_TIERS] = [fast@claude-code: sonnet]
[MODELS] = [light: fast, walkthrough: session, done: session, architect: session, developer: session, tester: session, reviewer: session, refactorer: session, validator: fast, security: session, diagnostics: session]
```

### New project

- Claude Code: writes only `fast@claude-code: sonnet`, asks nothing about Codex.
- Codex: one question, the model for `fast` in Codex — "keep the session's model" / free-form answer.
  The answer is written as `fast@codex-cli: <model>`. No list of models is offered: Spine cannot know
  what the account has.

The edits to `SPINE.md` are made by a small script, `scripts/model-tiers.sh` (`check`, `apply`),
not by hand, so they are tested and idempotent.

### Existing project (setup run again, either runtime)

- `[MODELS]` has `sonnet` entries → one question: replace them with `fast` for the listed keys and add
  `[MODEL_TIERS]` with `fast@claude-code: sonnet` — "Yes" / "No, keep as is". In Codex, "Yes" is
  followed by the `fast@codex-cli` question.
- This question replaces the current `report_models_read_as_session` report.
- `opus`, `haiku`, `fable` and full Claude ids are not migrated.
- An existing `[MODEL_TIERS]` is never overwritten; only the current runtime's missing line is added.
- The 1.x migration (the pre-2.0 config name, states D–F) copies values as written.

## 4. Documentation and tests

### Documentation

- `docs/configuration.md`: a `[MODEL_TIERS]` section; `[MODELS]` gains `fast` and a table
  "value → Claude Code → Codex" for `session`, `fast` with and without a line, `sonnet`, a Codex
  model name.
- `conventions/task-settings.md`: a `model_tiers` row, the new defaults, tiers in `model_defaults`.
- `runtimes/codex-cli.md`: the models paragraph, the stderr rule.
- `skills/orchestrator/SKILL.md` and `locales/{en,ru}.md`; `skills/setup/SKILL.md` and its locales,
  with en/ru parity.

### Tests (bats, test first)

- `tests/foundation/lib/model-and-effort.test.bats`: `fast` with and without a line in both runtimes;
  defaults; explicit `session`; `[MODEL_TIERS]` in Task.md ignored; bad `[MODEL_TIERS]` entries
  (tier, runtime, vocabulary, `as_session`); `show` and `json` (`model_tiers`).
- `tests/foundation/lib/runtimes.test.bats`: a tier in `model_defaults` passes the check.
- `tests/foundation/lib/codex-runtime-text.test.bats` and the locale parity tests.
- Regression: the field config (`light: sonnet`, `validator: sonnet`) in both runtimes gives
  the documented result.

## Out of scope

- Tiers other than `fast`.
- `[MODEL_TIERS]` in Task.md or `--set`.
- Discovering which models an account has.
- A release and its notes; changes to the installed Spine cache or to the field project.
