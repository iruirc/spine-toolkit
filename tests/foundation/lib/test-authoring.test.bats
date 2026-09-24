#!/usr/bin/env bats
# Which framework a test is written in was nobody's decision: a tester wrote the one
# framework its own text knew, and a name the runner never collects leaves a suite green
# with no test in it. The rule is core's because four kinds of agent follow it; the
# framework names are not, and the second test here is what keeps them out.

setup() {
  ROOT="$(cd -- "$(dirname -- "$BATS_TEST_FILENAME")/../../.." && pwd)"
  SKILL="$ROOT/skills/test-authoring/SKILL.md"
}

# A section's body, heading excluded, up to the next H2.
section() { # $1 = file, $2 = heading text without "## "
  awk -v h="## $2" '$0==h{f=1;next} f&&/^## /{exit} f' "$1"
}

@test "the skill exists and resolves under its own name" {
  [ -f "$SKILL" ] || { echo "no skills/test-authoring/SKILL.md"; return 1; }
  grep -q '^name: test-authoring$' "$SKILL" || { echo "frontmatter name is not test-authoring"; return 1; }
}

@test "the skill names no test framework" {
  hits="$(grep -ioE '\b(xctest|swift testing|quick|nimble|junit|kotest|mockk|mockito|jest|vitest|pytest|rspec)\b' "$SKILL" | sort -u | tr '\n' ' ')"
  [ -z "$hits" ] || { echo "core names a framework: $hits"; return 1; }
}

@test "the skill asks its questions in order and stops at the first answer" {
  pick="$(section "$SKILL" 'Choosing the framework')"
  [ -n "$pick" ] || { echo "no ## Choosing the framework"; return 1; }
  grep -qF 'stop at the first answer' <<<"$pick" || { echo "the questions are not ordered"; return 1; }
  for rule in 'a test file that exists' 'The surface decides' 'A new file' 'Nothing resolved'; do
    grep -qF "$rule" <<<"$pick" || { echo "## Choosing the framework has no rule '$rule'"; return 1; }
  done
  grep -qF '`## Modules`' <<<"$pick" || { echo "a module's own value does not win over the project's"; return 1; }
}

@test "the skill forbids mixing frameworks and inventing a second one" {
  pick="$(section "$SKILL" 'Choosing the framework')"
  grep -qF 'Never mix two frameworks in one file' <<<"$pick" || { echo "one file may hold two frameworks"; return 1; }
  grep -qF 'Never introduce a second framework into a target' <<<"$pick" \
    || { echo "an unresolved axis lets an agent bring in a framework of its own"; return 1; }
}

@test "the skill binds every agent that writes test code, the validator, and the reviewer" {
  who="$(section "$SKILL" 'Who follows it')"
  [ -n "$who" ] || { echo "no ## Who follows it"; return 1; }
  for role in tester developer diagnostics init validator reviewer; do
    grep -qF "$role" <<<"$who" || { echo "## Who follows it does not bind $role"; return 1; }
  done
}

@test "the skill sends syntax to the platform through topic testing" {
  grep -qF '**testing**' "$SKILL" || { echo "the skill does not name the topic"; return 1; }
  grep -qF 'manifest `## Topics`' "$SKILL" || { echo "no path from the topic to a skill"; return 1; }
  grep -qF 'conventions/platform-contract.md' "$SKILL" || { echo "the skill does not point at the contract"; return 1; }
}

@test "the contract fixes what the tests axis means when a platform declares it" {
  contract="$ROOT/conventions/platform-contract.md"
  grep -qF 'its values name the frameworks a project'"'"'s tests are written in' "$contract" \
    || { echo "the axis is still recommended with no fixed meaning"; return 1; }
}

@test "the topic vocabulary core publishes includes testing" {
  contract="$ROOT/conventions/platform-contract.md"
  topics="$(sed -n '/^```topics$/,/^```$/p' "$contract" | sed '1d;$d')"
  [ -n "$topics" ] || { echo "the topics block is gone"; return 1; }
  grep -qx 'testing' <<<"$topics" || { echo "no testing row in the published vocabulary"; return 1; }
}

@test "the contract says what the testing row must carry" {
  contract="$ROOT/conventions/platform-contract.md"
  grep -qF 'one section per value of the `tests` axis' "$contract" \
    || { echo "the testing row has no required shape"; return 1; }
  grep -qF 'the surfaces that force a framework' "$contract" \
    || { echo "the forced surfaces are not asked for"; return 1; }
}

@test "the fixture platform answers the testing topic" {
  fix="$ROOT/tests/fixtures/fixture-platform/skills/manifest/SKILL.md"
  grep -qE '^testing[[:space:]]*→[[:space:]]*`[a-z-]+`$' "$fix" \
    || { echo "the reference manifest has no testing row"; return 1; }
}

@test "the platform guide publishes the same topic vocabulary as the contract" {
  contract="$ROOT/conventions/platform-contract.md"
  guide="$ROOT/docs/building-a-platform.md"
  missing=""
  while IFS= read -r topic; do
    [ -n "$topic" ] || continue
    grep -qE "^$topic[[:space:]]+→" "$guide" || missing="$missing$topic, "
  done < <(sed -n '/^```topics$/,/^```$/p' "$contract" | sed '1d;$d')
  [ -z "$missing" ] || { echo "topics the guide never shows: ${missing%, }"; return 1; }
}

@test "the skill carries the neutral discipline" {
  d="$(section "$SKILL" 'What a good test is')"
  [ -n "$d" ] || { echo "no ## What a good test is"; return 1; }
  for rule in 'Arrange → Act → Assert' 'methodName_condition_expectedResult' \
              'One behaviour per test' 'Isolated' 'Written to fail'; do
    grep -qF "$rule" <<<"$d" || { echo "the discipline lost '$rule'"; return 1; }
  done
}

@test "the skill names the five doubles and how to choose between them" {
  d="$(section "$SKILL" 'Test doubles')"
  [ -n "$d" ] || { echo "no ## Test doubles"; return 1; }
  for w in dummy stub spy mock fake; do
    grep -qF "| $w |" <<<"$d" || { echo "## Test doubles has no row for $w"; return 1; }
  done
  grep -qF 'Verifying state' <<<"$d" || { echo "no rule for choosing between them"; return 1; }
  grep -qF 'Where it never belongs' <<<"$d" || { echo "a double may replace the code under test"; return 1; }
}

@test "the checklist before delivery is five lines of its own" {
  # Five bullets, not a pointer back at the prose: the gate is read at the end of
  # the work, when the sections above have scrolled out of the agent's attention.
  d="$(section "$SKILL" 'Before you deliver')"
  n="$(grep -c '^- ' <<<"$d")"
  [ "$n" -ge 5 ] || { echo "## Before you deliver has $n item(s)"; return 1; }
}

@test "the Review section lists the findings and says they may block" {
  r="$(section "$SKILL" 'Review')"
  [ -n "$r" ] || { echo "no ## Review"; return 1; }
  for f in 'cannot fail' 'standing in for the behaviour under test' \
           'state crossing between tests' 'no test names' 'more than one behaviour'; do
    grep -qF "$f" <<<"$r" || { echo "## Review lost the finding '$f'"; return 1; }
  done
  # Both neighbouring skills end their ## Review with "none of them blocks". Without
  # the opposite said out loud, a reviewer reads the nearest rule and waves the lot through.
  grep -qF 'may block' <<<"$r" || { echo "## Review does not say a finding may block"; return 1; }
  grep -qF '`## When the task owes no test`' <<<"$r" || { echo "## Review does not hold a task that owed no test to it"; return 1; }
}

@test "test quality is no longer sent to the platforms" {
  nb="$(section "$SKILL" "Not this skill's business")"
  [ -n "$nb" ] || { echo "no ## Not this skill's business"; return 1; }
  # The bullet's own words wrap; its bold lead does not, and inside this section it
  # can only be the delegation this change removes.
  if grep -qF '**What a good test is**' <<<"$nb"; then
    echo "the bullet that moved into this skill is still delegating"
    return 1
  fi
}

# The Review brief's text only, stopping at the agent() options object — the same
# extractor phase-verification.test.bats uses.
review_brief() {
  awk -v stop="label: .review." '/^\/\/ ── Review ─/{p=1;next} p&&$0~stop{exit} p' "$1"
}

@test "every phased profile's Review judges the tests by the skill" {
  for p in feature bug refactor test; do
    b="$(review_brief "$ROOT/workflows/profile-$p.js")"
    grep -qF "the way the test-authoring skill's ## Review section does" <<<"$b" \
      || { echo "profile-$p.js: Review never judges test quality"; return 1; }
    grep -qF 'these are defects in what was delivered and may block' <<<"$b" \
      || { echo "profile-$p.js: the clause reads as non-blocking, like its neighbour"; return 1; }
  done
}

@test "exactly the four phased profiles and QUICK carry the test-quality clause" {
  n="$(grep -l "the way the test-authoring skill's ## Review section does" "$ROOT"/workflows/profile-*.js | wc -l | tr -d ' ')"
  [ "$n" -eq 5 ] || { echo "$n profile script(s) carry the clause, expected 5"; return 1; }
}

@test "the TEST profile keeps no second copy of the criteria" {
  # It carried the only written-out criteria in core; leaving them beside the clause
  # is two sources that drift, which is the defect this change exists to remove.
  if grep -qF 'What counts here: edge-case coverage' "$ROOT/workflows/profile-test.js"; then
    echo "profile-test.js still lists the criteria inline"
    return 1
  fi
}

@test "the platform guide sends test discipline to core and boundaries to the platform" {
  # Without this line the next platform author writes the discipline into their own
  # tester, which is the duplication this skill was widened to end.
  guide="$ROOT/docs/building-a-platform.md"
  grep -qF 'what a good test is comes from core too' "$guide" \
    || { echo "the guide does not say the discipline is core's"; return 1; }
  grep -qF 'what counts as a boundary here' "$guide" \
    || { echo "the guide does not leave the boundaries to the platform"; return 1; }
}
