# setup — ru

## error_no_platform_installed
Ни один платформенный плагин не установлен. spine-toolkit не может узнать твой стек без него — установи один (spine-platform-swift для Swift, spine-platform-kotlin для Kotlin или другой платформенный плагин) и запусти `/setup` снова.

## platform_choice_question
Установлено несколько платформенных плагинов. Какой обслуживает этот проект?

## auq_platform_confirm
Платформенный плагин `{plugin}` — единственный установленный. Использовать его для этого проекта?

## auq_platform_confirm_options
Yes | Cancel

## error_template_not_found
Шаблон SPINE.md не найден. Проверь `templates/` в корне плагина spine-toolkit или установленные plugin/cache-шаблоны текущего хоста.

## auq_create_tasks_structure
Создать `Tasks/` структуру для управления задачами? [Yes / No]

## auq_create_docs_map
Создать `DocsMap.md` — реестр компонентов документации проекта? [Yes / No]

## auq_lang_label
Язык подсказок toolkit

## auq_lang_options
en | ru

## auq_mode_label
Режим воркфлоу

## auq_progress_label
Насколько подробно прогон профиля рассказывает о себе

## auq_reconfigure_toolkit
spine-toolkit уже настроен в проекте (`SPINE.md` существует). Что сделать?

## auq_reconfigure_toolkit_options
Overwrite | Backup-and-overwrite | Cancel

## auq_migrate_old_format
Обнаружен старый однофайловый формат (`CLAUDE.md` содержит toolkit-секции). Я перенесу его в двухфайловую раскладку: toolkit-секции уедут в `SPINE.md`, твои секции останутся в `CLAUDE.md`, добавится import-строка, оригинал сохранится в `CLAUDE.md.bak`. Продолжить?

## auq_migrate_old_format_options
Migrate-and-backup | Cancel

## auq_migrate_config_name
Найден дораскольный конфиг `CLAUDE-swift-toolkit.md`. Я переименую его в `SPINE.md`, добавлю блок `## Platform` со значением `{plugin}`, сверю `## Stack` с текущими осями этой платформы, перенаправлю import-строку в `CLAUDE.md` и сохраню бэкап оригинала. Всё, на что файл уже отвечает, сохраняется и заново не спрашивается. Продолжить?

## auq_migrate_config_name_options
Migrate-and-backup | Cancel

## auq_migrate_spine_name
Конфиг toolkit в проекте лежит под старым именем `CLAUDE-spine-toolkit.md`. Переименовать в `SPINE.md`? Внутри ничего не меняется, кроме строки заголовка; строка импорта в `CLAUDE.md` обновится. Оставить старое имя тоже можно: все читатели принимают оба.

## auq_migrate_spine_name_options
Переименовать | Оставить старое имя

## report_spine_name_migrated
✅ Переименовано `CLAUDE-spine-toolkit.md` → `SPINE.md`; `CLAUDE.md` теперь импортирует `@./SPINE.md`.

Откат: `mv SPINE.md CLAUDE-spine-toolkit.md` и вернуть строку импорта в `CLAUDE.md` на `@./CLAUDE-spine-toolkit.md`.

## report_spine_name_kept
Оставлен `CLAUDE-spine-toolkit.md`; toolkit читает его как раньше. Запусти `/setup` снова, когда захочешь переименовать в `SPINE.md`.

## setup_done
✅ spine-toolkit настроен в этом проекте.

`SPINE.md` записан:
  - Платформа: {platform}
  - Стек: {stack}
  - Режим: {mode}
  - Прогресс: {progress}
  - Язык: {lang}

Tasks/ структура: {tasks_status}
DocsMap.md: {docs_map_status}
{notes}
Следующие шаги:
  - создать первую задачу: /task-new <описание>
  - запустить задачу: /spine-toolkit:task-run <id>
  - посмотреть статус: /task-status

## report_migration_success
✅ Миграция в двухфайловую раскладку выполнена.

Перенесено в `SPINE.md`: {moved_sections}
Осталось в `CLAUDE.md`: {kept_sections}
Заполнено дефолтами: {filled_default_sections}
Поля, оставшиеся на дефолте: {filled_default_fields}
Предупреждения: {warnings}
Бэкап: {backup_path}
{notes}

Откат: `mv {backup_path} CLAUDE.md && rm SPINE.md`

## report_block_migration
✅ `{config_name}` переведён в формат полей 2.0. Ничего не спрашивалось: все значения взяты из самого файла.

Перенесено в поля: {moved_fields}
Поля, оставшиеся на дефолте: {filled_default_fields}
Сохранено без изменений: {kept_blocks}
Бэкап: {backup_path}

Откат: `mv {backup_path} {config_name}`

## stack_status_deferred
не задан — у этой платформы нет setup-скилла; оркестратор спросит по осям на первой задаче, которой они понадобятся

## stack_status_deferred_by_caller
не задан — вызывающий отложил его; оркестратор спросит по осям на первой задаче, которой они понадобятся

## tasks_status_created
создана

## tasks_status_already_existed
уже существовала

## tasks_status_skipped
пропущена

## docs_map_status_created
создан из шаблона — объявите в нём свои компоненты

## docs_map_status_already_existed
уже существовал, не тронут

## docs_map_status_skipped
пропущен

## report_agents_md_created
Создан `AGENTS.md`: через него Codex читает конфиг проекта.

## report_agents_md_appended
В конец `AGENTS.md` добавлен блок про конфиг проекта (бэкап: `{backup_path}`).

## report_agents_md_kept
`AGENTS.md` уже указывает Codex на конфиг проекта; оставлен как есть.

## report_agents_md_updated
`AGENTS.md` теперь называет переименованный конфиг проекта (бэкап: `{backup_path}`).

## auq_codex_git_rule
В песочнице Codex папка `.git` этого проекта доступна только на чтение, поэтому каждый коммит, который Spine делает после готовой фазы, будет спрашивать у тебя подтверждение. Разрешить `git add` и `git commit` без вопроса? В проекте появится файл `.codex/rules/spine.rules`: эти две команды пойдут без вопроса и вне песочницы, git-хуки проекта тоже. Чтобы отменить, удали файл.

## auq_codex_git_rule_options
Разрешить | Не разрешать — подтверждать каждый коммит

## auq_codex_menu
Сейчас вопросы Spine в Codex приходят текстом: ты отвечаешь цифрой. Codex умеет показывать их в виде меню, где вариант выбирается стрелками, как в Claude Code. Включить? В `{config_path}` в раздел `[features]` добавится строка `default_mode_request_user_input = true`. Она действует во всех сессиях Codex, а не только в этом проекте, и Codex покажет предупреждение, что функция «under development». Заработает после перезапуска: выйди из Codex, выполни `codex app-server daemon restart` и запусти Codex снова. Чтобы выключить, удали строку.

## auq_codex_menu_options
Включить | Не включать — вопросы останутся текстом

## report_codex_git_rule_written
Записан `.codex/rules/spine.rules`: после перезапуска Codex (выйди из него, выполни `codex app-server daemon restart`, запусти снова) коммиты идут без вопроса.

## report_codex_git_rule_declined
Правила для коммитов нет: Codex будет спрашивать перед каждым коммитом.

## report_codex_menu_enabled
Меню вопросов включено в `{config_path}`: выйди из Codex, выполни `codex app-server daemon restart` и запусти Codex снова.

## report_codex_menu_declined
Меню вопросов не включено: вопросы приходят нумерованным текстом.
