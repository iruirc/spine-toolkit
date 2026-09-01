# CLAUDE.md — spine-toolkit

> This repo is one Claude Code plugin: `spine-toolkit`, a task lifecycle orchestrator.
> User-project templates live in `templates/claude-md-stub/<lang>.md` (NOT here).
> This file configures Claude when it works on the plugin itself.

## Language

en

## Persona

- This repo's source-of-truth language is English.
- User-facing strings are localized via `skills/<name>/locales/<lang>.md`. Editing localized strings
  requires updating every locale file with parity.
- When changing a skill body, never inline a localized string — always reference a locale key.
- **No ecosystem knowledge lives here.** Not a language, not a framework, not a tool name. Stack
  knowledge arrives from a platform plugin through the manifest contract, and
  `tests/foundation/lib/dispatch-vocabulary.test.bats` is what holds that line.

## Repository layout

- `skills/` — `orchestrator`, `stack-detect`, `setup`, `workflow-*`, `task-*`, `feature-*`,
  `ops-checklist`, `agent-status`, `lang`
- `workflows/` — one `profile-*.js` orchestration script per profile
- `commands/` — `/task-*`, `/setup`, `/agent-status`, `/lang`
- `conventions/` — `i18n.md`, `stage-dispatch.md`, `platform-contract.md` and the rest
- `docs/` — `building-a-platform.md`, the how-to for platform authors
- `templates/` — `task-md`, `claude-md-stub`, `claude-toolkit-md`
- `scripts/` — lints plus the test and telemetry runners
- `hooks/` — plugin hooks; the only channel that reaches existing user projects on plugin update
- `tests/foundation/` — bats suites; `tests/workflows/` — probes
- `tests/fixtures/fixture-platform/` — a complete minimal platform plugin. Core's suite binds
  against it, and it doubles as the reference implementation of the contract.

## Conventions

- `conventions/i18n.md` — the i18n convention reference.
- `conventions/stage-dispatch.md` — the stage→agent execution contract.
- `conventions/platform-contract.md` — what a platform plugin must declare to core.
- `conventions/task-scale.md` — the `lite` / `full` axis: levers, floor, ratchet.

## When working on this repo

- Adding a user-facing string: add the key to BOTH `locales/en.md` AND `locales/ru.md`, then
  reference it from the skill body. Parity check
  (`diff <(grep '^## ' .../en.md | sort) <(grep '^## ' .../ru.md | sort)`) must be empty.
- Adding a skill with user-facing strings: include both locale files; the body must carry a
  `## Language Resolution` section naming the config that skill reads (the standard steps in
  `conventions/i18n.md` for a skill that runs inside a project root).
- Adding a command: bilingual `description:` line, body in English.
- Changing the contract in `conventions/platform-contract.md`: update
  `tests/fixtures/fixture-platform/` in the same commit. The fixture is the contract's only
  executable copy, and a contract that disagrees with it is worse than no contract. Check
  `docs/building-a-platform.md` too — it is the third copy, and the one platform authors read first.
