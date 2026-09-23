#!/usr/bin/env bats
# need_test=false reached one sentence of one prompt, and a task that owed no test shipped
# one. The rule lives in test-authoring; these tests hold it there and hold every stage
# that has to act on it.

setup() {
  ROOT="$(cd -- "$(dirname -- "$BATS_TEST_FILENAME")/../../.." && pwd)"
  SKILL="$ROOT/skills/test-authoring/SKILL.md"
  PHASED="feature bug refactor"
}

# A section's body, heading excluded, up to the next H2.
section() { # $1 = file, $2 = heading text without "## "
  awk -v h="## $2" '$0==h{f=1;next} f&&/^## /{exit} f' "$1"
}

@test "the skill says what need_test=false forbids" {
  s="$(section "$SKILL" 'When the task owes no test')"
  [ -n "$s" ] || { echo "no ## When the task owes no test"; return 1; }
  for f in 'adds no test: no test file and no test case' 'existing suite runs as usual' \
           'names that test and the reason' 'REFACTOR keeps its stricter rule'; do
    grep -qF "$f" <<<"$s" || { echo "the section lost: $f"; return 1; }
  done
}

@test "review holds a task that owed no test to the section" {
  r="$(section "$SKILL" 'Review')"
  grep -qF '`## When the task owes no test`' <<<"$r" || { echo "## Review does not point at the section"; return 1; }
  grep -qF 'is a blocking finding' <<<"$r" || { echo "a test under need_test=false reads as harmless"; return 1; }
  if grep -qF 'yields nothing' <<<"$r"; then echo "## Review still waves a need_test=false task through"; return 1; fi
}

@test "the contract decides whether, the section decides what false means" {
  nb="$(section "$SKILL" "Not this skill's business")"
  grep -qF '`## When the task owes no test`' <<<"$nb" || { echo "the bullet does not point at the section"; return 1; }
}
