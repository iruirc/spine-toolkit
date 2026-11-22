# AGENTS.md — spine-toolkit

> This repo is one plugin for Claude Code and Codex: `spine-toolkit`, a task lifecycle orchestrator.
> User-project templates live in `templates/claude-md-stub/<lang>.md` and
> `templates/agents-md-stub/<lang>.md` (NOT here).
> This file configures the agent working on the plugin itself: Claude Code reads it through
> `CLAUDE.md`, Codex reads it directly.

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
  `run-forecast`, `ops-risks`, `manual-checks`, `phase-verification`, `task-documents`, `artifact-reader`, `agent-status`, `lang`,
  `docs-route`, `task-report`
- `workflows/` — one `profile-*.js` orchestration script per profile
- `workflow-src/` — `prelude.js`, the prelude every `profile-*.js` shares; edit it here, then
  `scripts/sync-workflow-prelude.sh`
- `commands/` — `/task-*`, `/setup`, `/agent-status`, `/lang`
- `conventions/` — `i18n.md`, `stage-dispatch.md`, `platform-contract.md`, `driver-contract.md`,
  `docs-components.md` and the rest
- `docs/` — `building-a-platform.md`, `building-a-driver.md`, the how-tos for platform and driver
  authors
- `templates/` — `task-md`, `claude-md-stub`, `spine-md`, `docs-map`
- `scripts/` — lints plus the test and telemetry runners
- `hooks/` — plugin hooks; the only channel that reaches existing user projects on plugin update
- `tests/foundation/` — bats suites; `tests/workflows/` — probes
- `tests/fixtures/fixture-platform/` — a complete minimal platform plugin. Core's suite binds
  against it, and it doubles as the reference implementation of the contract.
- `tests/fixtures/fixture-driver/` — the same, for the driver contract.
- `CLAUDE.md` — imports `AGENTS.md` for Claude Code

## Conventions

- `conventions/i18n.md` — the i18n convention reference.
- `conventions/stage-dispatch.md` — the stage→agent execution contract.
- `conventions/platform-contract.md` — what a platform plugin must declare to core.
- `conventions/task-scale.md` — the `lite` / `full` axis: levers, floor, ratchet.
- `conventions/docs-components.md` — the documentation-component registry format and matching.

## When working on this repo

- What to run and when, and how to wait for it: `spine-ops/WORKSPACE.md`.
- After changing a skill, validate it: `python3 ${CODEX_HOME:-~/.codex}/skills/.system/skill-creator/scripts/quick_validate.py skills/<name>`.
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
- Releasing: never bump `version` in `.claude-plugin/plugin.json` by hand; a release is
  `spine-ops: scripts/release.sh`. It moves the driver floor's three reference copies —
  `tests/fixtures/fixture-driver/.claude-plugin/plugin.json`, `conventions/driver-contract.md`,
  `docs/building-a-driver.md` — in the release commit, because
  `tests/foundation/lib/driver-contract.test.bats` holds them equal to the version: a commit that
  moves one without the others leaves the suite red.
- Changing anything the platforms vendor — `scripts/lint-manifest.sh`, `scripts/lint-i18n.sh`,
  `scripts/lint-locales.sh`, `scripts/lint-core-refs.sh`, `scripts/test-foundation.sh`,
  `conventions/i18n.md`: every platform's `forks.test.bats` pins the sha256 of the file it copied, so
  their suites turn red the moment this one lands and stay red until they re-vendor. Core cannot do
  that for them and should not try, but the release notes should say which of the six moved —
  otherwise each platform discovers it by failing.
- Changing the contract in `conventions/driver-contract.md`: update `tests/fixtures/fixture-driver/`
  in the same commit, for the same reason the platform contract carries that rule — the fixture is
  the contract's only executable copy. `docs/building-a-driver.md` is the third copy, and the one
  driver authors read first. The capability vocabulary exists in three places (convention, lint,
  fixture) and `tests/foundation/lib/driver-contract.test.bats` is what holds them together.
- This repository is public, and `spine-ops: leak-guard` checks every commit, commit message, tag
  and push for absolute local paths and the owner's real project names. Never pass `--no-verify`
  and never change `core.hooksPath`. When the check stops you, replace the data with a neutral
  placeholder (`/Users/foo`, `com.example.app`, `MyApp`) instead of working around it.

## Codex compatibility

- Keep `.claude-plugin/plugin.json` and `.codex-plugin/plugin.json` aligned on `name`, `version`,
  `author.name`, and `repository`. Never move `version` by hand: a release goes through
  `spine-ops: scripts/release.sh`, which moves it in both. Never commit the `+codex.<cachebuster>`
  suffix Codex's local reinstall flow writes into `version`.
- `skills/` is the only component the Codex manifest declares. `skills/`, `conventions/`,
  `templates/`, `scripts/` and `hooks/` are shared by Claude Code and Codex; Codex runs the hooks
  and asks to trust them again after every update (`runtimes/codex-cli.md`). `workflows/` and
  `workflow-src/` are Claude Code only; of `commands/` Codex takes only a command whose body has no
  `$ARGUMENTS`, as a skill of its own (`setup` shows up as `source-command-setup`).
- In Codex the orchestrator runs through `runtimes/codex-cli.md`, the host's half of every step
  Claude Code does with its own tools.
- A skill only the orchestrator drives carries `policy.allow_implicit_invocation: false` in its
  `skills/<name>/agents/openai.yaml` and no `default_prompt`. This prevents automatic selection but
  does not disable explicit `$skill` use.
