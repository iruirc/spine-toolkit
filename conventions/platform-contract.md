# Platform Contract

A platform plugin teaches spine-toolkit one ecosystem: which agent owns each role, which stack axes
exist, how to read them off a repository, which of its skills cover which topic, and which skill core
calls to configure a project. All of that is
declared in a single skill — `<plugin>/skills/manifest/SKILL.md`, invoked as
`<plugin>:manifest`. Nothing else in the plugin is part of the contract.

A project says which platform serves it in one place: the `## Platform` block of its
`CLAUDE-spine-toolkit.md` holds the plugin's name, and that name is the whole selection mechanism.
Nothing is inferred from the repository and nothing is auto-discovered while a task runs.

A working example is `core/tests/fixtures/fixture-platform/` — the fixture core's own tests bind
against, and the thing to copy when writing a new platform. `core/scripts/lint-manifest.sh
<plugin-dir>` checks a manifest against everything below that a script can check.

## The manifest skill

Frontmatter `name: manifest`, so the skill resolves as `<plugin>:manifest`. Core reads it by
**invoking it** — the ordinary skill mechanism, and the only channel between the two plugins. Core
never reads the host's plugin cache from disk (host internals, not a public contract), and
`plugin.json`'s `metadata` field is not an alternative: the host preserves it but does not hand it
back.

The body is **data**: five H2 tables and no procedure. It says so in its own first lines, so the
agent that invokes it reads the tables instead of executing them. Prose between tables is for
humans; only the rows are parsed.

## `## Roles`

One row per role, `role = plugin:agent`, left-hand sides drawn from core's role vocabulary — exactly
these nine:

```
architect  developer  tester  reviewer  refactorer  validator  security  diagnostics  init
```

All nine must appear. A platform that has no agent for a role writes an em dash:

```
validator = —
```

That is a **declared absence**, not a hole to fill in later: core dispatches around it through the
"Declared deviation" rule in `core/conventions/stage-dispatch.md` — the stage runs in the main
context and says so in its first message. A row with an empty right-hand side is neither, and the
lint rejects it.

A role may fan out across an axis with `role[axis=value]`, once per value:

```
developer[ecosystem=jvm]     = kotlin-platform:kotlin-backend-developer
developer[ecosystem=android] = kotlin-platform:kotlin-mobile-developer
```

Core picks one row per role: an axis-qualified row whose value matches the project's resolved value
for that axis, else the bare `role =` row, else the em dash. Write the rows so that **at most one
axis-qualified row per role can match any one resolved stack** — where two could match, core takes
the first in file order and the manifest is simply ambiguous. A fanned-out role usually also wants a
bare row as the fallback for a project where that axis never resolved.

The right-hand side is always namespaced (`plugin:agent`), because the map it feeds travels into
subagent dispatch verbatim, and the agent it names must exist as `<plugin>/agents/<name>.md` —
`<name>` being the part after the colon.

What core makes of the table: it resolves one agent per role before any stage starts, and hands the
finished map to every executor. An em dash survives that resolution as itself, not as a missing key:

```
agents={architect: kotlin-platform:kotlin-architect, …, validator: —, security: —}
```

in the newline-separated encoding, and `{"validator": "—"}` in the JSON one. Either way it is a
value the executor tests for before dispatching, so the stage still runs and still announces
itself — an absent role degrades loudly by construction.

## `## Axes`

The catalog of stack axes and their allowed values, `axis = v1, v2, v3`. This is the source of truth
for both `stack-detect` and the option list the orchestrator offers the user when an axis cannot be
resolved from the repository. Values are proper nouns and are **never localized**: that option list
is rendered in the user's language, and an ordinary-word value like `manual` or `Factory`, translated
into it, matches no catalog entry when the answer comes back.

`ecosystem` is the one axis core requires every platform to declare, and the only axis whose meaning
core fixes: it names the ecosystem this platform serves (`apple`, `android`, `jvm`). Declare it —
but know that **nothing in core reads its value today**. A project names its platform outright in
the config's `## Platform` block; `ecosystem` is there for the parts that will have to reason about
ecosystems rather than plugin names, such as installation-time discovery or a repository holding two
of them. Reserved, not load-bearing: `stack-detect` excludes it from detection, so no `## Heuristics`
row should try to pin it.

Every other axis and every value is the platform's own choice; core recommends but does not impose
`ui`, `async`, `di`, `architecture`, `baseline`, `tests`.

## `## Heuristics`

How axis values are read off a repository. A `path:` row flags one or more axes as relevant to the
files in scope; an `import:`, `token:` or `file:` row pins one specific value — and what it pins must
be a value the axis lists under `## Axes`, since that is what `stack-detect` returns. A signal whose
value has to be computed (a deployment target read out of a build file) pins nothing: write it as a
flagging row and let the chain or the user supply the catalog value.

```
import: `SwiftUI` only (no UIKit/AppKit) → ui=SwiftUI
path:   `Views/`, `*View.swift`          → ui, architecture
```

Write the rows so that a repository signal matches **exactly one** of them — self-contained
conditions, not a list that only behaves if it is read top-down. Nothing in the contract states an
evaluation order, and a reader who assumes one will be wrong half the time.

A `path:` row may qualify one of its axes — `architecture (+ ui if a view binding is present)`. The
add-on flags its axis only for a file the same scan shows satisfies the condition, so write a
condition that scan can see: `stack-detect` corroborates it rather than taking it on trust.

## `## Topics`

Topic name → the platform's skills that cover it, as comma-separated backtick-quoted **bare** skill
names (a manifest is read one platform at a time, so its own skills need no `plugin:` prefix), or an
em dash for a topic this platform does not cover:

```
state management → `arch-mvvm`, `arch-tca`
persistence      → —
```

Core's `feature-landscape` and `feature-requirements` consume this table; the topic vocabulary is
open, and a platform names the topics it actually has. Every row is a topic and nothing else: a
skill core invokes by name belongs in `## Entrypoints`, not here, so a consumer may iterate these
rows generically without special-casing one of them.

## `## Entrypoints`

The skills core invokes by name, `entrypoint = ` a backtick-quoted **bare** skill name of this
plugin, or an em dash for one it does not provide:

```
setup = `swift-setup`
```

One entrypoint is defined today. **`setup`** names the platform half of installation: core's `setup`
writes the config and every block that is core's, then hands this skill the two that are not —
`## Stack` and `## Modules`, whose content is the platform's `## Axes` and nothing core can know.

`—`, or no `setup` row, is a supported shape, not an error: core writes the core blocks, leaves
`## Stack` unset, and the orchestrator's per-axis question fills it one task at a time.

The table is separate from `## Roles` because an entrypoint is a **skill**, invoked once at install
time by core itself, where a role is an **agent** dispatched per stage on the user's behalf; and
separate from `## Topics` because a topic is a reading list a consumer iterates, where an entrypoint
is a single name core calls. It exists so the binding needs neither a naming convention (a skill
named `setup` in the platform would collide with core's own in every natural-language trigger) nor a
reserved magic string inside another table.

## Conformance

```bash
core/scripts/lint-manifest.sh <plugin-dir>
```

checks that all five tables are present, that the Roles rows cover the nine-role vocabulary and no
more, that every named agent has a file in the plugin, that no role is mapped to nothing, and that a
`## Entrypoints` skill other than `—` exists in the plugin. What it deliberately does not check:
whether the skills named under `## Topics` exist — the reference fixture names placeholders on
purpose, so that check belongs to each real platform's own test suite. `## Entrypoints` is checked
and `## Topics` is not because core calls the one by name and merely lists the other: a typo in an
entrypoint is discovered at install time, after the config is already on disk, and is
indistinguishable there from the legitimate `—`.
