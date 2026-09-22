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

@test "the skill binds every agent that writes test code, and the validator that reads failures" {
  who="$(section "$SKILL" 'Who follows it')"
  [ -n "$who" ] || { echo "no ## Who follows it"; return 1; }
  for role in tester developer diagnostics init validator; do
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
