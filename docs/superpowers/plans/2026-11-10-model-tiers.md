# Model Tiers Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** One `[MODELS]` serves Claude Code and Codex: a key may say `fast`, and the project's
`[MODEL_TIERS]` says what `fast` is in each runtime; without a line it is `session`.

**Architecture:** `scripts/resolve-settings.sh` (embedded Python) parses `[MODEL_TIERS]`, resolves
`fast` after the `[MODELS]` chain, and reports through stderr, `json` and the settings column. The
orchestrator maps the new stderr line to a locale key. A new `scripts/model-tiers.sh` makes the
`SPINE.md` edits `setup` offers. Docs, template and locales follow.

**Tech Stack:** bash + embedded python3, bats (`bats_require_minimum_version 1.5.0`), Markdown skills and locales.

**Spec:** `docs/superpowers/specs/2026-11-10-model-tiers-design.md`

## Global Constraints

- The only tier is `fast`. Tier and runtime are matched case-insensitively; a model value keeps its spelling under `"models": "any"`.
- `[MODEL_TIERS]` is read from the project config only; Task.md, the epic and `--set` never set it.
- Key spelling `<tier>@<runtime id>`, regex `([A-Za-z]+)@([a-z0-9-]+)\s*:\s*(\S+)` (after lowercasing the key part).
- No line for the runtime → `session`. Spine never chooses a model.
- `runtimes/claude-code.json` `model_defaults` = `{"light": "fast", "validator": "fast"}`; `codex-cli.json` stays `{}`.
- New stderr line, exact: `<label>: '<entry>' has no fast@<runtime> in [MODEL_TIERS], read as session`, `<label>` as for the existing `is not a <runtime> model` line.
- Existing stderr lines keep their exact text.
- Settings column text: `<key>: fast → <model>` when set, `<key>: fast → session, no fast@<runtime>` when not.
- User-facing strings only through locale keys, en and ru with identical `## ` key sets.
- Repo language is English. No AI attribution in commits.
- No version bump, no changelog.

## Review Focus

1. Case and spacing: `Validator: FAST`, `FAST@Codex-CLI: gpt-x` should resolve like the lowercase form; `fast @ codex-cli: x` is not recognized and skipped with the usual warning (Task 1 test).
2. `fast@codex-cli: session` written explicitly: `session`, and no "has no fast@" line (Task 1 test).
3. A key set to `fast` by `--set` or Task.md resolves through the project's tiers, keeps source `run`/`task`, and its stderr label names that source (Task 1 test).
4. `model-tiers.sh apply` run twice changes nothing the second time, and rewrites `sonnet` in every `[MODELS]` line of a config that folds several (Task 5 test).
5. Two lines for the same `fast@<runtime>`: the later one wins, as a map entry does (Task 1 test).

---

### Task 1: Resolve `fast` through `[MODEL_TIERS]`

**Files:**
- Modify: `runtimes/claude-code.json`
- Modify: `scripts/resolve-settings.sh` (`load_runtime` ~l.167, the `MAPS` loop ~l.315–353, `json` output ~l.682)
- Test: `tests/foundation/lib/model-and-effort.test.bats`, `tests/foundation/lib/runtimes.test.bats`, `tests/foundation/lib/settings-resolver.test.bats`

**Interfaces:**
- Produces (Python, inside the heredoc):
  - `TIERS = ('fast',)`
  - `runtime_vocab(runtime_id) -> (models, as_session) | None` — non-fatal reader of another runtime's file; `load_runtime` keeps its fatal behavior for `--runtime`.
  - `MODEL_TIERS: dict[(tier, runtime), str]` — valid project entries, later wins.
  - `MODEL_TIER_OF: dict[key, {"tier": "fast", "model": str, "source": "project" | "unset"}]` — every `models` key whose chain ended at `fast`, defaults included.
- Produces (json): top-level `model_tiers` = `MODEL_TIER_OF` (always present, `{}` when empty). `models` holds final values.

- [ ] **Step 1: Update the runtime-file tests**

In `runtimes.test.bats`: the shape check accepts `model_defaults` values in `models` **or** `fast`; "the two first-iteration runtimes…" asserts `model_defaults["light"] == "fast"` and `model_defaults["validator"] == "fast"`.

In `settings-resolver.test.bats` the spec's behavior change lands in two existing tests, rewritten, not deleted:
- "a project that says nothing resolves … light and validator at sonnet" (~l.318) → retitle "… light and validator at fast, read as session"; expect `light`/`validator` `session`, `model_tiers.light.source == unset`; `source_of models` stays `default`.
- "light: platform reads as absent, so light keeps its sonnet default" (~l.330) → "… keeps its fast default"; expect `session`, stderr still empty.
- Leave the 1.11.0 test (~l.337) and "the shipped config template resolves to the defaults…" (~l.432) as they are: both carry `sonnet` explicitly and must stay green unchanged.

In `model-and-effort.test.bats` the template assertion changes in Task 3, not here. Add, using `rt_task` and `json_field`:

```bash
@test "fast resolves through the project's MODEL_TIERS in each runtime" {
  p="$BATS_TEST_TMPDIR/p"; t="$(rt_task "$p")"
  printf '[MODEL_TIERS] = [fast@claude-code: sonnet, fast@codex-cli: gpt-6-mini]\n[MODELS] = [validator: fast]\n' > "$p/SPINE.md"
  run --separate-stderr "$ROOT/scripts/resolve-settings.sh" json "$t"
  [ "$status" -eq 0 ]; [ -z "$stderr" ]
  [ "$(json_field 'd["models"]["validator"]' <<<"$output")" = "sonnet" ]
  [ "$(json_field 'd["model_tiers"]["validator"]["source"]' <<<"$output")" = "project" ]
  run --separate-stderr "$ROOT/scripts/resolve-settings.sh" json "$t" --runtime codex-cli
  [ "$(json_field 'd["models"]["validator"]' <<<"$output")" = "gpt-6-mini" ]
}
```

Further tests, same shape, with these exact expectations:
- `fast without a line for the runtime reads as session and says so`: config `[MODEL_TIERS] = [fast@claude-code: sonnet]` + `[MODELS] = [validator: fast]`, `--runtime codex-cli` → `models.validator == session`, `model_tiers.validator.source == unset`, stderr contains `'validator: fast' has no fast@codex-cli in [MODEL_TIERS], read as session`.
- `claude-code defaults light and validator to fast`: empty `SPINE.md` → `models.light == session`, `models.validator == session`, `model_tiers.light.source == unset`, stderr empty (a default is nobody's entry).
- `explicit session in MODEL_TIERS is session, silently` (Review Focus 2).
- `MODEL_TIERS in a Task.md is not read`: tiers only in `$t/Task.md` → `models.validator == session` under the default claude-code run.
- `a run-level fast resolves through the project's tiers` (Review Focus 3): `--set models.validator=fast` → final from tiers, `sources["models.validator"] == run`, unset stderr label starts `--set models`.
- `tier keys are case-insensitive, malformed ones are skipped` (Review Focus 1): `FAST@Codex-CLI: GPT-X` → `GPT-X` under codex-cli; `fast @ codex-cli: x` → stderr `'fast @ codex-cli: x' not recognized, skipped`.
- `bad MODEL_TIERS entries are skipped by name`: each of `slow@codex-cli: x`, `fast@nope: x`, `fast@claude-code: gpt-6-mini`, `fast@codex-cli: opus` → stderr `[MODEL_TIERS]: '<entry>' not recognized, skipped`.
- `the later of two lines for a tier wins` (Review Focus 5).

- [ ] **Step 2: Run them, see them fail**

Run: `bats tests/foundation/lib/model-and-effort.test.bats tests/foundation/lib/runtimes.test.bats tests/foundation/lib/settings-resolver.test.bats`
Expected: the new and rewritten tests FAIL (`model_tiers` KeyError, `fast` not recognized, `sonnet` where `session` is expected); the rest pass.

- [ ] **Step 3: Implement**

- `runtimes/claude-code.json`: `"model_defaults": {"light": "fast", "validator": "fast"}`.
- `load_runtime`: a default value passes when it is in `models` (or a token under `any`) or in `TIERS`.
- `[MODELS]` loop: a raw value in `TIERS` is accepted as `fast` before `map_value`; remember, per decided key, the source label and the entry as written.
- After the `models` map resolves: each key at `fast` → `MODEL_TIERS[('fast', RUNTIME)]` if present (`source: project`), else `session` (`source: unset`) plus the stderr line when a source decided the key.
- `[MODEL_TIERS]` reader: entries from `config_entries('MODEL_TIERS')`; validate per the spec's four rules using `runtime_vocab`; a bad entry → `warn('%s [MODEL_TIERS]' % CFG, entry)`.
- `json`: add `model_tiers=MODEL_TIER_OF`.

- [ ] **Step 4: Run, see them pass**

Run: `bats tests/foundation/lib/model-and-effort.test.bats tests/foundation/lib/runtimes.test.bats tests/foundation/lib/settings-resolver.test.bats tests/foundation/lib/opening-block-hook.test.bats`
Expected: all PASS.

- [ ] **Step 5: Commit**

```bash
git add runtimes/claude-code.json scripts/resolve-settings.sh tests/foundation/lib/model-and-effort.test.bats tests/foundation/lib/runtimes.test.bats tests/foundation/lib/settings-resolver.test.bats
git commit -m "feat(settings): resolve the fast model tier through [MODEL_TIERS]"
```

### Task 2: Show the tier in the settings column

**Files:**
- Modify: `scripts/resolve-settings.sh` (`show_rows` ~l.705)
- Test: `tests/foundation/lib/model-and-effort.test.bats`

**Interfaces:**
- Consumes: `MODEL_TIER_OF` from Task 1; `defaults['models']` keeps the raw defaults (`fast`), `resolved['models']` the finals.

- [ ] **Step 1: Write the failing tests**

- `show names a tier and what it became`: tiers set, `[MODELS] = [reviewer: fast]` → `show` output contains `reviewer: fast → sonnet`.
- `show always names a tier with no line for the runtime`: empty `SPINE.md`, `show --runtime claude-code` → contains `light: fast → session, no fast@claude-code` and `validator: fast → session, no fast@claude-code`.
- `show leaves a set default tier out of the diff`: template-like config (`light: fast, validator: fast`, `fast@claude-code: sonnet`) → `show` has no `[MODELS]` row; `show --all` has `validator: fast → sonnet`.
- Existing "show keeps the 2.28.0 key order" still passes unchanged.

- [ ] **Step 2: Run, see them fail**

Run: `bats tests/foundation/lib/model-and-effort.test.bats`
Expected: the three new tests FAIL.

- [ ] **Step 3: Implement**

In `show_rows`, for `models`: a key is chosen when the run set it, when its raw (pre-tier) value differs from `defaults['models'][k]` and a source decided it, or when `MODEL_TIER_OF[k]['source'] == 'unset'`. Its text uses the Global Constraints spelling. The `open` block reuses `show_rows`, so it follows.

- [ ] **Step 4: Run, see them pass**

Run: `bats tests/foundation/lib/model-and-effort.test.bats tests/foundation/lib/settings-resolver.test.bats tests/foundation/lib/opening-block-hook.test.bats`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add scripts/resolve-settings.sh tests/foundation/lib/model-and-effort.test.bats
git commit -m "feat(settings): the settings column names a model tier and its result"
```

### Task 3: Template and reference docs

**Files:**
- Modify: `templates/spine-md/en.md:36`
- Modify: `docs/configuration.md` (`### [MODELS]` ~l.349; new `### [MODEL_TIERS]` right after it)
- Modify: `conventions/task-settings.md` (Runtime table l.59–62; field table row `models` l.164; new `model_tiers` row)
- Modify: `skills/orchestrator/SKILL.md:595` (the `models` paragraph: defaults are `fast` for `light` and `validator`, resolved through `[MODEL_TIERS]`, and the map carries final models). The example `models=` line at l.505 stays as is: it is what the template resolves to in Claude Code.
- Modify: `skills/task-new/SKILL.md:129` (`fast` is a value a task may write)
- Test: `tests/foundation/lib/model-and-effort.test.bats`, `tests/foundation/lib/orchestrator-contract.test.bats`

- [ ] **Step 1: Write the failing tests**

- Change "the config template ships every Models key at its default" to expect `light: fast` and `validator: fast`, and assert the template has the line `[MODEL_TIERS] = [fast@claude-code: sonnet]` before `[MODELS]`.
- New `the doc explains MODEL_TIERS and a shared config across runtimes`: `docs/configuration.md` has `### [MODEL_TIERS]`; its section contains `fast@claude-code`, `fast@codex-cli`, `` `session` ``, `project config only`; the `[MODELS]` section contains `` `fast` `` and a table row starting `| \`sonnet\` |`.
- New `task-settings names model_tiers and the tier defaults`: `conventions/task-settings.md` contains `` `model_tiers` `` and `` `fast` for `light` and `validator` ``.
- In `orchestrator-contract.test.bats` "models and effort are resolved by the script…" (~l.366): replace the token `` `sonnet` for `light` and `validator`, `session` for every other role `` with `` `fast` for `light` and `validator`, `session` for every other role `` and add the token `[MODEL_TIERS]`.
- New `the template resolves to sonnet in Claude Code and session in Codex`: copy `$TPL` to `SPINE.md`; claude-code → `models.validator == sonnet`; codex-cli → `session` with the "has no fast@codex-cli" line on stderr.

- [ ] **Step 2: Run, see them fail**

Run: `bats tests/foundation/lib/model-and-effort.test.bats tests/foundation/lib/config-format.test.bats tests/foundation/lib/orchestrator-contract.test.bats`
Expected: the new and changed tests FAIL.

- [ ] **Step 3: Write the template line and the docs**

`docs/configuration.md` `[MODELS]`: Values add `fast`; Default becomes "the runtime's `model_defaults` (Claude Code: `fast` for `light` and `validator`)"; add the table:

| `[MODELS]` value | Claude Code | Codex CLI |
|---|---|---|
| `session` | session's model | session's model |
| `fast`, with `fast@<runtime>` | that line's model | that line's model |
| `fast`, no line | session's model | session's model |
| `sonnet` (any Claude name) | Sonnet | session's model |
| `gpt-…` (a Codex name) | skipped, next source down | as written |

State the behavior change in one sentence: a project with neither `[MODELS]` entries for `light`/`validator` nor `[MODEL_TIERS]` now runs them on the session's model.
`### [MODEL_TIERS]`: Values, Default (none), "project config only — no task override", the four rejection rules, example lines.

- [ ] **Step 4: Run, see them pass**

Run: `bats tests/foundation/lib/model-and-effort.test.bats tests/foundation/lib/config-format.test.bats tests/foundation/lib/orchestrator-contract.test.bats tests/foundation/lib/settings-resolver.test.bats`
Expected: PASS ("the shipped config template resolves to the defaults and reports nothing" included).

- [ ] **Step 5: Commit**

```bash
git add templates/spine-md/en.md docs/configuration.md conventions/task-settings.md skills/orchestrator/SKILL.md skills/task-new/SKILL.md tests/foundation/lib/model-and-effort.test.bats tests/foundation/lib/orchestrator-contract.test.bats
git commit -m "docs(settings): the fast tier in the template and the reference"
```

### Task 4: Orchestrator messages and the Codex map

**Files:**
- Modify: `skills/orchestrator/SKILL.md` (table ~l.750–756)
- Modify: `skills/orchestrator/locales/en.md`, `skills/orchestrator/locales/ru.md` (`warn_tuning_unrecognised`, `warn_model_read_as_session`, new `warn_model_tier_unset`)
- Modify: `runtimes/codex-cli.md` (l.9–12 models paragraph; `## What the user sees` stderr rule)
- Test: `tests/foundation/lib/codex-runtime-text.test.bats`

**Interfaces:**
- Produces: locale key `warn_model_tier_unset` with placeholders `{source}`, `{entry}`, `{runtime}`; `warn_model_read_as_session` gains `{runtime}`.

- [ ] **Step 1: Write the failing tests**

- `the orchestrator announces a fast tier with no line`: the table has a row whose first cell contains `has no fast@<runtime> in [MODEL_TIERS], read as session` and which names `warn_model_tier_unset` and `say nothing at task launch`; both locales have `## warn_model_tier_unset`, and each body contains `{source}`, `{entry}`, `{runtime}` and `` `fast@{runtime}: `` .
- `the Claude-model text says what to do`: both locales' `warn_model_read_as_session` body contains `` `fast` `` and `[MODEL_TIERS]`.
- `the tuning warning lists fast`: both locales' `warn_tuning_unrecognised` body contains `` `fast` ``.
- `the Codex map keeps resolver stderr from the user`: `## What the user sees` in `runtimes/codex-cli.md` contains `resolver's stderr`; the top paragraph contains `` `fast` `` and `[MODEL_TIERS]`.
- Locale parity: `diff <(grep '^## ' en.md | sort) <(grep '^## ' ru.md | sort)` empty for the orchestrator.

- [ ] **Step 2: Run, see them fail**

Run: `bats tests/foundation/lib/codex-runtime-text.test.bats`
Expected: the new tests FAIL.

- [ ] **Step 3: Write the texts**

Locale bodies carry the spec's section 2 meaning (source, reason, result, action); the ru text is a translation in the existing ru locale's register, not a transliteration. The table row's `{source}`/`{entry}` extraction is the existing rule; `{runtime}` is the `--runtime` the orchestrator passed.

- [ ] **Step 4: Run, see them pass; run the locale lints**

Run: `bats tests/foundation/lib/codex-runtime-text.test.bats && scripts/lint-locales.sh && scripts/lint-i18n.sh`
Expected: PASS, lints exit 0.

- [ ] **Step 5: Commit**

```bash
git add skills/orchestrator runtimes/codex-cli.md tests/foundation/lib/codex-runtime-text.test.bats
git commit -m "feat(orchestrator): say what a model tier or a Claude model became, and how to change it"
```

### Task 5: `scripts/model-tiers.sh`

**Files:**
- Create: `scripts/model-tiers.sh`
- Test: Create `tests/foundation/lib/model-tiers.test.bats`

**Interfaces:**
- Produces:
  - `model-tiers.sh check <config> --runtime <id>` → exit 0; stdout lines, in this order, each only when true:
    - `sonnet <key>[,<key>…]` — `[MODELS]` keys whose value is `sonnet`, in file order;
    - `tier-missing fast@<id>` — `[MODEL_TIERS]` has no `fast@<id>` line.
  - `model-tiers.sh apply <config> [--migrate] [--set fast@<id>=<model>]` → exit 0, edits in place:
    - `--migrate`: every `[MODELS]` line's `: sonnet` entries become `: fast`; ensures `fast@claude-code: sonnet`.
    - `--set`: adds the entry when that `fast@<id>` is absent; never overwrites an existing one.
    - A missing `[MODEL_TIERS]` line is inserted directly above the first `[MODELS]` line; entries are appended inside the existing brackets otherwise.
  - Usage errors → exit 2 with a `usage:` line.

- [ ] **Step 1: Write the failing tests**

`model-tiers.test.bats`, each on a temp copy:
- `check names sonnet keys and a missing tier line`: Courier line `[MODELS] = [light: sonnet, architect: session, validator: sonnet]` → stdout exactly `sonnet light,validator` then `tier-missing fast@codex-cli`.
- `check on the new template prints nothing for claude-code`.
- `apply --migrate rewrites sonnet and adds the claude-code line`: result has `light: fast`, `validator: fast`, `[MODEL_TIERS] = [fast@claude-code: sonnet]` on the line above `[MODELS]`; `architect: session` and `tester: opus` unchanged.
- `apply --set adds a Codex line and never overwrites one`: second `--set fast@codex-cli=other` leaves the first value.
- `apply is idempotent and covers folded MODELS lines` (Review Focus 4): two `[MODELS]` lines with `sonnet`; `apply --migrate` twice → file identical after the first and second run, no `sonnet` left in `[MODELS]`.
- `the resolver reads what apply wrote`: after `apply --migrate --set fast@codex-cli=gpt-6-mini`, `resolve-settings.sh json --runtime codex-cli` gives `models.validator == gpt-6-mini`, claude-code gives `sonnet`.
- `usage errors exit 2`.

- [ ] **Step 2: Run, see them fail**

Run: `bats tests/foundation/lib/model-tiers.test.bats`
Expected: FAIL, `scripts/model-tiers.sh: No such file`.

- [ ] **Step 3: Implement**

Same layout as `scripts/codex-permissions.sh`: `set -euo pipefail`, usage comment block, the work in an embedded `python3 -` heredoc. Lines are matched as `resolve-settings.sh`'s `config_fields` does (`^\[([A-Z_]+)\]\s*=\s*\[([^\]]*)\]`, column 0), so a commented-out line is never edited. Write via a temp file in the same folder and `os.replace`.

- [ ] **Step 4: Run, see them pass**

Run: `bats tests/foundation/lib/model-tiers.test.bats`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add scripts/model-tiers.sh tests/foundation/lib/model-tiers.test.bats
git commit -m "feat(setup): model-tiers.sh checks and writes a project's model tiers"
```

### Task 6: `setup` offers the tier questions

**Files:**
- Modify: `skills/setup/SKILL.md` (new step `6e`; the Codex paragraph l.417–422 removed; step 7 names 6e's line)
- Modify: `skills/setup/locales/en.md`, `skills/setup/locales/ru.md` (remove `report_models_read_as_session`; add `auq_models_migrate`, `auq_models_migrate_options`, `auq_models_codex_tier`, `auq_models_codex_tier_options`, `report_models_migrated`)
- Test: `tests/foundation/lib/codex-runtime-text.test.bats` (replace the milestone-6 setup test), new tests in `tests/foundation/lib/model-tiers.test.bats`

**Interfaces:**
- Consumes: `model-tiers.sh check|apply` from Task 5.
- Produces: step `6e` text; locale keys above. `auq_models_migrate` placeholders `{keys}`; `auq_models_codex_tier` none; `report_models_migrated` placeholders `{keys}`, `{tiers}`.

- [ ] **Step 1: Write the failing tests**

- Replace "a Claude model from the project config is named once by setup…" with `setup offers the model tier questions instead of a report`: `skills/setup/SKILL.md` contains `6e.`, `model-tiers.sh check`, `model-tiers.sh apply`, `auq_models_migrate`, `auq_models_codex_tier`; no locale has `## report_models_read_as_session`; both have the five new keys; the orchestrator row from Task 4 still says `say nothing at task launch`.
- `setup's 6e runs in every state but F`: the step text contains `state F → skip`.
- `the Codex tier question offers no model list`: `auq_models_codex_tier_options` in en has exactly two option lines.

- [ ] **Step 2: Run, see them fail**

Run: `bats tests/foundation/lib/codex-runtime-text.test.bats tests/foundation/lib/model-tiers.test.bats`
Expected: the new tests FAIL.

- [ ] **Step 3: Write step 6e and the locale keys**

Step 6e, after 6d, every state but F (`↓ state F → skip; that state asks nothing (step 4(e)).`), the config being the file this run wrote or found:
1. `model-tiers.sh check <config> --runtime <runtime>`.
2. A `sonnet …` line → AUQ `auq_models_migrate` with `{keys}`. Yes → `apply --migrate`.
3. In Codex CLI, a `tier-missing fast@codex-cli` line (after step 2) and either a new config (states A, B) or step 2 answered Yes → AUQ `auq_models_codex_tier`. A model given → `apply --set fast@codex-cli=<model>`. "Keep the session's model" → nothing.
4. Anything applied → `report_models_migrated` in step 7, on a line of its own after 6d's lines.

Remove the "In Codex CLI, whatever the menu's answer, also read the project config's `[MODELS]`…" paragraph. In the ru locale, the same keys with a faithful translation.

- [ ] **Step 4: Run, see them pass; run the lints**

Run: `bats tests/foundation/lib/codex-runtime-text.test.bats tests/foundation/lib/model-tiers.test.bats && scripts/lint-locales.sh && scripts/lint-i18n.sh`
Expected: PASS, lints exit 0.

- [ ] **Step 5: Commit**

```bash
git add skills/setup tests/foundation/lib/codex-runtime-text.test.bats tests/foundation/lib/model-tiers.test.bats
git commit -m "feat(setup): offer the fast tier for sonnet entries and a model for Codex"
```

### Task 7: Courier regression and the full suite

**Files:**
- Test: `tests/foundation/lib/model-and-effort.test.bats`

- [ ] **Step 1: Add the regression test**

`the field config gives the documented result in both runtimes`: config `[MODELS] = [light: sonnet, architect: session, developer: session, tester: session, reviewer: session, refactorer: session, validator: sonnet, security: session, diagnostics: session]`.
- claude-code: `light` and `validator` `sonnet`, stderr empty.
- codex-cli: both `session`; stderr has the two existing `is not a codex-cli model, read as session` lines and no `has no fast@` line.

- [ ] **Step 2: Run it**

Run: `bats tests/foundation/lib/model-and-effort.test.bats`
Expected: PASS (behavior already in place; this pins it).

- [ ] **Step 3: Run the whole suite and every lint**

Run: `scripts/test-foundation.sh`
Expected: exit 0, no failures. A failure outside the files this plan touched is reported, not patched around.

- [ ] **Step 4: Commit**

```bash
git add tests/foundation/lib/model-and-effort.test.bats
git commit -m "test(settings): pin the field model config in both runtimes"
```
