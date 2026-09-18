# orchestrator — ru

## error_no_task_id
Укажи номер задачи, например `запусти 026` / `/spine-toolkit:task-run 026`.

## error_task_not_found
Задача `{task_id}` не найдена в `Tasks/`.

## error_no_project_config
В проекте нет `CLAUDE-spine-toolkit.md` — ничто не говорит, какая платформа его обслуживает, а без платформы некому диспетчеризовать стадии. Запустите `/setup`, чтобы подключить toolkit к этому проекту (он же мигрирует конфиг, оставшийся от прежней версии toolkit), либо точку инициализации платформенного плагина, если самого проекта ещё нет. Затем запустите задачу снова.

## error_no_platform_manifest
Манифест платформы не найден. В конфиге проекта указана платформа «{plugin}», но её скилл-манифест не загрузился. Установите платформенный плагин или поправьте ## Platform в конфиге.

## fallback_profile_question
Какой профиль? (1) FEATURE (2) BUG (3) REFACTOR (4) TEST (5) REVIEW (6) EPIC (7) RESEARCH

## confirm_dispatch
Профиль: `{profile}`, режим: `{mode}`, стек: `{stack}`, старт: `{start_stage}`. Верно?

## error_research_required
Стадия `{stage}` требует `Research.md`. Запустите Research или используйте `--skip-research`.

## error_redo_no_artifact
Нечего переделывать — артефакта `{stage}` нет. Используйте `run --from {stage}`.

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

## stage_done_dialog_answer
Ответить

## stage_done_dialog_defer
Отложить (DEFERRED)

## stage_done_dialog_skip
Пропустить (вернуться позже)

## auq_stage_recovery_question
Стадия `{invalid_stage}` не входит в профиль `{profile}`. Допустимы: {profile_stages_list}. Выберите одну:

## auq_stage_override_question
Выберите другую стартовую стадию для профиля `{profile}`:

## auq_stage_recovery_recommended_suffix
(Рекомендуется)

## auq_confirm_dispatch_pick_stage
Нет, выбрать другую стадию

## error_stage_not_in_profile
`{invalid_stage}` — недопустимая стадия профиля `{profile}`. Допустимы: {profile_stages_list}.

## confirm_dispatch_yes
Да

## confirm_dispatch_cancel
Отмена

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

## dispatch_method_a
Стадии профиля {profile} идут через workflow-конвейер — последовательность держит рантайм, по агенту на стадию.

## dispatch_method_b
Тул Workflow в этой сессии недоступен, поэтому профиль {profile} идёт через свой скилл. Стадии и агенты те же, но последовательность держит ассистент, а не код.

## stage_error_prompt
Стадия {stage} вернула ошибку: {reason}. Диапазон останавливается здесь — следующая стадия строила бы работу на незавершённой.

## stage_error_option_retry
Повторить {stage}

## stage_error_option_stop
Остановиться и вернуть управление

## progress_open_header
{profile} {task_id} · {method} · {start} → {end} · Progress: {progress}

## progress_open_live_hint
Живой ход — вьюха /workflows. Каждый запуск ниже — там отдельная строка `{workflow}`, новые сверху.

## progress_open_live_ticker_note
Панель с токенами — запусти `bash "{script}" --session {session}` в соседней панели терминала.

## progress_open_method_b_live
В Method B хост сам рисует каждый вызов агента; панель добавляет к нему цифры расхода, которых хост не показывает.

## progress_open_settings
Настройки:

## progress_open_settings_rest
ещё {count} по умолчанию

## progress_dispatch
{range} → новый запуск `{workflow}`, верхняя строка в /workflows.

## progress_stage_report
{stage} — {agent}

## progress_stage_artifact
Артефакт: {path}

## progress_stage_verdict
Вердикт: {verdict}

## progress_stage_metrics
{tuning} · {out} out · {ctx} ctx · {tools} tools · {elapsed}

## progress_run_elapsed
Прогон занял {elapsed}.

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
`{line}` в `## Budgets` файла `CLAUDE-spine-toolkit.md` не называет артефакт, который знает линт бюджета, или потолок не целое положительное число, поэтому остаётся значение по умолчанию. Артефакты: `Task.md`, `Reproduce.md`, `Plan.md`, `Validation.md`, `Review.md` и `Done.md`.

## warn_walkthrough_pre_depth
`on` — значение, оставшееся от времён до оси глубины, поэтому этот прогон пишет `Walkthrough.md` на глубине `deep`: словарь терминов, порядок коммитов и раздел на каждый коммит, тогда как `on` давал сводку и журнал по буллету на коммит. Чтобы сохранить прежнюю форму, напишите `brief` — в `[WALKTHROUGH]` в `Task.md` или в `walkthrough` в разделе `## Reporting` файла `CLAUDE-spine-toolkit.md`.

## warn_walkthrough_unrecognised
`{value}` — не одна из трёх глубин walkthrough, поэтому запись пропущена и решает следующий источник: `walkthrough` в разделе `## Reporting` проекта, если он что-то называет, иначе `deep`. Глубины такие: `brief`, `deep` и `off` — исправьте значение в `[WALKTHROUGH]` в `Task.md` или в `walkthrough` в разделе `## Reporting` файла `CLAUDE-spine-toolkit.md`. Глубину, до которой этот прогон в итоге дорезолвил, называет колонка настроек выше.

## warn_tuning_unrecognised
`{entry}` в {source} — не ключ и значение, которые этот прогон умеет применить, поэтому запись пропущена и действует следующая настройка. Ключи моделей — `light` и восемь ролей, со значениями `opus`, `sonnet`, `haiku`, `fable` или `session`; ключи effort — восемь ролей, со значениями `low`, `medium`, `high`, `xhigh`, `max` или `session`.

## warn_effort_method_b
Effort, заданный для {roles}, в этом прогоне не действует: профиль идёт через свой скилл, а вызов агента из скилла не передаёт effort, поэтому все стадии работают на effort этой сессии. Выбор моделей по-прежнему действует.

## warn_driver_plugin_missing
Драйвер `{driver}` разрешён для этого прогона, но его манифест не резолвится — плагин не
установлен. Валидация отдаст свои UI-проверки вам вместо того, чтобы гнать приложение. Поставьте
плагин или напишите `driver: —` в `## Validation`, если так и задумано.

## warn_driver_server_missing
Драйвер `{driver}` установлен, но в этой сессии нет ни одного инструмента под объявленными им
префиксами ({namespaces}) — либо его MCP-сервер не подключён, либо зарегистрирован под другим именем.
Валидация отдаст свои UI-проверки вам вместо того, чтобы гнать приложение. Запустите сервер,
зарегистрируйте его под одним из этих имён или напишите `driver: —` в `## Validation`, если так и
задумано.
