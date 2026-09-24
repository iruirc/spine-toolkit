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

@test "the prelude hands the value to the three phased profiles and QUICK" {
  for f in "$ROOT"/workflows/profile-*.js; do
    grep -qF "const TESTS_NOTE = A.need_test === false && ['FEATURE', 'BUG', 'REFACTOR', 'QUICK'].includes(PROFILE)" "$f" \
      || { echo "$(basename "$f"): no gated TESTS_NOTE — TEST and RESEARCH default to false"; return 1; }
    grep -qF '${TESTS_NOTE}Output language:' "$f" || { echo "$(basename "$f"): brief() never carries the line"; return 1; }
    grep -qF '`## When the task owes no test`' "$f" || { echo "$(basename "$f"): the line does not point at the section"; return 1; }
  done
}

@test "no phased stage demands a tester the task does not need" {
  for p in $PHASED; do
    f="$ROOT/workflows/profile-$p.js"
    if grep -qE "^  if \(!need\('(Execute|Fix|Refactor)', '[a-z]+', 'tester'\)\)" "$f"; then
      echo "profile-$p.js: tester is demanded whatever need_test says"; return 1
    fi
    grep -qE "A\.need_test === false \? need\('(Execute|Fix|Refactor)', '[a-z]+'\) : need\(" "$f" \
      || { echo "profile-$p.js: no need() branch on need_test"; return 1; }
  done
}

@test "a test phase under need_test=false stops the stage before any phase runs" {
  for p in $PHASED; do
    f="$ROOT/workflows/profile-$p.js"
    g="$(grep -n "fromStartPhase(plan.phases || \[\]).filter((ph) => ph.kind === 'test')" "$f" | cut -d: -f1)"
    r="$(grep -n 'const phasesDone = await runPhases(' "$f" | cut -d: -f1)"
    [ -n "$g" ] || { echo "profile-$p.js: no guard over the remaining phases"; return 1; }
    [ "$g" -lt "$r" ] || { echo "profile-$p.js: the guard runs after the phases"; return 1; }
    grep -qF 'need_test=false, yet Plan.md has test phase(s)' "$f" || { echo "profile-$p.js: the stop names nothing"; return 1; }
  done
}

# A stage's block in a profile script, from its banner to the next one.
stage_block() { # $1 = file, $2 = stage
  awk -v s="// ── $2 " 'index($0,s)==1{p=1;next} p&&/^\/\/ ── /{exit} p' "$1"
}

@test "every BUG stage that spoke of the regression test branches on need_test" {
  f="$ROOT/workflows/profile-bug.js"
  # One phrase per stage that only its need_test=false branch carries; a bare
  # "A.need_test === false" would already match Fix through its need() line.
  while IFS='|' read -r s phrase; do
    grep -qF "$phrase" <<<"$(stage_block "$f" "$s")" \
      || { echo "BUG $s asks for a test whatever need_test says"; return 1; }
  done <<'EOF'
Reproduce|Reproduce.md proposes none and carries no ## Regression Test section
Plan|the plan has no phase of kind test and no regression-test item
Fix|the phase writes none
Review|${A.need_test === false ? '' : 'does the regression test lock in the real scenario, '}
Done|that no regression test was written because the task owes none
EOF
  if grep -qF 'unless the contract disabled it' "$f"; then
    echo "Fix still leaves the agent to guess the contract"; return 1
  fi
}

@test "Method B says the same" {
  for p in $PHASED; do
    grep -qF '`## When the task owes no test`' "$ROOT/skills/workflow-$p/SKILL.md" \
      || { echo "workflow-$p/SKILL.md: need_test only gates a role"; return 1; }
  done
  b="$ROOT/skills/workflow-bug/SKILL.md"
  if grep -F 'regression test is mandatory' "$b" | grep -vqF 'need_test=true'; then
    echo "workflow-bug/SKILL.md calls the test mandatory without the condition"; return 1
  fi
}

@test "an epic step reports its own need_test and need_review" {
  f="$ROOT/workflows/profile-epic.js"
  plan="$(stage_block "$f" "Plan")"
  execute="$(stage_block "$f" "Execute")"
  for tag in '[NEED_TEST]' '[NEED_REVIEW]'; do
    grep -qF "$tag" <<<"$plan" || { echo "Plan's return instruction never names $tag"; return 1; }
    grep -qF "$tag" <<<"$execute" || { echo "Execute's read-steps prompt never names $tag"; return 1; }
  done
  grep -qF "need_test: { type: 'boolean', description:" "$f" \
    || { echo "the STEP schema's need_test field has no description"; return 1; }
}

@test "the contract pins need_test and need_review as JSON booleans" {
  grep -qF 'Method A passes `need_test` and `need_review` as JSON booleans' "$ROOT/skills/orchestrator/SKILL.md" \
    || { echo "the Outbound Contract never says the type"; return 1; }
}
