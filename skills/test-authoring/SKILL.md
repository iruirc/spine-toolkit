---
name: test-authoring
description: "Use before writing test code or reading a test run's failures — as the tester, as a developer adding a regression test, as diagnostics sketching one, or as the skill that initializes a project. Decides which test framework that file is written in, from the file being extended, the surface under test and the project's stack. The syntax of each framework belongs to the platform and is resolved through topic **testing**."
---

# Test Authoring

A project declares which test framework it uses. A test written in another one is noise at best; at
worst it is invisible, because a runner collects only what it recognizes, and a suite with no test
in it is green. This skill decides the framework. What that framework looks like is the platform's
to say.

## Who follows it

- **tester** — every file it writes.
- **developer** — the regression test it adds with a fix.
- **diagnostics** — the test it sketches in its report.
- **init** — the first test of a new project, and the build setup that runs it.
- **validator** — from the other end: it reads failures of every value the axis allows, because one
  target can hold two frameworks at once.

## Choosing the framework

Ask in this order and stop at the first answer:

1. **Extending a test file that exists** → the framework that file already uses.
   Never mix two frameworks in one file.
2. **The surface decides** → where a surface can only be driven by one framework, that framework
   wins over anything the stack says. Which surfaces those are is the platform's list, and it lives
   with the syntax (below).
3. **A new file** → the value the project gives the test-framework axis for that module: the
   `## Modules` line of `CLAUDE-spine-toolkit.md` where one names the module, else `## Stack`.
4. **Nothing resolved** → the framework of the tests nearest the code under test.
   Never introduce a second framework into a target on your own initiative. Where there are no
   tests to follow, choose, and say in your report which framework you chose and why, so review
   sees the choice.

The choice is a name the project already uses, never a preference of yours: a framework you consider
better is a proposal for the user, not a file you write.

## Where the syntax comes from

This skill names no framework, and neither does anything else in core. To turn the chosen value into
code: invoke `<platform>:manifest` — `<platform>` is the first non-empty line of the `## Platform`
block of `CLAUDE-spine-toolkit.md` — and read the manifest `## Topics` row for **testing**, the way
`conventions/platform-contract.md` describes. The skill that row names carries one section per value
of the axis: how a test is declared so the runner collects it, how it asserts, its lifecycle hooks,
parameterization, asynchronous tests, how a failure reads in the runner's output, and what a project
needs to run that framework at all. It also carries the list of surfaces rule 2 asks for.

A row that is an em dash, or no row at all, means the platform covers this with no skill of its own:
follow the project's existing tests and say so in your report.

## Not this skill's business

- **Whether a test is needed at all.** That is `[NEED_TEST]` in the task contract.
- **How much a phase verifies before it commits.** That is `spine-toolkit:phase-verification`.
- **What a good test is** — structure, naming, what may be replaced by a double. Today that lives
  with each platform's tester.
