# Driver Contract

A driver plugin teaches spine-toolkit one way to drive a running application: which MCP server's
tools do it, which targets that server reaches, and what it can and cannot do on each of them. All
of that is declared in a single skill — `<plugin>/skills/manifest/SKILL.md`, invoked as
`<plugin>:manifest`. Nothing else in the plugin is part of the contract.

A driver is an **adapter, not the server**. It does not install the MCP server and need not ship in
the server's repository: the server is installed the ordinary way, and the adapter only declares
what it can do. That is what lets a third party write an adapter for a server they do not own.

A project says which driver serves it in one place: the `driver:` key of `## Validation` in its
`CLAUDE-spine-toolkit.md`. The platform's manifest may name a default, and a single task overrides
both with `[DRIVER]`.

A working example is `tests/fixtures/fixture-driver/`. `scripts/lint-driver-manifest.sh
<plugin-dir>` checks a manifest against everything below that a script can check.

## The manifest skill

Frontmatter `name: manifest`, so the skill resolves as `<plugin>:manifest`. The body is **data**:
four H2 blocks and no procedure. It says so in its own first lines, so the agent that invokes it
reads the blocks instead of executing them.

`## Driver`, `## Targets` and at least one `## Capabilities: <target>` are required; `## Procedure`
is optional.

## Declare capabilities, never calls

The schemas of a connected MCP server's tools, and the server's own instructions, are already in the
context of whoever invokes them: the names, the arguments, the server's own guidance on cost. A
manifest that repeats them creates a second copy of a truth that changes on every server upgrade,
and the copy is the one nobody re-reads.

So the manifest declares what changes rarely and cannot be derived from the schemas — **which
capabilities exist** — and the call syntax is never written down anywhere, in this file or any
other. Whoever drives reads it from the schemas at the moment of use.

## `## Driver`

One row, `namespace = <prefix>[, <prefix>…]`. A prefix is the string under which the server's tools
appear in a session's tool list, so that a validator can tell whether the server is connected at all
before planning around it. Lowercase, may contain digits, hyphens and underscores, must start with a
letter.

```
## Driver

namespace = mobile, mcp-devices
```

**Several names, because the name is not yours to choose.** The prefix comes from the key the user
wrote in their MCP configuration, and that key is arbitrary — a server whose package is called one
thing is commonly registered under another, and two users register the same server differently. List
the names your server is plausibly registered under: the one its own documentation prints, the
package name, the names it used to have. The resolver takes **the first one for which tools are
actually present**, so order the list by preference.

A user who invented a name outside your list gets the "unreachable" state and a message naming every
prefix that was tried, which is enough to fix it in one edit. That is the rare case, and it is why
this is a list rather than a key the user must set in every project.

## `## Targets`

One surface per line, bare — no right-hand side. Every name must be from the surface vocabulary
below.

```
## Targets

ios-simulator
ios-device
android-emulator
```

These are the surfaces this driver can drive. The platform declares the surfaces it produces, and
the two are compatible when the sets intersect. Declare only what you genuinely reach: a surface you
list but cannot drive produces invented evidence, which is worse than declaring nothing.

The old grammar paired each target with an ecosystem. It is gone, and a row carrying `=` is rejected
rather than half-read: the ecosystem axis meant different kinds of thing on different platforms, and
matching on it gave a false negative on a platform that read the word as a language.

## `## Capabilities: <target>`

One block per target, holding whitespace-separated capability names from the vocabulary below, in
any order, across as many lines as reads well — **and nothing else. No prose.** Every token in the
block is read as a capability, so a sentence here is reported word by word. Explanations belong
above the block or in `## Procedure`. **Positive lists only: named means supported, absent means
not.**

Absence as "no" is the safe default. An unclaimed capability is deferred to a human rather than
silently skipped, which is the failure this whole contract exists to stop. There is no `partial`:
"partly supported" is indistinguishable from "unsupported" at the moment someone decides whether a
check can be driven.

Every target of `## Targets` needs a block, and every block needs a target — a target with no
capabilities declares nothing, and a block for an undeclared target is never read.

```
## Capabilities: alpha-emulator

launch stop install reset_state
ui_tree find assert screenshot logs
tap type swipe key
```

### The vocabulary

Closed, and core's. Portability is the reason: an adapter written against one platform has to be
legible to another platform's validator, and that holds only if both read one list. A name outside
it is rejected by the lint. Extending the vocabulary is a minor release of core, exactly like adding
a role.

The criterion for a row is one thing: **it changes the decision between driving a check and handing
it to a human.** Anything that only changes cost or convenience belongs in `## Procedure`.

<!-- vocabulary:start -->

| Group | Capabilities |
|---|---|
| lifecycle | `launch` `stop` `install` `reset_state` |
| observation | `ui_tree` `find` `assert` `screenshot` `video` `logs` |
| input | `tap` `type` `swipe` `gesture` `key` |
| device environment | `deeplink` `background` `permissions` `alerts` `push` `biometrics` `camera` `location` `network_conditions` `viewport` `locale` `webview` |
| quality | `a11y_audit` `visual_baseline` `performance` |
| scenarios | `record_replay` `multi_device` |

<!-- vocabulary:end -->

Four are worth spelling out, because they do not read as obvious. `reset_state` — without resetting
app state there is no way to check onboarding or a first run, a staple of hand-run lists. `webview`
— a native-only driver sees the container and not its contents, so a hybrid screen is deferred
whole. `locale` — switching the app's language, which the operational checklist already asks about
and nothing can currently answer. `alerts` separately from `permissions` — a grant is given once,
while a modal is caught in the middle of a scenario.

## Surfaces

A **surface** is a place an application runs and can be driven: a simulator, a physical device, a
desktop process, a browser page. Both sides of the contract name surfaces from one closed list, and
that shared naming is the whole of how a driver and a platform decide they fit.

A platform declares which surfaces it produces, in the `## Driver` block of its own manifest
(`conventions/platform-contract.md`). A driver declares which it can drive, in `## Targets`. They
are compatible when the two sets intersect; a driver covering none of a platform's surfaces resolves
to `incompatible`.

<!-- surfaces:start -->

| Surface | What it is |
|---|---|
| `ios-simulator` | an iOS simulator |
| `ios-device` | a physical iOS device |
| `android-emulator` | an Android emulator |
| `android-device` | a physical Android device |
| `macos` | a macOS application, as a process |
| `windows` | a Windows application, as a process |
| `linux` | a Linux application, as a process |
| `browser` | a page in a browser |

<!-- surfaces:end -->

Closed, and core's, for the same reason the capability vocabulary is: a driver written against one
platform has to be legible to another platform's validator, and that holds only if both read one
list. A name outside it is rejected by the lint. Extending the list is a minor release of core.

Eight is what the platforms that exist produce and the servers that exist drive. Televisions,
HarmonyOS and Aurora are supported by real servers today and named here by none, because no platform
produces them — declaring a surface nobody can be on is a vocabulary written against nothing. **A
driver whose server reaches more than this list simply does not declare the excess**, and that is
not an error to work around: the list grows when a platform arrives that needs it.

## `## Procedure`

Free prose, and the only place a driver speaks in its own words: how a target is selected, in what
order to reach for tools by cost, what state to leave the device in, and — if the server can report
its own capabilities at runtime — the call that asks it.

Call signatures do not go here. That is the whole of "declare capabilities, never calls", and this
block is where the temptation lands. Keep it to a screen.

## The four states

What a driver resolves to, and what the resolver does with it. The states are core's vocabulary;
acting on them belongs to whoever drives.

| State | When | Consequence |
|---|---|---|
| `ok` | resolved, tools present in the session, ecosystem matched | drive, within the declared capabilities |
| `none` | the resolution chain produced `—` on a platform inside the driver contract | defer to a human |
| `unavailable` | declared, but no tool carries its `namespace` prefix in this session | defer, naming the missing prefix |
| `incompatible` | no target's ecosystem matches the platform's | defer, naming both sides |

Deferring on `none` reaches only a platform that takes part in the driver contract: a platform whose
manifest declares no `## Driver` block drives with its own tooling exactly as it did before this
contract existed, and the state fires for it only when it has no tooling to drive a running instance
at all, which its validator announces as a declared deviation.

All three non-working states take the existing "deferred, not dropped" branch: the checks go to
`ManualChecks.md`, the matching `OpsChecklist.md` items become Pending, and **the verdict is not
lowered**. Distinguishing them is required because the user's next action differs in each: install a
driver, connect the server, pick a different one, or nothing at all.

`incompatible` deliberately does not stop the stage. Driving with a mismatched driver is invented
evidence, which is worse than a deferred check — but the build and the test run still produce theirs,
and stopping would take those away over a line in a config.

## Depending on core

One line of `plugin.json`, the object form with a semver range, exactly as a platform declares it:

```json
{
  "name": "neutral-driver",
  "dependencies": [
    { "name": "spine-toolkit", "version": ">=1.7.0 <2" }
  ]
}
```

The string form `["spine-toolkit"]` is not permitted: it travels through the host's install closure
but fills none of its constraint map, reading as a deliberate absence of any constraint while
providing none.

## Conformance

```bash
scripts/lint-driver-manifest.sh <plugin-dir>
```

checks that the required blocks are present, that `namespace` is a single well-formed row, that every
target has a capabilities block and every capabilities block a target, that no target is declared
twice, that every capability is in the vocabulary, and that `plugin.json` carries a name and an
object-form dependency on core.
