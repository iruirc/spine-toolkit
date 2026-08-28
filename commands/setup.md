---
description: "Configure spine-toolkit in an existing project / Настроить spine-toolkit в существующем проекте"
argument-hint: (no arguments)
---

Activate skill `spine-toolkit:setup`.

The skill asks which platform plugin serves this project, creates `CLAUDE-spine-toolkit.md` (toolkit-owned) from the template, inserts a single `@./CLAUDE-spine-toolkit.md` import line into your project's `CLAUDE.md` (user-owned, created if absent), asks for the prompt language, workflow mode and progress verbosity, hands the platform its own `## Stack` and `## Modules` blocks, and (optionally) creates the `Tasks/` and `Docs/` structures. Projects on the legacy single-file `CLAUDE.md` layout or on the pre-split `CLAUDE-swift-toolkit.md` name are detected and migrated. To generate a **new** project from scratch use the platform plugin's own init command.
