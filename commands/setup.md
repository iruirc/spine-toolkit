---
description: "Configure spine-toolkit in an existing project / Настроить spine-toolkit в существующем проекте"
argument-hint: (no arguments)
---

Activate skill `spine-toolkit:setup`.

The skill asks which platform plugin serves this project, creates `CLAUDE-spine-toolkit.md` (toolkit-owned) from the template, inserts a single `@./CLAUDE-spine-toolkit.md` import line into your project's `CLAUDE.md` (user-owned, created if absent), asks for the prompt language, workflow mode and progress verbosity, hands the platform its own `## Stack` and `## Modules` blocks, and (optionally) creates the `Tasks/` structure and offers `DocsMap.md`, the documentation registry. Projects on the legacy single-file `CLAUDE.md` layout, on the pre-split `CLAUDE-swift-toolkit.md` name, or on the 1.x block format are detected and migrated; the last of the three is rewritten without asking, since the file itself answers every question. To generate a **new** project from scratch use the platform plugin's own init command.
