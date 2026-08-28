# setup — ru

## error_no_platform_installed
Ни один платформенный плагин не установлен. spine-toolkit не может узнать твой стек без него — установи swift-platform (или другой платформенный плагин) и запусти `/setup` снова.

## platform_choice_question
Установлено несколько платформенных плагинов. Какой обслуживает этот проект?

## auq_platform_confirm
Платформенный плагин `{plugin}` — единственный установленный. Использовать его для этого проекта?

## auq_platform_confirm_options
Yes | Cancel

## error_template_not_found
Шаблон CLAUDE-spine-toolkit.md не найден. Проверь `templates/` в корне плагина spine-toolkit или установленные plugin/cache-шаблоны текущего хоста.

## auq_create_tasks_structure
Создать `Tasks/` структуру для управления задачами? [Yes / No]

## auq_create_docs_structure
Создать `Docs/` структуру для документации проекта? [Yes / No]

## auq_lang_label
Язык подсказок toolkit

## auq_lang_options
en | ru

## auq_mode_label
Режим воркфлоу

## auq_progress_label
Насколько подробно прогон профиля рассказывает о себе

## auq_reconfigure_toolkit
spine-toolkit уже настроен в проекте (`CLAUDE-spine-toolkit.md` существует). Что сделать?

## auq_reconfigure_toolkit_options
Overwrite | Backup-and-overwrite | Cancel

## auq_migrate_old_format
Обнаружен старый однофайловый формат (`CLAUDE.md` содержит toolkit-секции). Я перенесу его в двухфайловую раскладку: toolkit-секции уедут в `CLAUDE-spine-toolkit.md`, твои секции останутся в `CLAUDE.md`, добавится import-строка, оригинал сохранится в `CLAUDE.md.bak`. Продолжить?

## auq_migrate_old_format_options
Migrate-and-backup | Cancel

## auq_migrate_config_name
Найден дораскольный конфиг `CLAUDE-swift-toolkit.md`. Я переименую его в `CLAUDE-spine-toolkit.md`, добавлю блок `## Platform` со значением `{plugin}`, сверю `## Stack` с текущими осями этой платформы, перенаправлю import-строку в `CLAUDE.md` и сохраню бэкап оригинала. Всё, на что файл уже отвечает, сохраняется и заново не спрашивается. Продолжить?

## auq_migrate_config_name_options
Migrate-and-backup | Cancel

## setup_done
✅ spine-toolkit настроен в этом проекте.

`CLAUDE-spine-toolkit.md` записан:
  - Платформа: {platform}
  - Стек: {stack}
  - Режим: {mode}
  - Прогресс: {progress}
  - Язык: {lang}

Tasks/ структура: {tasks_status}
Docs/ структура: {docs_status}
{notes}
Следующие шаги:
  - создать первую задачу: /task-new <описание>
  - запустить задачу: /task-run <id>
  - посмотреть статус: /task-status

## report_migration_success
✅ Миграция в двухфайловую раскладку выполнена.

Перенесено в `CLAUDE-spine-toolkit.md`: {moved_sections}
Осталось в `CLAUDE.md`: {kept_sections}
Заполнено дефолтами: {filled_default_sections}
Предупреждения: {warnings}
Бэкап: {backup_path}
{notes}

Откат: `mv {backup_path} CLAUDE.md && rm CLAUDE-spine-toolkit.md`

## stack_status_deferred
не задан — у этой платформы нет setup-скилла; оркестратор спросит по осям на первой задаче, которой они понадобятся

## tasks_status_created
создана

## tasks_status_already_existed
уже существовала

## tasks_status_skipped
пропущена

## docs_status_created
создана

## docs_status_already_existed
уже существовала

## docs_status_skipped
пропущена
