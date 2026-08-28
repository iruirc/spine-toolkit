---
name: setup
description: |
  Configures spine-toolkit in an existing project: picks the platform plugin that serves it, creates CLAUDE-spine-toolkit.md from the template, inserts an @./ import line into CLAUDE.md, creates the Tasks/ and Docs/ structures, and hands the platform half its own blocks. Migrates projects on the legacy single-file CLAUDE.md layout and on the pre-split config name.
  Use when (en): "set up spine-toolkit", "configure spine-toolkit", "install toolkit in project", "add spine-toolkit to project", "init toolkit here", "/setup"
  Use when (ru): "настрой spine-toolkit", "подключи spine-toolkit", "установи toolkit в проект", "добавь spine-toolkit к проекту", "инициализируй toolkit здесь", "/setup"
---

# Setup

Bootstraps spine-toolkit in an **already existing** project. Two-file layout:

- `CLAUDE-spine-toolkit.md` — toolkit-owned configuration; its sections are the ones `templates/claude-toolkit-md/en.md` carries. Created and updated by this skill.
- `CLAUDE.md` — user-owned project instructions. Touched once to insert the `@./CLAUDE-spine-toolkit.md` line; otherwise unchanged.

This skill owns the config **format** and every block that is core's: `## Language`, `## Mode`, `## Progress`, `## Platform`, `## Agents`, and the file-level scaffolding. It owns none of the stack: `## Stack` and `## Modules` are filled by the platform half (step 5), because which axes exist and which values they take is the platform manifest's `## Axes`, not core's.

The skill creates no source files, modifies no code, and starts no workflow. Generating a project from scratch belongs to the platform plugin's `init` agent.

## Input

Normally invoked by the user with nothing. It also accepts answers a caller has already collected —
a platform's `init` agent, which asks the same stack questions before scaffolding a project, is the
case this exists for:

```
lang     = en | ru                    # skips q0
mode     = manual | auto              # skips qM
progress = quiet | normal | live      # skips qP
platform = plugin name                # skips Platform Discovery
stack    = {axis: value, …}           # forwarded to the platform half in step 5
```

Every field is optional; an absent one means the question is asked as usual, so an empty input is
the ordinary `/setup` run. `stack` values must be spelled as the platform's `## Axes` catalog spells
them — the platform half matches them against that catalog and asks for whatever it cannot place, so
a value in the caller's own vocabulary costs one re-asked question, never a wrong config.

## Language Resolution

Special case for `setup`: `CLAUDE-spine-toolkit.md` does not yet exist on first install (we are creating it). The skill therefore asks for the language as the very first question (q0) using keys `auq_lang_label` and `auq_lang_options`. Until that answer arrives, the q0 prompt is shown bilingually (English label / Russian label). From q0 onward, `<lang>` is the chosen value (`en` or `ru`), and every subsequent AUQ / error / report uses `locales/<lang>.md`. If q0 is skipped (text fallback, harness limitation), default to `en`.

The full resolution procedure used elsewhere — read `CLAUDE-spine-toolkit.md → ## Language` — applies after `setup` has finished.

## Agent Tooling

Use `conventions/agent-tooling.md` for host-neutral interaction and file-access
terms.

In this skill, `AUQ` means the structured question mechanism. If the active host
cannot provide a structured question tool, ask numbered options in a regular
message and parse the reply. Locale keys with the `auq_` prefix remain the
canonical prompt/option keys.

## Platform Discovery

A project names its platform outright in `## Platform`; discovery happens **once, here**, because the config that would answer the question is the file this skill is creating.

A platform plugin is one that exposes a skill named `manifest` — `<plugin>:manifest`, per `conventions/platform-contract.md`. Enumerate them from the skills available in this session; that listing is the host's own answer to "what is installed" and needs no filesystem walk. Nothing else identifies a platform: not the plugin's name, not the files in the repository.

```
platforms := installed skills named `manifest`, as their `<plugin>` prefixes
  0  → error using key `error_no_platform_installed`. Stop, no disk changes.
  1  → AUQ using key `auq_platform_confirm`, placeholder `{plugin}`
       (options: `auq_platform_confirm_options` — Yes / Cancel)
  ≥2 → AUQ using key `platform_choice_question`, options := the plugin names
```

Confirming rather than assuming on the single-platform path is deliberate: the name is written into the config and every later run resolves roles through it, so a wrong one is silent until the first dispatch.

## State Detection

The skill's behavior is determined by the project state, computed from four checks:

1. Does `CLAUDE.md` exist in the project root?
2. Does `CLAUDE-spine-toolkit.md` exist in the project root?
3. Does a pre-split `CLAUDE-swift-toolkit.md` exist in the project root?
4. Does `CLAUDE.md` contain any of `## Language`, `## Stack`, or `## Mode` headings? (Indicates the legacy single-file format.)

| State | `CLAUDE.md` | `CLAUDE-spine-toolkit.md` | Pre-split config | Toolkit sections in `CLAUDE.md`? | Action branch |
|---|---|---|---|---|---|
| **A · new_install** | absent | absent | absent | — | Ask q0, qM, qP. Create both files. |
| **B · existing_md** | present | absent | absent | no | Ask q0, qM, qP. Backup CLAUDE.md. Insert `@import` line. Create `CLAUDE-spine-toolkit.md`. |
| **C · already_configured** | present | present | — | no | AUQ `auq_reconfigure_toolkit` on `CLAUDE-spine-toolkit.md` only. Self-heal `CLAUDE.md` if `@import` is missing. |
| **D · old_format** | present | absent | absent | yes | AUQ `auq_migrate_old_format`. Run the migration algorithm (see below). |
| **E · renamed_config** | present | absent | present | — | AUQ `auq_migrate_config_name`. Rename the file, reconcile blocks, rewrite the `@import` line. |

### Edge sub-states

- `CLAUDE.md` has the `@./CLAUDE-spine-toolkit.md` import line, but `CLAUDE-spine-toolkit.md` is absent: route to **state A** (create the toolkit file). Do not modify `CLAUDE.md`.
- `CLAUDE-spine-toolkit.md` exists but `CLAUDE.md` is absent: create a stub `CLAUDE.md` from `templates/claude-md-stub/<lang>.md`. Toolkit file untouched.
- Both `CLAUDE-spine-toolkit.md` and a pre-split `CLAUDE-swift-toolkit.md` exist: state **C**. The new name wins; report the stale file rather than touching it, so nothing the user may still be reading is deleted behind their back.

## Algorithm

```
0. Ask the language (q0):
   AUQ using key `auq_lang_label` with options from `auq_lang_options` (`en` / `ru`).
   Store answer as <lang>; subsequent prompts/reports use locales/<lang>.md.
   Q0 is shown bilingually. If skipped, default <lang> = `en`.
   ↓ `lang` in the input → use it, ask nothing.

1. Resolve the platform (see Platform Discovery).
   ↓ `platform` in the input → use it, skip discovery: the caller that named one is the
     platform itself.
   ↓ none installed → render `error_no_platform_installed`. Stop.

2. Compute state (see State Detection table).

3. Locate templates:
   a. `templates/claude-toolkit-md/en.md` — toolkit file template (English-only; the
      file body is always EN regardless of `<lang>`).
   b. `templates/claude-md-stub/<lang>.md` — minimal CLAUDE.md stub (localized).
   Lookup paths (try in order):
     - `<core root>/templates/...` — both templates are core's (see
       `conventions/agent-tooling.md` → Plugin Roots And Templates)
     - host-installed plugin/cache template paths
     - Claude Code compatibility paths:
       `~/.claude/plugins/cache/spine-toolkit/spine-toolkit/<latest-version>/templates/...`
       or the marketplace checkout under `~/.claude/plugins/marketplaces/spine-toolkit/`
   ↓ if neither path is available → render `error_template_not_found`. Stop.

4. Branch by state:

   STATE A (new_install):
     a. Ask qM (mode) using `auq_mode_label` and qP (progress) using `auq_progress_label` —
        each only if the input did not already answer it (same rule in states B and C).
     b. Render `templates/claude-toolkit-md/en.md` with the Placeholder Replacements below.
        Write to <project>/CLAUDE-spine-toolkit.md.
     c. **If CLAUDE.md does NOT exist**: render `templates/claude-md-stub/<lang>.md` with
        `{project_name}` derived from the project directory name. Write to <project>/CLAUDE.md.
        **If CLAUDE.md DOES exist** (the broken-state edge sub-state): SKIP this sub-step.
        Do not overwrite the user's CLAUDE.md.

   STATE B (existing_md):
     a. Ask qM, qP.
     b. Render the toolkit template. Write to <project>/CLAUDE-spine-toolkit.md.
     c. Backup CLAUDE.md → CLAUDE.md.bak (collision suffix: .bak.YYYYMMDD-HHMMSS).
     d. Insert `@./CLAUDE-spine-toolkit.md` as a new line:
        - if the first non-empty line is an H1 (`# ...`), insert immediately after it
          (with one blank line before and after).
        - otherwise, insert at the very top of the file (with one blank line after).
        - if the line already exists anywhere in the file → skip insertion (idempotent).

   STATE C (already_configured):
     a. AUQ using key `auq_reconfigure_toolkit` with options `auq_reconfigure_toolkit_options`
        (Overwrite / Backup-and-overwrite / Cancel).
        - Cancel → stop, no disk changes.
        - Backup-and-overwrite → rename CLAUDE-spine-toolkit.md → CLAUDE-spine-toolkit.md.bak
          (timestamp on collision). Continue.
        - Overwrite → continue.
     b. Ask qM, qP.
     c. Render the toolkit template. Write to CLAUDE-spine-toolkit.md (overwrite).
     d. Self-heal CLAUDE.md: if the `@./CLAUDE-spine-toolkit.md` line is missing, run the
        insertion logic from State B step (d), with backup.

   STATE D (old_format):
     a. Run the migration parser on CLAUDE.md. Compute moved/kept/defaulted/warning section sets.
     b. Show a summary preview (sections to move, kept, defaulted, warnings, backup path).
     c. AUQ `auq_migrate_old_format` with options `auq_migrate_old_format_options`
        (Migrate-and-backup / Cancel).
        - Cancel → stop, no disk changes.
        - Migrate-and-backup → continue.
     d. Backup CLAUDE.md → CLAUDE.md.bak (timestamp on collision).
     e. Build the new CLAUDE-spine-toolkit.md (toolkit_sections in canonical order; missing
        sections filled from template defaults) — EXCEPT `## Platform`, which is written with
        the platform resolved in step 1 whether or not the source has a section by that name.
        Neither branch of that carries a plugin name: a legacy config normally lacks the block
        entirely, and one that has it means something else, because the pre-split stack axis
        was itself called `Platform` and held a deployment target. Filling from the template
        default, or carrying the source's section over, writes a config that passes every
        existence check and fails at the orchestrator's step 5.7.
     f. Hand `## Stack` to the platform half (step 5) — a migrated `## Stack` was written
        against an older axis catalog, exactly as in state E.
     g. Build the new CLAUDE.md (preamble [stub or preserved] + @import line + user_sections
        in original order).
     h. Atomic write: write to *.new temp files, then rename.

   STATE E (renamed_config):
     a. Show a preview: the file to rename, the blocks that will be added, and the backup path.
     b. AUQ `auq_migrate_config_name` with options `auq_migrate_config_name_options`
        (Migrate-and-backup / Cancel).
        - Cancel → stop, no disk changes.
        - Migrate-and-backup → continue.
     c. Backup CLAUDE-swift-toolkit.md → CLAUDE-swift-toolkit.md.bak (timestamp on collision).
     d. Parse it with the same parser as state D. Keep every section whose heading matches the
        canonical list; fill missing canonical sections from the template default.
     e. `## Platform` is written with the platform resolved in step 1 whether or not the source
        has a section by that name — a pre-split config normally lacks the block, and one that
        has it means something else, because the pre-split stack axis was itself called
        `Platform` and held a deployment target. Everything else the file already answers is
        kept, not re-asked.
     f. Hand `## Stack` to the platform half (step 5) for reconciliation against its current
        `## Axes` — a platform that has renamed an axis since the config was written is the case
        this exists for.
     g. Atomic write to CLAUDE-spine-toolkit.md; remove the old file only after the write
        succeeds. Rewrite the `@./CLAUDE-swift-toolkit.md` line in CLAUDE.md to the new name
        (backup first); if the line is absent, insert it per State B step (d).

5. Hand the platform its own blocks:
   The `setup` row of the platform manifest's ## Entrypoints names the skill that owns them.
   Invoke `<platform>:<that skill>` with {lang, state, config_path, stack} — `stack` being the
   input's, empty when there was none. Forwarding it is what keeps a caller that already asked
   the stack questions from having them asked again; core never reads a value in it. It asks its
   own stack questions for the axes still without a value, writes ## Stack and ## Modules into
   the config, and returns
   {stack_lines, notes} — the axis lines, and any already-rendered notes about what it
   reconciled in a migrated ## Stack.
   ↓ the row is `—`, or absent → leave ## Stack and ## Modules as the template's placeholders and
     report `stack_status_deferred`; the orchestrator's per-axis AUQ fills them later, one task
     at a time. A platform without a setup skill is a supported shape, not an error.

6. Optional Tasks/ structure (orthogonal to state):
   If Tasks/ does not exist:
     AUQ using key `auq_create_tasks_structure`.
     ↓ Yes → mkdir -p Tasks/{TODO,ACTIVE,DONE,BACKLOG,RESEARCH,CHECK,UNABLE_FIX}; .gitkeep in
       each; tasks_status = `tasks_status_created`.
     ↓ No → skip; tasks_status = `tasks_status_skipped`.
   If Tasks/ exists (folder, symlink, or file) → tasks_status = `tasks_status_already_existed`
   (existing layouts, including manual symlinks, are NEVER overwritten).

6b. Optional Docs/ structure (orthogonal to state):
   If Docs/ does not exist:
     AUQ using key `auq_create_docs_structure`.
     ↓ Yes → mkdir -p Docs/{architecture,api,guides,notes}; .gitkeep in each;
       docs_status = `docs_status_created`.
     ↓ No → skip; docs_status = `docs_status_skipped`.
   If Docs/ exists (folder, symlink, or file) → docs_status = `docs_status_already_existed`.

7. Render the report:
   - States A/B/C/E → key `setup_done` with placeholders {platform}, {stack}, {mode},
     {progress}, {lang}, {tasks_status}, {docs_status}, {notes}.
   - State D → key `report_migration_success` with placeholders {moved_sections},
     {kept_sections}, {filled_default_sections}, {warnings}, {backup_path}, {notes}.
   {notes} is the platform half's returned notes, one per line, already rendered in <lang>;
   empty when it reconciled nothing. It is the only place those lines surface, so a rewrite
   the platform performed silently would be a rewrite the user never sees.
```

One report, rendered here: the platform half is a delegate, not a second entry point, so its
returned axis lines fill `{stack}` rather than printing a report of their own.

## Migration Algorithm (states D and E)

### Parser

Splits the source file into a sequence of `[(heading, body), ...]` plus a `preamble` string.

Rules:
- Section boundary = a line that starts with the literal `## ` (h2). H1, h3+, indented `##` are NOT boundaries.
- A `## ` line inside a fenced code block (` ``` `) is NOT a boundary. The parser tracks fenced state.
- The `preamble` is everything before the first valid `## ` line (may be empty).
- A section body includes all lines until the next `## ` boundary (exclusive) or EOF.

### Section classification

Canonical toolkit headings = the `## ` headings of `templates/claude-toolkit-md/en.md`, read from that file in the order it has them. Match case-insensitively and **exactly**, not by prefix.

Read the list rather than restating it here: a second copy falls behind the day the toolkit adds a section, and a section missing from the copy is silently never migrated into an existing project.

- `toolkit_sections` = sections whose heading matches the canonical list.
- `user_sections` = everything else, in original order.
- `unknown_warnings` = headings that look toolkit-like but don't match exactly (e.g. `Stacks`, `Mode (custom)`). Kept in `user_sections`. Surfaced in the report.

Exact match only — no prefix-matching. `## Stack Cookbook` is NOT classified as `Stack`.

### Preamble handling

- **Toolkit preamble detected** if the H1 (first non-empty `# ...` line) matches any of these canonical strings (exact match, case-sensitive):
  - `# CLAUDE.md — Swift Toolkit` (legacy single-file template — both EN and RU legacy templates used the same H1 string; only the body was localized)
  - `# CLAUDE-swift-toolkit.md — Swift Toolkit Configuration` (pre-split two-file template)
  - `# CLAUDE-spine-toolkit.md — Toolkit Configuration` (current)
  → Discard the preamble, replace it with the rendered `templates/claude-md-stub/<lang>.md`.
- **Otherwise**: preserve the preamble as-is. Insert `@./CLAUDE-spine-toolkit.md` after the H1 (or at the very top if no H1) before the first user section.

### Output assembly

`CLAUDE-spine-toolkit.md`:
```
<H1 + intro from templates/claude-toolkit-md/en.md>

<toolkit_sections in canonical order>
```

For canonical sections missing from the source: fill from the template default (e.g. `## Mode\n\nmanual`). Track in `filled_default_sections` for the report.

`## Platform` is the one exception, in **both** migrating states, and it is unconditional: it is
written from the platform resolved in step 1 and never appears in `filled_default_sections`, whether
the source lacks the section (the normal case — the block did not exist before the split) or carries
one (the pre-split stack axis was also called `Platform`, so such a section holds a version string,
not a plugin name). Its template default is a placeholder, not a value, so neither source can
supply it. A config carrying the placeholder is worse than one carrying nothing:
Routing check 4 sees a config, so the run proceeds to step 5.7 and fails there naming a plugin that
does not exist.

`CLAUDE.md` (state D only — state E leaves user sections alone):
```
<preamble: stub or preserved>

@./CLAUDE-spine-toolkit.md

<user_sections in original order>
```

Empty `user_sections` → the file ends at the `@import` line (with a trailing newline).

### Safeguards

1. **Backup always**: the source file → `<name>.bak` (or `.bak.YYYYMMDD-HHMMSS` on collision) **before** any disk write.
2. **Atomic writes**: write to `*.new`, then atomic rename.
3. **Idempotency**: if the toolkit file exists AND CLAUDE.md has the `@import` line, state detection routes to C, not D or E.
4. **Rollback hint** in the report: `mv {backup_path} CLAUDE.md && rm CLAUDE-spine-toolkit.md`.
5. **Line endings**: normalize to LF on write.

## Core Questions

Labels from locale keys. Core asks three — minus any the input already answered; every stack
question belongs to the platform half.

- q0 — Language: `en` / `ru` (`auq_lang_label`, `auq_lang_options`)
- qM — Mode: `manual` (default) / `auto` (`auq_mode_label`)
- qP — Progress: `normal` (default) / `quiet` / `live` (`auq_progress_label`)

## Placeholder Replacements

In `templates/claude-toolkit-md/en.md` (the toolkit file is EN-only):

| Placeholder | Source | Substituted with |
|---|---|---|
| `<platform-plugin>` in `## Platform` | step 1 | the resolved platform plugin name |
| the `<one … line per axis …>` placeholder in `## Stack` | step 5 | the axis lines the platform half wrote |
| first non-empty line under `## Mode` | qM | `manual` or `auto` |
| first non-empty line under `## Progress` | qP | `quiet`, `normal` or `live` |
| first non-empty line under `## DeliveryMode` | template default | `manual`; do not replace this when applying qM |
| `en` value in `## Language` | q0 | `en` or `ru` |
| `<Communication Language>` in `## Persona` | q0 | `English` or `Russian` (the human-readable language name; drives Claude's communication language with the user) |

`## Agents` keeps its template body verbatim. That body is explanatory prose with angle-bracket
placeholders, so the block ships in every config holding no row — the state to expect. Setup never
writes a row into it.

In `templates/claude-md-stub/<lang>.md`:

| Placeholder | Source |
|---|---|
| `{project_name}` | basename of the project directory |

## Edge cases

- **No platform plugin installed** → `error_no_platform_installed`. Stop. No disk changes.
- **Templates not found** → `error_template_not_found`. Stop.
- **AUQ unavailable** → text fallback with numbered options.
- **User cancels** (Cancel on the AUQ in state C, D or E) → exit, no disk changes.
- **Tasks/ already exists** → no overwrite; report `tasks_status_already_existed`.
- **Docs/ already exists** → no overwrite; report `docs_status_already_existed`.

## What this skill does NOT do

- Does NOT create a project, a build manifest, sources, linter config, or `README.md` — that is the platform plugin's `init` agent.
- Does NOT ask a stack question or write `## Stack` / `## Modules` — that is the platform half.
- Does NOT modify source code or existing project configs.
- Does NOT start workflows or call `orchestrator`.
- Does NOT init git or make commits.
- Does NOT install dependencies.
- Does NOT create the first task — use `/task-new`.
- Does NOT modify user content in `CLAUDE.md` beyond inserting/preserving the `@import` line and (in state D) splitting toolkit sections out.
