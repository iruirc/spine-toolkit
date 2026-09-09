# Building a Driver Plugin

A driver plugin tells spine-toolkit how a running application can be driven during Validation: which
MCP server's tools do it, which targets they reach, and what each target supports. It is an
**adapter** — it does not ship, install, or wrap the server. That is what lets you write one for a
server you do not own.

If you maintain a platform plugin, read `docs/building-a-platform.md` instead; the two are separate
categories and a plugin is one or the other.

## 1. What you are declaring, and what you are not

You declare **capabilities**: whether the driver can launch the app, read a UI tree, tap, deliver a
push, switch the locale. You do **not** declare how any of that is called. The tool schemas of a
connected MCP server are already in the context of whoever drives, along with the server's own
instructions; writing them down here creates a second copy that goes stale at the server's next
release, and the copy is the one nobody re-reads.

This is not hypothetical. The contract exists because a platform's validator carried a table of six
call names, every one of which had stopped existing when the server moved to an action-based API,
and nothing noticed for months.

## 2. Copy the fixture

```bash
cp -R <spine-toolkit>/tests/fixtures/fixture-driver my-driver
```

`tests/fixtures/fixture-driver/` is the contract's executable copy: two files, both load-bearing.
Everything below is editing them.

## 3. `plugin.json`

```json
{
  "name": "my-driver",
  "description": "…",
  "version": "1.0.0",
  "dependencies": [
    { "name": "spine-toolkit", "version": ">=1.7.1 <2" }
  ]
}
```

Object form, never `["spine-toolkit"]` — the string form travels through the host's install closure
while filling none of its constraint map, so it reads as a deliberate absence of any constraint. The
upper bound is the next major: a major release of core takes every dependent plugin off the loader
at once. The lower bound is the oldest core whose grammar you have actually linted against; keep the
current core unless you have checked an older one, because too high refuses to load and says why,
while too low loads and misreads you.

## 4. `## Driver` — the prefixes

```
namespace = mine, my-package
```

The prefixes the server's tools carry in a session's tool list. **Give more than one, and here is
why:** the prefix comes from the key the user typed into their MCP configuration, and that key is
theirs to choose. A server whose package is named one thing is routinely registered under another —
one of the two servers this contract was designed against renamed its package and kept printing the
old key in its own install instructions. List the name your documentation prints, the package name,
and any name the server used to have. The resolver takes the first prefix with tools actually
present, so order the list by preference.

A user who invented a name outside your list gets a message naming every prefix that was tried.
That is a one-edit fix for them and no work for you — which is why this is a list rather than a
setting every project has to carry.

## 5. `## Targets` — which surfaces you drive

```
ios-simulator
android-emulator
```

Bare names, one per line, from core's surface vocabulary — the closed list in
`conventions/driver-contract.md`. A **surface** is a place an application runs and can be driven: a
simulator, a physical device, a desktop process, a browser page.

The platform declares the surfaces its projects run on; you declare the ones you drive; you fit when
the two sets intersect. There is no axis to match against any more — that mechanism meant a
different thing on every platform, and it gave a false negative wherever an author read it as
naming a language.

**Declare only what you genuinely reach.** A surface you list but cannot drive produces invented
evidence, which is worse than declaring nothing.

**If your server reaches surfaces the vocabulary has no name for** — a television, another mobile
OS — you simply do not declare them, and that is not an error to work around. The list grows by a
minor release of core when a platform arrives that produces them.

## 6. `## Capabilities: <target>` — one block per target

Positive lists: named means supported, absent means not. Absence is the safe default — an unclaimed
capability is handed to a human, never silently skipped.

**Capability names and nothing else in the block.** The lint reads every token under the heading as
a capability, so a sentence there is reported word by word; explanations go above the block or into
`## Procedure`.

**Declare per target, honestly.** This is where most of the value is. A simulator that cannot deliver
a push and a device that can are the same driver with two different answers, and a single flat list
would be a lie in half its rows. Support depth varying by backend is the normal case, not an edge
one.

What you declare is what your server can do **when fully installed**. If it ships in parts — one of
the two servers here has a modular edition whose platforms default to none — a surface you declare
may be absent on a given machine, and that is expected. If your server can report its own
composition at run time, name that call in `## Procedure`: the answer may narrow what your table
says and may never widen it.

The vocabulary is closed and it is core's — see `conventions/driver-contract.md`. A name outside it
is rejected by the lint. If your server does something the vocabulary has no row for, that is either
something that changes cost rather than the drive-or-defer decision (it goes in `## Procedure`), or a
genuine gap in the vocabulary (open an issue against core; extending it is a minor release).

## 7. `## Procedure` — your quirks, in a screen

How a target gets selected, what order to reach for tools by cost, what state to leave the device
in, and the call that reports capabilities at run time if your server has one. Keep it to a screen.
No call signatures — that is the one rule of this file.

## 8. Check it

```bash
<spine-toolkit>/scripts/lint-driver-manifest.sh my-driver
```

Clean output is `driver manifest OK: my-driver`. The lint checks the required blocks, one `namespace`
row of well-formed names, `## Targets` rows that are bare surfaces from core's vocabulary (a row
carrying `=` is the retired grammar and is rejected), targets and capability blocks covering each
other exactly, capabilities inside the vocabulary, and the dependency form.

Copy the lint into your own repo and run it in CI: plugins share no code, so update both or neither,
and record the source in a header comment the way platform authors do.

## 9. Try it

In a project already configured for spine-toolkit, set the key:

```
## Validation

driver: my-driver
```

Then run a task with a Validation stage. If the plugin is not installed, or its server is not
connected, the orchestrator says so before the run starts rather than after the implementing stage.

## 10. Failure modes worth knowing

- **Declared but not connected.** The manifest promises; the session has no tools under any of your
  prefixes. The run continues, the UI checks go to a human, and the digest names every prefix that
  was tried. This is not a failed validation — it is a broken setup, and it says so.
- **No shared surface.** None of your `## Targets` is a surface the platform produces. Nothing is
  driven, and the build and tests still run. Both sets are named in the message, so the mismatch is
  visible rather than mysterious.
- **Surface present in your table, absent on the machine.** The server is connected, but the module
  for that surface is not installed. Same handling: the check goes to a human, and the message names
  the surface.
- **Over-declaring.** The expensive one. A capability you list but cannot deliver turns a check that
  would have been handed to a human into a check nobody performed.
