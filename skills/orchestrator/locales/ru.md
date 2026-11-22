# orchestrator — ru

## error_no_task_id
Укажи номер задачи, например `запусти 026` / `/spine-toolkit:task-run 026`.

## error_task_not_found
Задача `{task_id}` не найдена в `Tasks/`. Проверь номер и проект; чтобы создать новую задачу, запусти `/task-new <описание>`.

## error_task_ambiguous
Под `{task_id}` подходит больше одной задачи:
{matches}
Назови её полным именем папки или путём.

## error_task_outside_tasks
`{path}` — не задача внутри `{tasks}`. Открой задачу через папку `Tasks` этого проекта.

## error_no_project_config
В проекте нет `SPINE.md` — ничто не говорит, какая платформа его обслуживает, а без платформы некому диспетчеризовать стадии. Запусти `/setup`, чтобы подключить toolkit к этому проекту (он же мигрирует конфиг, оставшийся от прежней версии toolkit), либо точку инициализации платформенного плагина, если самого проекта ещё нет. Затем запусти задачу снова.

## error_no_platform_manifest
Манифест платформы не найден. В конфиге проекта указана платформа «{plugin}», но её скилл-манифест не загрузился. Установи платформенный плагин или поправь ## Platform в конфиге.

## error_core_older_than_platform
`{platform}` {platform_version} требует spine-toolkit `{requires}`, а сессия работает на {core}. Перезапусти сессию.

## fallback_profile_question
Какой профиль? (1) FEATURE (2) BUG (3) REFACTOR (4) TEST (5) REVIEW (6) EPIC (7) RESEARCH

## confirm_dispatch
Профиль: `{profile}`, режим: `{mode}`, стек: `{stack}`, старт: `{start_stage}`. Верно?

## error_research_required
Стадия `{stage}` требует `Research.md`. Запусти Research или используй `--skip-research`.

## error_redo_no_artifact
Нечего переделывать — артефакта `{stage}` нет. Используй `run --from {stage}`.

## stage_done_prompt
`{stage}` готова. Перейти к следующей? [Yes / Edit / No]

## stage_done_prompt_with_questions
`{stage}` готова, но в артефакте остались открытые вопросы:

{questions}

Что делаем?

## stage_done_option_continue
Перейти к следующей стадии

## stage_done_option_resolve
Ответить на вопросы сейчас

## stage_done_option_edit
Править артефакт вручную

## stage_done_dialog_question
Вопрос {n}/{total} — `{section}`: {text}

## stage_done_dialog_accept
Принять рекомендацию

## stage_done_dialog_defer
Отложить (DEFERRED)

## stage_done_dialog_skip
Пропустить (вернуться позже)

## auq_stage_recovery_question
Стадия `{invalid_stage}` не входит в профиль `{profile}`. Допустимы: {profile_stages_list}. Выбери одну:

## auq_stage_override_question
Выбери другую стартовую стадию для профиля `{profile}`:

## auq_stage_recovery_recommended_suffix
(Рекомендуется)

## auq_confirm_dispatch_pick_stage
Поправить стартовую стадию

## error_stage_not_in_profile
`{invalid_stage}` — недопустимая стадия профиля `{profile}`. Допустимы: {profile_stages_list}.

## confirm_dispatch_yes
Да

## confirm_dispatch_cancel
Отмена

## confirm_step_dispatch
Шаг `{step_id}` эпика `{epic_id}`: профиль `{profile}`, стек `{stack}`, старт `{start_stage}`. Запустить сейчас?

## confirm_step_dispatch_run
Запустить

## confirm_step_dispatch_later
Не сейчас: шаг и эпик ждут

## confirm_step_dispatch_skip
Закрыть без прогона (SKIPPED)

## info_step_postponed
Шаг `{step_id}` отложен — он и следующие шаги эпика `{epic_id}` ждут, их статус не меняется. Продолжить: `продолжи {epic_id}`.

## scale_lite_suggest
Похоже на маленькую задачу: {reason}. Её можно вести на `lite` — артефакты короче, проверки те же. Размер всё равно можно позже поднять до `full`.

## scale_lite_suggest_option
Да, запустить на lite

## auq_axis_ui_question
Какой UI-фреймворк использует эта задача?

## auq_axis_async_question
Какой async-подход использует эта задача?

## auq_axis_di_question
Какой подход Dependency Injection использует эта задача?

## auq_axis_architecture_question
Какую архитектуру использует эта задача?

## auq_axis_baseline_question
Какой baseline платформы у этой задачи?

## auq_axis_tests_question
Какой тестовый фреймворк использует эта задача?

## auq_axis_generic_question
Какое значение оси `{axis}` использует эта задача?

## auq_research_agent_question
Какой агент должен выполнить стадию Research?

## auq_research_agent_architect
Architect — feasibility, сравнительный анализ, исследование домена

## auq_research_agent_diagnostics
Diagnostics — аудит, инвентарь, поиск паттерна

## auq_research_agent_security
Security — OWASP, уязвимость, certificate pinning

## research_agent_diagnostics_keywords
audit; inventory; grep all; аудит; найди все

## research_agent_security_keywords
security; OWASP; vulnerability; certificate pinning; безопасность

## research_experiment_announce
Опыт: агент Research может менять код на ветке `{branch}`, собирать его и запускать приложение. Ветка не вливается.

## stage_error_prompt
Стадия {stage} вернула ошибку: {reason}. Диапазон останавливается здесь — следующая стадия строила бы работу на незавершённой.

## stage_error_option_retry
Повторить {stage}

## stage_error_option_stop
Остановиться и вернуть управление

## open_header
{profile} {task} · {start} → {end} · Progress: {progress} · {method}

## open_method_a
Method A

## open_method_b
Method B ({skill}): {why}

## open_stages
Стадии:

## open_workflows
Ход — во вьюхе /workflows: каждый диспатч там отдельная строка {workflow}, новые сверху.

## open_run_setting
Только на этот прогон: {field} {from} → {to}

## open_run_setting_kept
Только на этот прогон: {field} {to}, как и было

## open_directive
Уточнение владельца, дословно уходит каждой стадии: {directive}

## open_live_a
Панель токенов: запусти `bash "{script}" --session {session}` в соседней панели терминала.

## open_live_b
Каждый вызов агента хост рисует сам; панель токенов добавляет цифры, которых он не показывает.

## open_settings
Настройки:

## open_settings_rest
ещё {n} по умолчанию.

## open_core_lag
ядро {core} (установлено {installed}) · {platform} {platform_version} — перезапусти сессию, чтобы подхватить обновление

## open_core_incompatible
ядро {core} · {platform} {platform_version} требует spine-toolkit {requires} — перезапусти сессию

## progress_stage_metrics
{tuning} · {out} out · {ctx} ctx · {cacheWrite} cache-w · {cacheRead} cache-r · {tools} tools · {elapsed}

## progress_run_totals
{agents} агентов · {out} out · {elapsed}

## progress_run_volume
{total} итого · {cacheRead} cache-read · {cacheWrite} cache-write · {in} in

## dispatch_blocked_prompt
Тул Workflow доступен, и у профиля {profile} есть workflow-скрипт, но запуску мешает {reason}. Method B прогонит те же стадии через скилл.

## dispatch_blocked_option_a
Запустить через workflow (Method A)

## dispatch_blocked_option_b
Запустить через скилл (Method B)

## deviation_role_absent
Роль `{role}` на этой платформе не закрыта ни одним агентом, поэтому стадия {stage} выполняется здесь, в основном контексте.

## routing_project_init
Создание проекта с нуля — дело платформенного плагина: запусти его точку инициализации (агент, которым платформа закрывает роль `init`, обычно за собственной слэш-командой). Оркестратор ведёт задачи в `Tasks/`, а не бутстрап.

## scale_escalated
Размер повышен до `full` на стадии {stage}: {reason}. В `Task.md` записано `[SCALE] = [full]`; оставшиеся стадии идут на полной глубине.

## budget_over_limit
`{artifact}` — {actual} строк при потолке в {cap}. Сокращаю до потолка, не теряя требований.

## task_doc_anchor_missing
`{step}`: якорь `{anchor}` в `Task.md` отсутствует, пуст или стоит голый прочерк. Возвращаю архитектору: заполнить якорь или написать `— <причина>`, если он неприменим.

## warn_budget_unrecognised
`{line}` в `[BUDGETS]` файла `Task.md` или конфига проекта не называет ключ, который знает линт бюджета, или значение не целое положительное число, поэтому ключ решает следующий источник ниже. Ключи: `Task.md`, `Reproduce.md`, `Plan.md`, `Validation.md`, `Review.md` и `Done.md` считаются в строках, `words-per-sentence` считается в словах.

## lang_mismatch
`{artifact}` → `{section}`: проза не на языке проекта (`{lang}`). Возвращаю файл автору: переписать эту прозу на `{lang}`, структуру не трогать.

## lang_mismatch_persists
`{artifact}` → `{section}` после одного переписывания всё ещё не на языке проекта. Оставляю как есть, прогон продолжается.

## lang_mismatch_unowned
`{artifact}` → `{section}`: проза не на языке проекта (`{lang}`). Этот файл не пишет ни одна роль этого прогона, поэтому он не возвращается на переписывание и остаётся как есть.

## lang_readers_disagree
Проверка языка мерила прозу по `{measured}`, а этот прогон пишет на `{lang}`: два прочтения `[LANG]` расходятся, поэтому ни один файл не возвращается на переписывание.

## walkthrough_lint_finding
{line}. Возвращаю `Walkthrough.md` автору на исправление.

## walkthrough_lint_style
{line}. Находка стиля: попадает в отчёт, а `Walkthrough.md` за неё не возвращается — автор её уже получал один раз.

## walkthrough_lint_persists
{line} — осталось и после одного прохода. Оставляю `Walkthrough.md` как есть, прогон продолжается.

## leftover_process
Стадия оставила работающий процесс: `{cmd}` (pid {pid}, {age}, родитель {parent}).

## leftover_tree
Стадия оставила `{path}` в `{root}` ({change}), и её отчёт этого не объясняет.

## leftovers_prompt
Что сделать с тем, что оставила стадия?

## leftovers_option_kill
Остановить перечисленные процессы

## leftovers_option_restore
Вернуть изменённые и удалённые файлы к закоммиченному состоянию

## leftovers_option_leave
Оставить всё как есть

## leftovers_option_remove_added
Удалить файлы, которые стадия добавила в папку задачи

## stage_call_hung
Агент `{agent}` ждёт `{tool}` уже {age}, а инструмент не отвечает. Процессы под ним:

## stage_call_hung_option_kill
Остановить один из этих процессов — инструмент вернёт ошибку, стадия продолжится

## stage_call_hung_option_wait
Подождать ещё

## stage_call_hung_option_stop
Остановить стадию

## stage_watch_failed
Наблюдатель за зависшими вызовами завершился с кодом {code}: до конца стадии зависшие вызовы инструментов не отслеживаются. Его последняя строка:

## warn_walkthrough_pre_depth
`on` — значение, оставшееся от времён до оси глубины, поэтому оно читается как `deep`: словарь терминов, порядок коммитов и раздел на каждый коммит, тогда как `on` давал сводку и журнал по буллету на коммит. `on` проекта всё равно заканчивается на `off`, если `scale` этой задачи — `lite`: гейт стоит ниже собственного поля задачи и выше проектного. Чтобы сохранить прежнюю форму, напиши `brief` в `[WALKTHROUGH]` — в `Task.md` или в конфиге проекта.

## warn_artifact_check_pre_split
`[ARTIFACT_CHECK]` — написание времён до разделения на два поля, поэтому оно прочитано и как `[PLAN_CHECK]`, и как `[DONE_CHECK]` — каждое там, где не решает более близкая собственная строка. Прогон идёт дальше с тем, что получилось. Чтобы записать это по-нынешнему, замени вручную строку `[ARTIFACT_CHECK] = [X]` — в `Task.md` или в конфиге проекта — двумя строками `[PLAN_CHECK] = [X]` и `[DONE_CHECK] = [X]` с тем же `X`; если в файле эти две строки уже есть, впиши `X` в них и удали строку `[ARTIFACT_CHECK]`.

## warn_walkthrough_unrecognised
`{value}` — не одна из трёх глубин walkthrough, поэтому запись пропущена и решает остаток цепочки: `off`, если `scale` этой задачи — `lite`; иначе `[WALKTHROUGH]` проекта, если он что-то называет, и `deep`, если не называет ничего. Глубины такие: `brief`, `deep` и `off` — исправь значение в `[WALKTHROUGH]` — в `Task.md` или в конфиге проекта. Глубину, до которой этот прогон в итоге дорезолвил, называют настройки выше.

## warn_tuning_unrecognised
`{entry}` в {source} — не ключ и значение, которые этот прогон умеет применить, поэтому запись пропущена и действует следующая настройка. Ключи моделей — `light`, `walkthrough`, `done` и восемь ролей, со значениями `opus`, `sonnet`, `haiku`, `fable`, `fast` или `session`; ключи effort — `walkthrough`, `done` и восемь ролей, со значениями `low`, `medium`, `high`, `xhigh`, `max` или `session`.

## warn_model_read_as_session
`{entry}` в {source} называет модель Claude Code, которой в {runtime} нет, поэтому эта роль работает на модели сессии. Чтобы выбрать модель для этого runtime, задай там значение `fast` и добавь `fast@{runtime}: <модель>` в `[MODEL_TIERS]` конфига проекта; `/setup` может добавить строку `[MODEL_TIERS]`.

## warn_model_tier_unset
`{entry}` в {source}: в `[MODEL_TIERS]` нет строки `fast@{runtime}`, поэтому эта роль работает на модели сессии. Чтобы выбрать модель, добавь `fast@{runtime}: <модель>` в `[MODEL_TIERS]` конфига проекта: `[MODEL_TIERS]` в `Task.md` не читается.

## warn_effort_method_b
Effort, заданный для {roles}, в этом прогоне не действует: профиль идёт через свой скилл, а вызов агента из скилла не передаёт effort, поэтому все стадии работают на effort этой сессии. Выбор моделей по-прежнему действует.

## warn_driver_plugin_missing
Драйвер `{driver}` разрешён для этого прогона, но его манифест не резолвится — плагин не
установлен. Стадия, которая ведёт приложение, — валидация или опыт RESEARCH — отдаст свои
UI-проверки тебе. Поставь плагин или напиши `[DRIVER] = [—]` в конфиге проекта,
если так и задумано.

## warn_driver_server_missing
Драйвер `{driver}` установлен, но в этой сессии нет ни одного инструмента под объявленными им
префиксами ({namespaces}) — либо его MCP-сервер не подключён, либо зарегистрирован под другим
именем. Стадия, которая ведёт приложение, — валидация или опыт RESEARCH — отдаст свои UI-проверки
тебе. Запусти сервер, зарегистрируй его под одним из этих имён или напиши `[DRIVER] = [—]`
в конфиге проекта, если так и задумано.

## auq_catch_up_question
Задача была закончена, но после её Done появились коммиты:
{counts}
Что делаем?

## auq_catch_up_option
Догнать: проверить, отревьюить и закрыть только эти коммиты

## warn_catch_up_whole_task
В Done.md не записано, где стояли репозитории, поэтому Review прочитает всю задачу.

## warn_review_ranges_full
Review прочитал {repos} от базы задачи: их запись прошлого ревью переписана или её не было. Где нет и известной базы, он ревьюил собственные коммиты задачи в этом репозитории.

## error_catch_up_not_done
Нельзя догнать `{task_id}` — у задачи нет `Done.md`, она не была закончена. Продолжи её через `run {task_id}`.

## info_catch_up_nothing
Догонять нечего: ни в одном репозитории `{task_id}` нет коммитов после её Done.

## error_fix_review_nothing
У задачи `{task_id}` нет ревью, требующего изменений, — fix-review нечего исправлять.

## info_fix_round
Круг исправлений {n} из {max}: {count} находок из Review уходят в одну фазу плана.

## warn_fix_round_unrecorded
Круг исправлений {n} не оставил в Plan.md строки `Review fixes {n}`: фаза исправлений не записана, поэтому автоматический цикл останавливается здесь.

## auq_fix_review_question
Review требует изменений:
{findings}
Что делаем?

## auq_fix_review_option_all
Исправить все: одна фаза плана, затем Validation, Review исправлений, Done

## auq_fix_review_option_pick
Выбрать, какие исправлять

## auq_fix_review_option_leave
Пока оставить

## auq_fix_rounds_spent
Автоматические круги исправлений исчерпаны, а Review всё ещё требует изменений:
{findings}
Что делаем?

## auq_fix_rounds_option_more
Ещё один круг исправлений

## auq_fix_rounds_option_self
Исправлю сам, потом redo Review

## quick_escalation_stop
Задача `{task_id}` — не QUICK-правка: {reason}. Ничего не изменено. Поменяй `[TASK_TYPE]` в её `Task.md` на BUG, FEATURE или REFACTOR и запусти заново.

## known_failures_outside
Падения вне задачи:
{list}

## known_failures_add_flaky
Внести нестабильные в реестр известных падений как `flaky` и продолжить

## known_failures_add_permanent
Внести красные в реестр известных падений как `permanent` и повторить Validation

## known_failures_cleared
{ids} больше не падают. Перенести их в `## Removed` реестра известных падений?

## known_failures_remove
Перенести в `## Removed`

## known_failures_keep
Оставить в реестре

## auq_run_resume_question
Прошлый прогон этой задачи ({started}) не закончен. Он шёл с настройками: {settings}; уточнение владельца: {directive}. Применить их к этому запуску?

## auq_run_resume_apply
Применить

## auq_run_resume_discard
Отбросить

## info_run_resumed
Этот запуск продолжает прошлый ({started}): настройки {settings}; уточнение владельца: {directive}.

## info_directive_declined
{stage} не выполнила часть уточнения владельца: {what}

## warn_run_scale_kept
В `Task.md` задачи уже стоит `[SCALE] = [full]`, поэтому «облегчённо на этот запуск» не применено, прогон идёт на `full`. Чтобы прогнать облегчённо, убери эту строку вручную.

## warn_run_setting_refused
`{line}` — настройка на этот запуск не применена, её решают файлы задачи.

## info_task_docs_uncommitted
`{path}` вне git или игнорируется им, поэтому документы задачи не закоммичены.

## task_docs_foreign_file
В папке задачи лежит `{path}`, и это не документ задачи.

## task_docs_foreign_prompt
Как закоммитить документы задачи?

## task_docs_foreign_option_exclude
Закоммитить без этих файлов

## task_docs_foreign_option_remove
Удалить эти файлы и закоммитить

## task_docs_foreign_option_commit_all
Закоммитить всё как есть

## warn_run_file_tracked
`{path}` лежит в git, значит, это не твоё слово на этот запуск, а файл, который мог написать кто угодно: он проигнорирован. Если настройки и уточнение нужны, скажи их снова.

## codex_permissions_outdated
Настройки Spine для Codex неполные. Проверка читает только собственные настройки Spine, а не то, что этой сессии разрешено иначе, поэтому шаг из списка может пройти и без вопроса:
{items}
Задача продолжается. Чтобы записать настройки, запусти `$spine-toolkit:setup`.

## codex_perm_rules
- `.codex/rules/{file}` нет в проекте: Codex может спросить перед командами, которые он пропускает, — коммитами, сборками, тестовыми прогонами.

## codex_perm_rules_outdated
- `.codex/rules/{file}` отличается от файла установленного Spine: Codex может спросить перед командами, которые пропускает только новая версия.

## codex_perm_menu
- Флаг меню вопросов не задан: вопросы Spine придут нумерованным текстом. Ничего не останавливается.

## codex_perm_mcp
- У MCP-сервера `{server}` в конфиге нет режима одобрения: Codex может спрашивать перед его вызовами, разве что эта сессия их уже одобряет.

## codex_perm_root_missing
- `{path}` (внешние пакеты) не покрыт `writable_roots`, и эта сессия не может туда писать: перед записью туда Codex может спросить.

## codex_perm_root_unlisted
- `{path}` (внешние пакеты) не покрыт `writable_roots`, но эта сессия может туда писать: в этом запуске ничего не меняется; в сессии, запущенной из другой папки, Codex может спросить.

## codex_perm_root_stale
- `{path}` есть в `writable_roots` от Spine, но в конфиге проекта его больше нет. Ничего не останавливается.

## estimation_run_forecast
Прогноз прогона: {best}–{worst}, ворот {gates}, уверенность {confidence}.
