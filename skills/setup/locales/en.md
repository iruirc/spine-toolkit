# setup — en

## error_no_platform_installed
No platform plugin is installed. spine-toolkit needs one to know your stack — install swift-platform (or another platform plugin) and run `/setup` again.

## platform_choice_question
Several platform plugins are installed. Which one serves this project?

## auq_platform_confirm
Platform plugin `{plugin}` is the only one installed. Use it for this project?

## auq_platform_confirm_options
Yes | Cancel

## error_template_not_found
CLAUDE-spine-toolkit.md template not found. Check the spine-toolkit plugin root's `templates/` or the active host's installed plugin/cache templates.

## auq_create_tasks_structure
Create the `Tasks/` structure for managing tasks? [Yes / No]

## auq_create_docs_structure
Create the `Docs/` structure for project documentation? [Yes / No]

## auq_lang_label
Toolkit language for prompts

## auq_lang_options
en | ru

## auq_mode_label
Workflow mode

## auq_progress_label
How much a profile run narrates itself

## auq_reconfigure_toolkit
spine-toolkit is already configured (`CLAUDE-spine-toolkit.md` exists). What should I do?

## auq_reconfigure_toolkit_options
Overwrite | Backup-and-overwrite | Cancel

## auq_migrate_old_format
Detected the old single-file format (`CLAUDE.md` contains toolkit sections). I will migrate to the two-file layout: move toolkit sections to `CLAUDE-spine-toolkit.md`, keep your sections in `CLAUDE.md`, insert the import line, and back up the original to `CLAUDE.md.bak`. Proceed?

## auq_migrate_old_format_options
Migrate-and-backup | Cancel

## auq_migrate_config_name
Found a pre-split config `CLAUDE-swift-toolkit.md`. I will rename it to `CLAUDE-spine-toolkit.md`, add the `## Platform` block naming `{plugin}`, reconcile `## Stack` against that platform's current axes, repoint the import line in `CLAUDE.md`, and back up the original. Everything the file already answers is kept, not re-asked. Proceed?

## auq_migrate_config_name_options
Migrate-and-backup | Cancel

## setup_done
✅ spine-toolkit configured in this project.

`CLAUDE-spine-toolkit.md` written:
  - Platform: {platform}
  - Stack: {stack}
  - Mode: {mode}
  - Progress: {progress}
  - Language: {lang}

Tasks/ structure: {tasks_status}
Docs/ structure: {docs_status}
{notes}
Next steps:
  - create your first task: /task-new <description>
  - run a task: /spine-toolkit:task-run <id>
  - check status: /task-status

## report_migration_success
✅ Migrated to the two-file layout.

Moved to `CLAUDE-spine-toolkit.md`: {moved_sections}
Kept in `CLAUDE.md`: {kept_sections}
Filled with defaults: {filled_default_sections}
Warnings: {warnings}
Backup: {backup_path}
{notes}

To roll back: `mv {backup_path} CLAUDE.md && rm CLAUDE-spine-toolkit.md`

## stack_status_deferred
not set — this platform ships no setup skill; the orchestrator will ask per axis on the first task that needs one

## tasks_status_created
created

## tasks_status_already_existed
already existed

## tasks_status_skipped
skipped

## docs_status_created
created

## docs_status_already_existed
already existed

## docs_status_skipped
skipped
