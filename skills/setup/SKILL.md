---
name: setup
description: |
  Configures spine-toolkit in an existing project: picks the platform plugin that serves it, creates SPINE.md from the template, inserts an @./ import line into CLAUDE.md, creates the Tasks/ structure and offers the documentation registry, and hands the platform half its own blocks. Migrates projects on the legacy single-file CLAUDE.md layout, on the pre-split config name, on the 1.x block format, and renames the pre-multi-runtime CLAUDE-spine-toolkit.md to SPINE.md on request.
  Use when (en): "set up spine-toolkit", "configure spine-toolkit", "install toolkit in project", "add spine-toolkit to project", "init toolkit here", "/setup"
  Use when (ru): "настрой spine-toolkit", "подключи spine-toolkit", "установи toolkit в проект", "добавь spine-toolkit к проекту", "инициализируй toolkit здесь", "/setup"
---

# Setup

Bootstraps spine-toolkit in an **already existing** project. Two-file layout:

- `SPINE.md` — toolkit-owned configuration, the *project config* (`conventions/task-settings.md` → Project config); its sections are the ones `templates/spine-md/en.md` carries. Created and updated by this skill. A project set up before the toolkit ran in more than one runtime carries the same file as `CLAUDE-spine-toolkit.md`; every reader accepts that name, and state G below renames it on request.
- `CLAUDE.md` — user-owned project instructions. Touched once to insert the `@./SPINE.md` line; otherwise unchanged.
- `AGENTS.md` — touched only when this skill runs in Codex CLI, which reads `AGENTS.md` and no `@`-import: one marked block pointing at the project config (see **AGENTS.md (Codex CLI)**).

This skill owns the config **format** and every block or field that is core's: `[LANG]`, `[WORKFLOW_MODE]`, `[PROGRESS]`, `## Platform`, `## Agents`, and the file-level scaffolding. It owns none of the stack: `## Stack` and `## Modules` are filled by the platform half (step 5), because which axes exist and which values they take is the platform manifest's `## Axes`, not core's.

The skill creates no source files, modifies no code, and starts no workflow. Generating a project from scratch belongs to the platform plugin's `init` agent.

## Input

Normally invoked by the user with nothing. It also accepts answers a caller has already collected —
a platform's `init` agent, which asks the same stack questions before scaffolding a project, is the
case this exists for; a platform command that writes a config into a repository holding no code yet
is the other:

```
lang     = en | ru                    # skips q0
mode     = manual | auto              # skips qM
progress = quiet | normal | live      # skips qP
platform = plugin name                # skips Platform Discovery
stack    = {axis: value, …} | —       # forwarded to the platform half in step 5; — skips step 5
tasks    = create | skip              # skips step 6's question
docs_map = create | skip              # skips step 6b's question
```

Every field is optional; an absent one means the question is asked as usual, so an empty input is
the ordinary `/setup` run. A caller that fills every field is asked nothing about the config — a
batch run relies on that; the overwrite and migration confirmations of states C, D and E are consent,
not config, and have no field. `stack` values must be spelled as the platform's `## Axes` catalog spells
them — the platform half matches them against that catalog and asks for whatever it cannot place, so
a value in the caller's own vocabulary costs one re-asked question, never a wrong config.

## Language Resolution

Special case for `setup`: the project config does not yet exist on first install (we are creating it). The skill therefore asks for the language as the very first question (q0) using keys `auq_lang_label` and `auq_lang_options`. Until that answer arrives, the q0 prompt is shown bilingually (English label / Russian label). From q0 onward, `<lang>` is the chosen value (`en` or `ru`), and every subsequent AUQ / error / report uses `locales/<lang>.md`. If q0 is skipped (text fallback, harness limitation), default to `en`.

The full resolution procedure used elsewhere — read the project config's `[LANG]` field — applies after `setup` has finished.

## Agent Tooling

**Runtime.** This skill names Claude Code tools. `<runtime>` is the host you run in: `claude-code` in Claude Code, `codex-cli` in Codex CLI. Outside Claude Code, read `<core root>/runtimes/<runtime>.md` before anything else: it maps each tool named here — the structured question, loading `<platform>:manifest` and the platform's setup skill — to the host's own.

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

The skill's behavior is determined by the project state, computed from five checks:

1. Does `CLAUDE.md` exist in the project root?
2. Does `SPINE.md` exist in the project root — and if it does, does it carry a heading from the first column of the block-to-field mapping below?
2b. Does `CLAUDE-spine-toolkit.md` — the pre-multi-runtime name of the same file — exist in the project root, and in which format (the same heading check)? (That heading is the 1.x block format, the one `scripts/resolve-settings.sh` refuses to read. Scan raw lines exactly as the resolver does, fences included — not the Parser's rule below: a file the resolver refuses must never classify as already configured, or the two readers send the user round a loop.)
3. Does a pre-split `CLAUDE-swift-toolkit.md` exist in the project root?
4. Does `CLAUDE.md` carry a `Language`, `Stack` or `Mode` heading? (That is the legacy single-file layout, where all three lived in `CLAUDE.md`.)

| State | `CLAUDE.md` | `SPINE.md` | `CLAUDE-spine-toolkit.md` | Pre-split config | Toolkit sections in `CLAUDE.md`? | Action branch |
|---|---|---|---|---|---|---|
| **A · new_install** | absent | absent | absent | absent | — | Ask q0, qM, qP. Create both files. |
| **B · existing_md** | present | absent | absent | absent | no | Ask q0, qM, qP. Backup CLAUDE.md. Insert `@import` line. Create `SPINE.md`. |
| **C · already_configured** | present | present, 2.0 fields | any | — | no | AUQ `auq_reconfigure_toolkit` on `SPINE.md` only. Self-heal `CLAUDE.md` if `@import` is missing. |
| **D · old_format** | present | absent | absent | absent | yes | AUQ `auq_migrate_old_format`. Run the migration algorithm (see below). |
| **E · renamed_config** | present | absent | absent | present | — | AUQ `auq_migrate_config_name`. Rename the file, reconcile blocks, rewrite the `@import` line. |
| **F · old_block_format** | present | present, 1.x headings | — | — | no | Migrate the config's format without asking. Back up, rewrite, report. |
| **G · legacy_name** | any | absent | present, 2.0 fields | — | no | AUQ `auq_migrate_spine_name`. Rename to `SPINE.md` and rewrite the `@import` line, or keep the name and report. |

A `CLAUDE-spine-toolkit.md` in the 1.x block format with no `SPINE.md` is **F on that file**: the
format migration rewrites it under the name it had, and the next `/setup` run is G.
**F is decided before G, and G before C**: a configured project whose file is 1.x is not already configured, it is a
project that cannot run. All five checks are file reads, so the state is known before step 0 asks
anything — which is what lets F take the language and the platform from the file instead of asking.

### Edge sub-states

- `CLAUDE.md` has the `@./SPINE.md` import line, but `SPINE.md` is absent: route to **state A** (create the toolkit file). Do not modify `CLAUDE.md`. A `@./CLAUDE-spine-toolkit.md` line whose file is absent routes to **state A** as well, with one difference: rewrite that line to `@./SPINE.md` once `SPINE.md` is written, or `CLAUDE.md` keeps importing a file that no longer exists.
- `SPINE.md` exists but `CLAUDE.md` is absent: create a stub `CLAUDE.md` from `templates/claude-md-stub/<lang>.md`. Toolkit file untouched.
- Both `SPINE.md` and `CLAUDE-spine-toolkit.md` exist: state **C** on `SPINE.md`. The new name wins; report the stale file rather than touching it, so nothing the user may still be reading is deleted behind their back — the resolver ignores it the same way and says so on stderr.
- Both `SPINE.md` (or `CLAUDE-spine-toolkit.md`) and a pre-split `CLAUDE-swift-toolkit.md` exist: state **C** (or **G**). The newer name wins; report the stale file rather than touching it.

## Algorithm

```
0. Ask the language (q0):
   AUQ using key `auq_lang_label` with options from `auq_lang_options` (`en` / `ru`).
   Store answer as <lang>; subsequent prompts/reports use locales/<lang>.md.
   Q0 is shown bilingually. If skipped, default <lang> = `en`.
   ↓ `lang` in the input → use it, ask nothing.
   ↓ state F → the config's own language value answers it, ask nothing.
   ↓ state G → the config already carries the language; ask nothing, and write nothing to it.

1. Resolve the platform (see Platform Discovery).
   ↓ `platform` in the input → use it, skip discovery: the caller that named one is the
     platform itself.
   ↓ state F → the config already names the platform; skip discovery.
   ↓ state G → the config already names the platform; skip discovery.
   ↓ none installed → render `error_no_platform_installed`. Stop.

2. Compute state (see State Detection table).

3. Locate templates:
   a. `templates/spine-md/en.md` — toolkit file template (English-only; the
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
     b. Render `templates/spine-md/en.md` with the Placeholder Replacements below.
        Write to <project>/SPINE.md.
     c. **If CLAUDE.md does NOT exist**: render `templates/claude-md-stub/<lang>.md` with
        `{project_name}` derived from the project directory name. Write to <project>/CLAUDE.md.
        **If CLAUDE.md DOES exist** (the broken-state edge sub-state): SKIP this sub-step.
        Do not overwrite the user's CLAUDE.md.

   STATE B (existing_md):
     a. Ask qM, qP.
     b. Render the toolkit template. Write to <project>/SPINE.md.
     c. If the `@./SPINE.md` line already exists anywhere in the file → skip
        c and d: CLAUDE.md is neither written nor backed up. Otherwise backup CLAUDE.md →
        CLAUDE.md.bak (collision suffix: .bak.YYYYMMDD-HHMMSS).
     d. Insert `@./SPINE.md` as a new line:
        - if the first non-empty line is an H1 (`# ...`), insert immediately after it
          (with one blank line before and after).
        - otherwise, insert at the very top of the file (with one blank line after).

   STATE C (already_configured):
     a. AUQ using key `auq_reconfigure_toolkit` with options `auq_reconfigure_toolkit_options`
        (Overwrite / Backup-and-overwrite / Cancel).
        - Cancel → stop, no disk changes.
        - Backup-and-overwrite → rename SPINE.md → SPINE.md.bak
          (timestamp on collision). Continue.
        - Overwrite → continue.
     b. Ask qM, qP.
     c. Render the toolkit template. Write to SPINE.md (overwrite).
     d. Self-heal CLAUDE.md: if the `@./SPINE.md` line is missing, run the
        insertion logic from State B step (d), with backup; a `@./CLAUDE-spine-toolkit.md` line
        left behind is rewritten to `@./SPINE.md` rather than joined by a second import.

   STATE D (old_format):
     a. Run the migration parser on CLAUDE.md. Compute moved/kept/defaulted/warning section sets.
     b. Show a summary preview (sections to move, kept, defaulted, warnings, backup path).
     c. AUQ `auq_migrate_old_format` with options `auq_migrate_old_format_options`
        (Migrate-and-backup / Cancel).
        - Cancel → stop, no disk changes.
        - Migrate-and-backup → continue.
     d. Backup CLAUDE.md → CLAUDE.md.bak (timestamp on collision).
     e. Build the new SPINE.md (toolkit_sections in canonical order; missing
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
     g. Atomic write to SPINE.md; remove the old file only after the write
        succeeds. Rewrite the `@./CLAUDE-swift-toolkit.md` line in CLAUDE.md to the new name
        (backup first); if the line is absent, insert it per State B step (d).

   STATE F (old_block_format):
     a. Parse the existing config — `SPINE.md`, or `CLAUDE-spine-toolkit.md` where that is the
        file the project has — with the section parser (it already splits on `## `).
     b. Map each moved block's value(s) onto the fields, per the mapping table below. A block
        the file does not carry contributes nothing; its field is written at the absent-field
        default named under that table — not always the template's line — and listed in
        {filled_default_fields}. A 1.9.0 config, which has no Budgets, Models or Effort block
        at all, migrates exactly as a full one does.
     c. Keep verbatim, in place: the blocks that stay — Persona, Rules, Platform, Agents, Stack,
        Modules, EstimationDeltas, DeliveryMode, AILeverage, Paths, Orchestration — and any
        heading in neither the canonical list nor the mapping, a near-miss like `Validaton`
        included. The resolver trips only on the ten exact names, so keeping one costs nothing
        while dropping it loses the user's own content. All of them go in {kept_blocks}.
     d. Back up the file, write the new one atomically under the name it had — `SPINE.md`, or
        `CLAUDE-spine-toolkit.md` where that is the file the project has — and report with
        `report_block_migration`, {config_name} being that name. CLAUDE.md is untouched: its
        import line already names this file. A legacy name is state G's business on the next run.
     e. Ask nothing, and skip every step that would: step 5's platform half, step 6, step 6b.
        Every value came from the file; what the file did not answer takes the default, which is
        what a 1.x project was already running on.

   STATE G (legacy_name):
     a. AUQ `auq_migrate_spine_name` with options `auq_migrate_spine_name_options`
        (Rename / Keep the old name).
        - Keep the old name → no change to the config or CLAUDE.md; run step 6c, then report
          `report_spine_name_kept`. Every reader
          keeps accepting the file under that name.
        - Rename → continue.
     b. `mv CLAUDE-spine-toolkit.md SPINE.md`. No backup: the rename is reversible by one `mv`,
        and nothing inside the file changes except the next step.
     c. Replace the file's first line — its H1 — with the H1 of `templates/spine-md/en.md`
        (`# SPINE.md — Spine Configuration`). Every other byte stays.
     d. In CLAUDE.md, replace the `@./CLAUDE-spine-toolkit.md` line with `@./SPINE.md`. No such
        line: insert `@./SPINE.md` per State B step (d), with backup — unless the file already
        carries `@./SPINE.md`, in which case leave it alone. A CLAUDE.md that does not exist is
        created from the stub as in the edge sub-state above, whichever answer was given: with
        Keep the old name the stub imports `@./CLAUDE-spine-toolkit.md`, the file the project has.
     e. Run step 6c (**AGENTS.md (Codex CLI)**). Report `report_spine_name_migrated`, whose rollback hint is
        `mv SPINE.md CLAUDE-spine-toolkit.md` plus restoring the import line. Stop. Every value
        is already in the file, so steps 5, 6 and 6b have nothing to ask; run `/setup` again
        (state C) to reconfigure.

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
   ↓ the input's `stack` is `—` → do not invoke it either: same placeholders, reported as
     `stack_status_deferred_by_caller` — the caller's repository has no stack to ask about yet.
   ↓ state F → do not invoke it either: that state asks nothing, and its ## Stack already holds
     the answers.

6. Optional Tasks/ structure (orthogonal to state, except F):
   ↓ state F → skip; that state asks nothing (step 4(e)).
   If Tasks/ does not exist:
     AUQ using key `auq_create_tasks_structure`, unless the input's `tasks` already answers it.
     ↓ Yes, or `tasks = create` → mkdir -p Tasks/{TODO,ACTIVE,DONE,BACKLOG,RESEARCH,CHECK,UNABLE_FIX};
       .gitkeep in each; tasks_status = `tasks_status_created`.
     ↓ No, or `tasks = skip` → skip; tasks_status = `tasks_status_skipped`.
   If Tasks/ exists (folder, symlink, or file) → tasks_status = `tasks_status_already_existed`
   (existing layouts, including manual symlinks, are NEVER overwritten).

6b. Optional documentation registry (orthogonal to state, except F):
   ↓ state F → skip; that state asks nothing (step 4(e)).
   If the registry named by [DOCS_MAP] does not exist:
     AUQ using key `auq_create_docs_map`, unless the input's `docs_map` already answers it.
     ↓ Yes, or `docs_map = create` → copy templates/docs-map/DocsMap.md to that path;
       docs_map_status = `docs_map_status_created`.
     ↓ No, or `docs_map = skip` → skip; docs_map_status = `docs_map_status_skipped`.
   If it exists → docs_map_status = `docs_map_status_already_existed` (never overwritten).
   Declaring what a project's documentation is stays the project's own work: the template ships
   two examples to delete, not a guess at this project's components.

6c. AGENTS.md, in Codex CLI only — see **AGENTS.md (Codex CLI)** below. Runs in every state,
   state F included: it asks nothing.

7. Render the report:
   - States A/B/C/E → key `setup_done` with placeholders {platform}, {stack}, {mode},
     {progress}, {lang}, {tasks_status}, {docs_map_status}, {notes}.
   - State D → key `report_migration_success` with placeholders {moved_sections},
     {kept_sections}, {filled_default_sections}, {filled_default_fields}, {warnings},
     {backup_path}, {notes}.
   - State F → key `report_block_migration` with placeholders {moved_fields},
     {filled_default_fields}, {kept_blocks}, {backup_path}, {config_name}.
   - State G → key `report_spine_name_migrated` after a rename, `report_spine_name_kept` after
     Keep; neither takes a placeholder.
   Then, when step 6c changed or found `AGENTS.md`, the line it names, on a line of its own.
   {notes} is the platform half's returned notes, one per line, already rendered in <lang>;
   empty when it reconciled nothing. It is the only place those lines surface, so a rewrite
   the platform performed silently would be a rewrite the user never sees.
```

One report, rendered here: the platform half is a delegate, not a second entry point, so its
returned axis lines fill `{stack}` rather than printing a report of their own.

## AGENTS.md (Codex CLI)

Codex CLI reads `AGENTS.md`, not `CLAUDE.md`, and expands no `@./` import, so the project config
reaches it through a sentence. Which runtime you are in is this skill's Runtime paragraph
(**Agent Tooling**).

- In Claude Code: nothing — `AGENTS.md` is neither read nor written.
- In Codex CLI (`codex-cli`), after the state's branch wrote or kept the config:
  - `AGENTS.md` absent → create it from `templates/agents-md-stub/<lang>.md`; report
    `report_agents_md_created`.
  - present without the line `<!-- spine: project config -->` → back it up to `AGENTS.md.bak`
    (`.bak.YYYYMMDD-HHMMSS` on collision), then append the stub's block — the marker and the
    sentence, without the stub's H1 — after one blank line at the end; report
    `report_agents_md_appended` with {backup_path}.
  - present with that line, and the sentence under it names the config file the project has →
    leave it untouched, no backup; report `report_agents_md_kept`.
  - present with that line, but the sentence under it names a different config file (an earlier
    run kept `CLAUDE-spine-toolkit.md`, this one renamed it) → back it up as above, replace that
    file name in the sentence under the marker and nothing else; report
    `report_agents_md_updated` with {backup_path}.
- The block names the config file the project has after this run: `SPINE.md`, or
  `CLAUDE-spine-toolkit.md` when state G kept the old name — then write that name in place of
  `SPINE.md` in the block.

The template resolves like every other (`conventions/agent-tooling.md` → Plugin Roots). Nothing else
of `CLAUDE.md` is copied into `AGENTS.md`, and nothing is written under `.codex/`.

## Migration Algorithm (states D, E and F)

### Parser

Splits the source file into a sequence of `[(heading, body), ...]` plus a `preamble` string.

Rules:
- Section boundary = a line that starts with the literal `## ` (h2). H1, h3+, indented `##` are NOT boundaries.
- A `## ` line inside a fenced code block (` ``` `) is NOT a boundary. The parser tracks fenced state.
- The `preamble` is everything before the first valid `## ` line (may be empty).
- A section body includes all lines until the next `## ` boundary (exclusive) or EOF.

### Section classification

Canonical toolkit headings = the `## ` headings of `templates/spine-md/en.md`, read from that file in the order it has them. Match case-insensitively and **exactly**, not by prefix.

Read the list rather than restating it here: a second copy falls behind the day the toolkit adds a section, and a section missing from the copy is silently never migrated into an existing project.

- `toolkit_sections` = sections whose heading matches the canonical list.
- `moved_blocks` = sections whose heading is in the first column of the mapping below. Their values
  become fields and the heading itself does not survive.
- `user_sections` = everything else, in original order.
- `unknown_warnings` = headings that look toolkit-like but don't match exactly (e.g. `Stacks`, `Mode (custom)`). Kept in `user_sections`. Surfaced in the report.

The canonical list and the mapping are one piece of knowledge read in two halves — what a toolkit
config holds that stays a block, and what it holds that became a field. A heading in neither is the
project's own. Neither half may be restated where the other is read: a heading missing from both
classifies as a user section, and the project's own value for it is dropped.

Exact match only — no prefix-matching. `## Stack Cookbook` is NOT classified as `Stack`.

### Block-to-field mapping

What a 1.x config's ten blocks become. Read by every migrating state: D and E find them in a legacy
or pre-split source, F finds them in a config that is otherwise current.

| Old block | Old key | New field | Value's shape in the old file |
|---|---|---|---|
| `Language` | — | `[LANG]` | the block's first value line |
| `Mode` | — | `[WORKFLOW_MODE]` | the block's first value line |
| `Progress` | — | `[PROGRESS]` | the block's first value line that is not `<key>: <value>` |
| `Progress` | `settings` | `[SETTINGS_REPORT]` | `settings: <value>` |
| `Scale` | — | `[SCALE]` | the block's first value line |
| `Reporting` | `walkthrough` | `[WALKTHROUGH]` | `walkthrough: <value>` |
| `Validation` | `drive_app` | `[DRIVE_APP]` | `drive_app: <value>`; spelled `mobile_mcp: <value>` before the rename, and that value is carried over, not dropped |
| `Validation` | `manual_checks` | `[MANUAL_CHECKS]` | `manual_checks: <value>` |
| `Validation` | `driver` | `[DRIVER]` | `driver: <value>` |
| `Validation` | `phase_verification` | `[PHASE_VERIFICATION]` | `phase_verification: <value>` |
| `Docs` | `enabled` | `[DOCS]` | `enabled: <value>` |
| `Docs` | `map` | `[DOCS_MAP]` | `map: <value>` |
| `Docs` | `strictness` | `[DOCS_STRICTNESS]` | `strictness: <value>` |
| `Docs` | `freshness` | `[DOCS_FRESHNESS]` | `freshness: <value>` |
| `Budgets` | every line | `[BUDGETS]` | one `<artifact>: <lines>` line per artifact → one comma-separated list |
| `Models` | every line | `[MODELS]` | one `<key>: <model>` line per key → one comma-separated list |
| `Effort` | every line | `[EFFORT]` | one `<role>: <level>` line per role → one comma-separated list |

A value is copied, never re-derived: the old file's spelling is what 1.x resolved, and a migration
that improves on it changes a project's behavior behind its back. The exception is a value 1.x read
past — chiefly the pre-rename spelling of `drive_app` in the row above — which now lands on what the
user wrote rather than on the default 1.x fell to.

A field no block answered is written at **the value `scripts/resolve-settings.sh` resolves when the
field is absent**, which is not the same thing as the template's line. Twenty-three agree; `[SCALE]` does
not — the template ships `lite`, the resolver resolves `full`. `lite` is what a *new* project is
given; a 1.x config with no `Scale` block was running `full`, and writing `lite` would take
`[WALKTHROUGH]` to `off` with it, so the project would silently stop writing `Walkthrough.md`.
`[WALKTHROUGH_CHECK]` agrees by its declared default `auto` — the resolver's own output for it is
the derived `on`/`off`, which is never what the file is written with.

### Preamble handling

This concerns the source that becomes `CLAUDE.md`, which is state D's. States E and F rewrite the
toolkit config, whose H1 and intro come from the toolkit template (see Output assembly), and leave
`CLAUDE.md` alone apart from the import line.

- **Toolkit preamble detected** if the H1 (first non-empty `# ...` line) matches any of these canonical strings (exact match, case-sensitive):
  - `# CLAUDE.md — Swift Toolkit` (legacy single-file template — both EN and RU legacy templates used the same H1 string; only the body was localized)
  - `# CLAUDE-swift-toolkit.md — Swift Toolkit Configuration` (pre-split two-file template)
  - `# CLAUDE-spine-toolkit.md — Toolkit Configuration` (pre-multi-runtime two-file template)
  - `# SPINE.md — Spine Configuration` (current)
  → Discard the preamble, replace it with the rendered `templates/claude-md-stub/<lang>.md`.
- **Otherwise**: preserve the preamble as-is. Insert `@./SPINE.md` after the H1 (or at the very top if no H1) before the first user section.

### Output assembly

`SPINE.md`:
```
<H1 + intro from templates/spine-md/en.md>

<toolkit_sections in canonical order>
```

For canonical sections missing from the source: fill from the template default (e.g. `## DeliveryMode\n\nmanual`). Track in `filled_default_sections` for the report.

The two field blocks are canonical sections no migrating source has, so they always arrive from the
template. The mapping then replaces the bracketed value of each field a moved block answered; a
field none answered is written at the absent-field default named under the mapping — the template's
line for twenty-three of them, `full` for `[SCALE]` — and listed in `filled_default_fields`. The moved
blocks themselves are not carried over: their headings are gone from the format, and one left in
the file is what the resolver refuses.

`## Platform` is the one exception, in migrating states D and E, and it is unconditional: it is
written from the platform resolved in step 1 and never appears in `filled_default_sections`, whether
the source lacks the section (the normal case — the block did not exist before the split) or carries
one (the pre-split stack axis was also called `Platform`, so such a section holds a version string,
not a plugin name). Its template default is a placeholder, not a value, so neither source can
supply it. A config carrying the placeholder is worse than one carrying nothing:
Routing check 4 sees a config, so the run proceeds to step 5.7 and fails there naming a plugin that
does not exist.

A `[MOBILE_MCP]` line in a Task.md of a task already in flight is **not** migrated
— core reads only `[DRIVE_APP]`, so such a task falls back to the project default; say so once in the
migration report rather than rewriting task folders.

`CLAUDE.md` (state D only — states E and F leave that file alone):
```
<preamble: stub or preserved>

@./SPINE.md

<user_sections in original order>
```

Empty `user_sections` → the file ends at the `@import` line (with a trailing newline).

### Safeguards

1. **Backup before a write**: the source file → `<name>.bak` (or `.bak.YYYYMMDD-HHMMSS` on collision) **before** any disk write to it. A file setup does not write gets no backup. State G's H1 rewrite is the one exception: the rename it follows is undone by one `mv`, and the hint says so.
2. **Atomic writes**: write to `*.new`, then atomic rename.
3. **Idempotency**: if the toolkit file exists AND CLAUDE.md has the `@import` line, state detection routes to C, not D or E — to G while the file still carries the legacy name, and to F rather than either while it is still in the 1.x block format.
4. **Rollback hint** in the report: `mv {backup_path} CLAUDE.md && rm SPINE.md`. State F rewrote one file under its own name, so its hint is `mv {backup_path} {config_name}`. State G's is `mv SPINE.md CLAUDE-spine-toolkit.md` and the import line back.
5. **Line endings**: normalize to LF on write.

## Core Questions

Labels from locale keys. Core asks three — minus any the input already answered; every stack
question belongs to the platform half.

- q0 — Language: `en` / `ru` (`auq_lang_label`, `auq_lang_options`)
- qM — Mode: `manual` (default) / `auto` (`auq_mode_label`)
- qP — Progress: `normal` (default) / `quiet` / `live` (`auq_progress_label`)

## Placeholder Replacements

In `templates/spine-md/en.md` (the toolkit file is EN-only):

| Placeholder | Source | Substituted with |
|---|---|---|
| `<platform-plugin>` in `## Platform` | step 1 | the resolved platform plugin name |
| the `<one … line per axis …>` placeholder in `## Stack` | step 5 | the axis lines the platform half wrote |
| the bracketed value in `[WORKFLOW_MODE]` | qM | `manual` or `auto` |
| the bracketed value in `[PROGRESS]` | qP | `quiet`, `normal` or `live` |
| first non-empty line under `## DeliveryMode` | template default | `manual`; do not replace this when applying qM |
| the bracketed value in `[LANG]` | q0 | `en` or `ru` |
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
- **User cancels** (Cancel on the AUQ in state C, D or E) → exit, no disk changes. Keep the old name in
  state G is not a cancel: the config and CLAUDE.md stay as they are, and step 6c still runs.
- **Tasks/ already exists** → no overwrite; report `tasks_status_already_existed`.
- **The registry already exists** → no overwrite; report `docs_map_status_already_existed`.

## What this skill does NOT do

- Does NOT create a project, a build manifest, sources, linter config, or `README.md` — that is the platform plugin's `init` agent.
- Does NOT ask a stack question or write `## Stack` / `## Modules` — that is the platform half.
- Does NOT modify source code or existing project configs.
- Does NOT start workflows or call `orchestrator`.
- Does NOT init git or make commits.
- Does NOT install dependencies.
- Does NOT create the first task — use `/task-new`.
- Does NOT modify user content in `CLAUDE.md` beyond inserting/preserving the `@import` line and (in state D) splitting toolkit sections out.
