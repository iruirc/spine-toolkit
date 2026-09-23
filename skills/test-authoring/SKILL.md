---
name: test-authoring
description: "Use before writing test code, before judging tests in review, or when reading a test run's failures — as the tester, as a developer adding a regression test, as diagnostics sketching one, as the skill that initializes a project, or as the reviewer. Decides which test framework that file is written in, and what makes the test worth keeping: its form, its name, its isolation, and which collaborators may be replaced by a double. The syntax of each framework belongs to the platform and is resolved through topic **testing**."
---

# Test Authoring

A project declares which test framework it uses. A test written in another one is noise at best; at
worst it is invisible, because a runner collects only what it recognizes, and a suite with no test
in it is green. This skill decides the framework, and says what the test written in it has to be: a
form, a name, an isolation rule, and a boundary past which a collaborator may be replaced by a double.
What that framework looks like is the platform's to say.

## Who follows it

- **tester** — every file it writes.
- **developer** — the regression test it adds with a fix.
- **diagnostics** — the test it sketches in its report.
- **init** — the first test of a new project, and the build setup that runs it.
- **validator** — from the other end: it reads failures of every value the axis allows, because one
  target can hold two frameworks at once.
- **reviewer** — the tests a task added, judged by `## Review` below.

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

## What a good test is

The rules below hold whatever the framework. None of them is a matter of style: each names a way a
test stops being evidence.

- **Arrange → Act → Assert.** Three parts, in that order, and a reader can point at each one. A test
  that interleaves them hides which line is the claim.
- **The name says what broke.** `methodName_condition_expectedResult` — the unit, the condition it is
  under, the outcome expected of it. How that name is attached to a test the runner will actually
  collect differs per framework and costs the whole test silently when it is wrong: that is
  `### Declaration` in the skill the **testing** row names.
- **One behaviour per test.** Arrange only what this test needs. Assert one thing, in as many calls as
  that one thing takes. A test that asserts five behaviours reports the first failure and hides four.
- **Isolated.** No test depends on another, on the order they run in, or on state one left behind.
  What resets that state is the framework's hooks — `### Lifecycle` in the same skill — and a hook
  that arranges more than the test in front of it needs is the shared mega-setup the rule above
  forbids, moved one level up.
- **Written to fail.** A test exists to catch a change in behaviour. One written to go green, or with
  its expectation copied from whatever the code returns today, records the bug instead of catching it.

## Test doubles

Five words for five things. One word for all of them is how a test ends up asserting the double's own
configuration.

| Double | What it is | When it is the right one |
|---|---|---|
| dummy | a value passed only to satisfy a signature | the parameter takes no part in the behaviour |
| stub | returns answers fixed in advance | the test needs an input that comes from outside |
| spy | records the calls it received | what is verified is that the call happened |
| mock | a spy with its expected calls declared up front | the interaction itself is the behaviour |
| fake | a working implementation, simplified | the boundary is used often and must stay coherent |

**Choosing.** Verifying state — what the code returned, stored or emitted — takes a stub or a fake.
Verifying calls — that something was invoked, how often, with what — takes a spy or a mock, and ties
the test to how the code works rather than to what it does. Prefer state: a call-verifying test breaks
on every refactor and catches nothing in exchange. The exception is where the call *is* the behaviour
— a message sent, a payment charged, a file deleted — and then verifying it is the point.

**Where a double belongs.** On a boundary the test cannot cross: network, filesystem, database, clock,
randomness, system APIs, the dependency container. Which of those this ecosystem has, and what stands
in for each, is the platform's to say.

**Where it never belongs.** The code under test, the helpers it calls, and value transformations.
A double there leaves a test that passes over a behaviour nobody ran.

## Before you deliver

- Every test is idempotent: a hundred runs, alone or inside the suite, give the same result.
- Arrange, Act and Assert are visible in every test.
- Doubles stand on boundaries only, never on the behaviour under test.
- Empty, boundary and error inputs are covered, not the happy path alone.
- Every test would fail if the behaviour under it broke. If you cannot say how a test fails, it is not
  a test yet.

## When the task owes no test

With `need_test=false` the task adds no test: no test file and no test case. The
existing suite runs as usual, at every phase's verification and at Validation. An existing test may
be edited only when the change alters the very behaviour it asserts; the phase
names that test and the reason in its summary. REFACTOR keeps its stricter rule: there any edited
test is a finding. Such an edit belongs in the phase that changes the behaviour, never in a phase
of its own — a phase holding only that edit reads as a test phase and stops the run.

## Review

Findings read out of the tests a task added or changed — not out of the suite around them:

1. an assertion that cannot fail: a tautology, a literal compared with itself, or a value the double
   beneath it was configured to return;
2. a double standing in for the behaviour under test, where the real thing could have been called;
3. state crossing between tests: a shared mutable fixture, a dependency on order, a hook that does not
   undo what the test wrote;
4. behaviour in the diff that no test names, or a happy path alone where that behaviour has errors and
   boundaries;
5. a test asserting more than one behaviour, or a name that does not say what broke.

**A finding here may block.** The neighbouring skills end their `## Review` with "none of them
blocks", because they judge how a plan was written after Validation has already proven the code. This
section judges the artifact: a test that cannot fail is a defect in what was delivered, and it belongs
in `blocking_findings`.

Where `need_test` was false, a test the task added is a blocking finding; an edit to an existing
test whose phase named no reason for it is a finding — see `## When the task owes no test`.
Whether a test was owed is the task contract's decision, not review's.

## Not this skill's business

- **Whether a test is needed at all.** That is `need_test` in the task contract; what `false` then
  forbids is `## When the task owes no test`.
- **How much a phase verifies before it commits.** That is `spine-toolkit:phase-verification`.
