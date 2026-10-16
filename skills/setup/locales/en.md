# setup — en

## error_no_platform_installed
No platform plugin is installed. spine-toolkit needs one to know your stack — install one (spine-platform-swift for Swift, spine-platform-kotlin for Kotlin, or another platform plugin) and run `/setup` again.

## platform_choice_question
Several platform plugins are installed. Which one serves this project?

## auq_platform_confirm
Platform plugin `{plugin}` is the only one installed. Use it for this project?

## auq_platform_confirm_options
Yes | Cancel

## error_template_not_found
SPINE.md template not found. Check the spine-toolkit plugin root's `templates/` or the active host's installed plugin/cache templates.

## auq_create_tasks_structure
Create the `Tasks/` structure for managing tasks? [Yes / No]

## auq_create_docs_map
Create `DocsMap.md`, the registry of this project's documentation components? [Yes / No]

## auq_lang_label
Toolkit language for prompts

## auq_lang_options
en | ru

## auq_mode_label
Workflow mode

## auq_progress_label
How much a profile run narrates itself

## auq_reconfigure_toolkit
spine-toolkit is already configured (`SPINE.md` exists). What should I do?

## auq_reconfigure_toolkit_options
Overwrite | Backup-and-overwrite | Cancel

## auq_migrate_old_format
Detected the old single-file format (`CLAUDE.md` contains toolkit sections). I will migrate to the two-file layout: move toolkit sections to `SPINE.md`, keep your sections in `CLAUDE.md`, insert the import line, and back up the original to `CLAUDE.md.bak`. Proceed?

## auq_migrate_old_format_options
Migrate-and-backup | Cancel

## auq_migrate_config_name
Found a pre-split config `CLAUDE-swift-toolkit.md`. I will rename it to `SPINE.md`, add the `## Platform` block naming `{plugin}`, reconcile `## Stack` against that platform's current axes, repoint the import line in `CLAUDE.md`, and back up the original. Everything the file already answers is kept, not re-asked. Proceed?

## auq_migrate_config_name_options
Migrate-and-backup | Cancel

## auq_migrate_spine_name
Your project carries its toolkit config under the old name `CLAUDE-spine-toolkit.md`. Rename it to `SPINE.md`? Nothing inside changes except the title line, and the import line in `CLAUDE.md` is updated to match. Keeping the old name is fine too: every reader accepts both.

## auq_migrate_spine_name_options
Rename | Keep the old name

## report_spine_name_migrated
✅ Renamed `CLAUDE-spine-toolkit.md` → `SPINE.md`; `CLAUDE.md` now imports `@./SPINE.md`.

To roll back: `mv SPINE.md CLAUDE-spine-toolkit.md` and put the import line in `CLAUDE.md` back to `@./CLAUDE-spine-toolkit.md`.

## report_spine_name_kept
Kept `CLAUDE-spine-toolkit.md`; the toolkit keeps reading it as before. Run `/setup` again whenever you want it renamed to `SPINE.md`.

## setup_done
✅ spine-toolkit configured in this project.

`SPINE.md` written:
  - Platform: {platform}
  - Stack: {stack}
  - Mode: {mode}
  - Progress: {progress}
  - Language: {lang}

Tasks/ structure: {tasks_status}
DocsMap.md: {docs_map_status}
{notes}
Next steps:
  - create your first task: /task-new <description>
  - run a task: /spine-toolkit:task-run <id>
  - check status: /task-status

## report_migration_success
✅ Migrated to the two-file layout.

Moved to `SPINE.md`: {moved_sections}
Kept in `CLAUDE.md`: {kept_sections}
Filled with defaults: {filled_default_sections}
Fields left at their default: {filled_default_fields}
Warnings: {warnings}
Backup: {backup_path}
{notes}

To roll back: `mv {backup_path} CLAUDE.md && rm SPINE.md`

## report_block_migration
✅ `{config_name}` is now in the 2.0 field format. Nothing was asked: every value came from the file itself.

Moved into fields: {moved_fields}
Fields left at their default: {filled_default_fields}
Kept unchanged: {kept_blocks}
Backup: {backup_path}

To roll back: `mv {backup_path} {config_name}`

## stack_status_deferred
not set — this platform ships no setup skill; the orchestrator will ask per axis on the first task that needs one

## stack_status_deferred_by_caller
not set — the caller deferred it; the orchestrator will ask per axis on the first task that needs one

## tasks_status_created
created

## tasks_status_already_existed
already existed

## tasks_status_skipped
skipped

## docs_map_status_created
created from the template — declare your components in it

## docs_map_status_already_existed
already existed, left untouched

## docs_map_status_skipped
skipped

## report_agents_md_created
Created `AGENTS.md`: Codex reads the project config through it.

## report_agents_md_appended
Added the project config block to the end of `AGENTS.md` (backup: `{backup_path}`).

## report_agents_md_kept
`AGENTS.md` already points Codex at the project config; left as it was.

## report_agents_md_updated
`AGENTS.md` now names the renamed project config (backup: `{backup_path}`).

## auq_codex_git_rule
Codex keeps this project's `.git` read-only in its sandbox, so every commit Spine makes after a finished phase would stop to ask you. Allow `git add` and `git commit` without asking? This writes `.codex/rules/spine.rules` in the project: those two commands then run without a question and outside the sandbox, and so do the project's git hooks. To undo, delete the file.

## auq_codex_git_rule_options
Allow | Don't allow — confirm every commit

## auq_codex_menu
Spine's questions in Codex come as text now: you answer with a number. Codex can show them as a menu you pick from with the arrow keys, as in Claude Code. Turn it on? This adds `default_mode_request_user_input = true` under `[features]` in `{config_path}`. It applies to every Codex session, not only this project, and Codex shows a warning that the feature is "under development". It takes effect after a restart: exit Codex, run `codex app-server daemon restart`, and start Codex again. To turn it off, delete the line.

## auq_codex_menu_options
Turn on | Don't turn on — questions stay as text

## report_codex_git_rule_written
Wrote `.codex/rules/spine.rules`: after a restart of Codex — exit it, run `codex app-server daemon restart`, start it again — commits run without asking.

## report_codex_git_rule_declined
No commit rule: Codex will ask before each commit.

## report_codex_menu_enabled
Question menu turned on in `{config_path}`: exit Codex, run `codex app-server daemon restart`, and start Codex again.

## report_codex_menu_declined
Question menu left off: questions come as numbered text.
