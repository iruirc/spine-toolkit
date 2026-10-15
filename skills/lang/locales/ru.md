# lang — ru

## error_no_toolkit_file
В текущей директории нет конфига проекта (`SPINE.md` или старого `CLAUDE-spine-toolkit.md`). Сначала запусти `/setup`.

## error_unsupported_language
Неподдерживаемый язык: `{lang}`. Поддерживаются: `en`, `ru`.

## error_config_predates_2_0
В конфиге проекта нет секции `## Project settings`: файл старше 2.0. Запусти `/setup`, чтобы мигрировать его, затем снова `/lang`.

## report_current_language
Текущий язык: `{current}`.

## report_supported_languages
Поддерживаются: `en`, `ru`. Использование: `/lang <code>`.

## report_language_changed
Язык изменён: `{old}` → `{new}`. Все последующие вызовы скиллов будут использовать `{new}`.
