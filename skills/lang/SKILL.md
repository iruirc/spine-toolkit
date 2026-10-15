---
name: lang
description: |
  Change the project language for spine-toolkit user-facing prompts. Updates `[LANG]` in the project config (SPINE.md, or CLAUDE-spine-toolkit.md where the project has not migrated). Currently supported: en, ru.
  Use when (en): "switch language to en", "switch language to ru", "change toolkit language", "/lang"
  Use when (ru): "переключи язык на en", "смени язык на русский", "поменяй язык toolkit", "/lang"
---

# Lang

Updates the `[LANG]` field of the project config — `SPINE.md`, or `CLAUDE-spine-toolkit.md` where the project has not migrated (core's `conventions/task-settings.md` → Project config). Pure configuration skill: no project state mutated besides this one field.

## Language Resolution

Before producing any user-facing string:

1. Read the project config from the project root (core's `conventions/task-settings.md` → Project config).
2. Find the `[LANG]` field.
3. Take the field's value, lowercase and trim it. That is `<lang>`.
4. If `<lang>` is `en` or `ru`, use it. Otherwise default to `en`.
5. Read this skill's `locales/<lang>.md`. Look up keys by H2 header.
6. If a key is missing, fall back to the same key in `locales/en.md`. If still missing, that's a bug — fail loudly with key name.

Caching: resolve `<lang>` once per skill invocation; do not re-read the project config per string.

## Algorithm

```
1. Locate the project config in the current project root: SPINE.md, else CLAUDE-spine-toolkit.md — the first that exists, never both.
   ↓ If not found → print error using key `error_no_toolkit_file`. Stop.

2. Parse $ARGUMENTS:
   ↓ If empty → print current value (read the `[LANG]` field) and supported list using keys
       `report_current_language` + `report_supported_languages`. Stop.
   ↓ If value not in {en, ru} → print error using key `error_unsupported_language`. Stop.

3. Update that file:
   - Locate the `[LANG]` field (regex: a line matching `^\[LANG\]\s*=\s*\[[^\]]*\]`).
   - Replace the bracketed value in place, keeping the trailing comment.
   - If the field is missing but `## Project settings` is present → insert `[LANG] = [<value>]` right after the heading.
   - If `## Project settings` itself is missing → the config predates 2.0. Print error using key
     `error_config_predates_2_0`. Stop. Do not insert a new heading.

4. Print success using key `report_language_changed` with placeholders {old}, {new}.
```

## Edge cases

- Neither SPINE.md nor CLAUDE-spine-toolkit.md present → key `error_no_toolkit_file`.
- Argument missing → print current state (not an error).
- Argument unsupported → key `error_unsupported_language`, list supported.
- Argument equals current value → still OK; print success message anyway.

## What this skill does NOT do

- Does NOT translate any existing files.
- Does NOT validate that locales for the chosen language exist for every skill (that's a contributor concern, not user concern).
- Does NOT touch any other section of the project config, and never renames it (that is `setup`).
