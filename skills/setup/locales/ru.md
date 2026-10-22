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

## auq_codex_permissions
В Codex Spine будет спрашивать подтверждение перед многими своими шагами. Он может настроить Codex так, чтобы они шли без вопросов:

{items}

Применить? Codex один раз попросит подтвердить запись этих файлов. Всё заработает после перезапуска: выйди из Codex, выполни `codex app-server daemon restart` и запусти Codex снова. Чтобы отменить настройку, удали названный файл или строку.

## auq_codex_permissions_options
Применить всё | Выбрать по одному | Ничего не менять — подтверждать каждый шаг

## auq_codex_permission_item
{item}

Записать эту настройку?

## auq_codex_permission_item_options
Записать | Пропустить

## codex_item_rules_core
- `.codex/rules/spine.rules` в проекте: коммиты после готовой фазы, сборки и тестовые прогоны, которые запускает Spine, и его проверка остатков пойдут без вопроса и вне песочницы — git-хуки проекта тоже.

## codex_item_rules_platform
- `.codex/rules/{file}` в проекте: команды сборки, тестов и симулятора платформы пойдут без вопроса и вне песочницы, а с ними и сборочные скрипты проекта.

## codex_item_menu
- Меню вопросов: вопросы Spine придут меню, где вариант выбирается стрелками, а не нумерованным текстом. В `{config_path}` в раздел `[features]` добавится `default_mode_request_user_input = true`; действует во всех сессиях Codex, и Codex предупредит, что функция «under development».

## codex_item_mcp
- MCP-сервер `{server}`: Codex перестанет спрашивать перед каждым его вызовом — валидация делает их десятки. В его раздел в `{config_path}` добавится `default_tools_approval_mode = "approve"`.

## codex_item_root_missing
- `{path}`: внешние пакеты из конфига проекта; стадии Spine смогут писать туда без вопроса. Путь добавится в `writable_roots` файла `.codex/config.toml` проекта.

## codex_item_root_stale
- `{path}`: больше нет в конфиге проекта; путь уберётся из `writable_roots` файла `.codex/config.toml` проекта.

## report_codex_permissions_written
Настройки Codex записаны. Заработают после перезапуска: выйди из Codex, выполни `codex app-server daemon restart` и запусти Codex снова.

## report_codex_permissions_declined
Настройки Codex не изменены: Codex продолжит спрашивать перед этими шагами.

## report_codex_permissions_error
Не удалось проверить настройки Spine для Codex: {error}
