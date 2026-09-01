---
name: manifest
description: Platform manifest for the fixture platform. Data, not instructions — the five tables spine-toolkit reads to bind roles, axes, heuristics, topics and entrypoints.
---

# Fixture Platform Manifest

> This skill is **data**, not instructions. spine-toolkit reads the five tables below by
> invoking this skill; there is no procedure here to follow.

This is the minimal manifest a `*-platform` plugin declares to spine-toolkit, kept as a fixture:
spine-toolkit's `fixture-platform.test.bats` runs against it directly, and its `lint-manifest.sh`
validates copies of it. (Filenames, not paths: a directory-prefixed path here would resolve under
THIS plugin's root and find nothing — the rule every reference below follows.) Treat every value below as load-bearing —
use it as a template for a real platform's manifest, not as a stub to satisfy a grep.

## Roles

Canonical core role → `plugin:agent`. `role[axis=value]` fans one role out across an axis value,
demonstrated below on `developer` the way a platform serving two UI stacks splits it into one
variant each. The bare `developer` row below it is the fallback for a project where `widget` never
resolves; without it the role falls through to the em dash on every such task. `—` declares a role absent — an expected deviation spine-toolkit dispatches around (the
stage-dispatch convention in `spine-toolkit`), not a gap to fill in later.

architect               = fixture-platform:fixture-architect
developer[widget=alpha] = fixture-platform:fixture-developer
developer[widget=beta]  = fixture-platform:fixture-architect
developer               = fixture-platform:fixture-developer
tester                  = fixture-platform:fixture-developer
reviewer                = fixture-platform:fixture-architect
refactorer              = fixture-platform:fixture-developer
validator               = —
security                = —
diagnostics             = —
init                    = —

## Axes

`ecosystem` is the one axis every platform must declare, and the one whose meaning spine-toolkit
fixes: it names the ecosystem this platform serves. Declared and reserved, not yet consumed; a
project names the plugin that serves it outright, in the `## Platform` block of its config.
Every other axis, and its allowed values, is the platform's own choice; `widget` here is the axis
the `developer` fan-out above and the heuristics below key on. (Named `widget`, not `lang`: core's
prompt-language skill is `lang` and resolves en/ru — an unrelated concept that would share the
name, and this fixture should not teach a name that collides with it.)

ecosystem = fixture
widget    = alpha, beta

## Heuristics

How `stack-detect` resolves axis values from repo signals: a `path` pattern flags an axis as
relevant, an `import` literal pins one specific value.

path:   `src/**` with no `alpha` or `beta` import → widget
import: `alpha`                                    → widget=alpha
import: `beta`                                     → widget=beta

## Topics

Topic → comma-separated, backtick-quoted, bare skill names that cover it (no `plugin:` prefix —
a manifest is read one platform at a time, so its own skills need no namespacing), or `—` if this
platform has none. Consumed by spine-toolkit's methodology skills, which name a topic and resolve
it here. Every row here is a topic; a skill spine-toolkit calls by name lives in `## Entrypoints`
instead.

state management → `store-flux`, `store-atoms`
navigation       → `route-table`
networking       → `fetch-client`
persistence      → —
concurrency      → `task-scheduler`
deep links       → —

## Entrypoints

Skills spine-toolkit invokes by name, or `—` for one this platform does not provide. This fixture
ships no setup skill, and the em dash is the point: spine-toolkit writes the config's core blocks,
leaves `## Stack` unset, and the orchestrator asks per axis on the first task that needs one.

setup = —
