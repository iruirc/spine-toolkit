#!/usr/bin/env bats
# changed: sweep skills workflows
# Split from phase-verification.test.bats: the tests that walk the source trees.

setup() {
  ROOT="$(cd -- "$(dirname -- "$BATS_TEST_FILENAME")/../../.." && pwd)"
  SKILL="$ROOT/skills/phase-verification/SKILL.md"
  PROFILES="feature bug refactor test"
}

# A section's body, heading excluded, up to the next H2.
section() { # $1 = file, $2 = heading text without "## "
  awk -v h="## $2" '$0==h{f=1;next} f&&/^## /{exit} f' "$1"
}

# Same extractors as manual-checks.test.bats: a stage's brief in a profile script,
# and a stage's own bullet in a Method B skill.
plan_brief() {
  awk '/^\/\/ ── Plan ─/{p=1;next} p&&/^\/\/ ── /{exit} p' "$1"
}

bullet() { # $1 = SKILL.md, $2 = stage name
  awk -v s="- **$2**" 'index($0,s)==1{p=1;print;next} p&&/^- \*\*/{exit} p' "$1"
}

# The Review brief's text only, stopping at the agent() options object — same
# extractor as manual-checks.test.bats.
review_brief() {
  awk -v stop="label: .review." '/^\/\/ ── Review ─/{p=1;next} p&&$0~stop{exit} p' "$1"
}

@test "every phased profile's Plan brief asks for the line and points at the skill" {
  for p in $PROFILES; do
    b="$(plan_brief "$ROOT/workflows/profile-$p.js")"
    grep -qF 'with a **Verification:** line' <<<"$b" \
      || { echo "profile-$p.js: the Plan brief never asks for the line"; return 1; }
    grep -qF 'phase-verification skill' <<<"$b" \
      || { echo "profile-$p.js: the Plan brief does not point at the skill"; return 1; }
    grep -qF 'The regression set belongs to Validation' <<<"$b" \
      || { echo "profile-$p.js: the Plan brief does not hand the regression to Validation"; return 1; }
  done
}

@test "the Plan requirement reached the Method B skill of every phased profile" {
  for p in $PROFILES; do
    b="$(bullet "$ROOT/skills/workflow-$p/SKILL.md" Plan)"
    grep -qF 'opens with a `**Verification:**` line' <<<"$b" \
      || { echo "workflow-$p/SKILL.md: the Plan stage says nothing about the line"; return 1; }
    grep -qF '`phase-verification` skill' <<<"$b" \
      || { echo "workflow-$p/SKILL.md: the Plan stage does not point at the skill"; return 1; }
  done
}

@test "every profile script runs what the phase's line names" {
  n="$(ls "$ROOT"/workflows/profile-*.js | wc -l | tr -d ' ')"
  [ "$n" -eq 8 ] || { echo "scanned $n script(s), expected 8"; return 1; }
  for f in "$ROOT"/workflows/profile-*.js; do
    grep -qF 'run the checks its **Verification:** line names' "$f" \
      || { echo "$(basename "$f"): the prelude still picks its own checks"; return 1; }
    grep -qF 'a rung is never lowered' "$f" \
      || { echo "$(basename "$f"): the prelude lets a phase lower its rung"; return 1; }
  done
}

@test "the old names for a phase's checks are gone from both dispatch forms" {
  [ -d "$ROOT/workflows" ] && [ -f "$ROOT/skills/workflow-test/SKILL.md" ] \
    || { echo "the scan would run over nothing"; return 1; }
  hits="$(grep -rnF \
    -e 'touched scope' -e 'targeted tests' -e 'newly added tests for that phase' \
    -e "Run the phase\\'s new tests" -e 'Where possible, runs local tests' \
    "$ROOT/workflows" "$ROOT"/skills/workflow-* || true)"
  [ -z "$hits" ] || { echo "$hits"; return 1; }
}

@test "the Method B implementing stage runs what the line names" {
  for pair in feature:Execute bug:Fix refactor:Refactor test:Write; do
    p="${pair%%:*}"; s="${pair#*:}"
    b="$(bullet "$ROOT/skills/workflow-$p/SKILL.md" "$s")"
    grep -qF '`**Verification:**` line names' <<<"$b" \
      || { echo "workflow-$p/SKILL.md: $s does not run what the line names"; return 1; }
    grep -qF 'a rung is never lowered' <<<"$b" \
      || { echo "workflow-$p/SKILL.md: $s lets a phase lower its rung"; return 1; }
  done
}

@test "every phased profile's Review judges the line without blocking on it" {
  for p in $PROFILES; do
    b="$(review_brief "$ROOT/workflows/profile-$p.js")"
    grep -qF "the way the phase-verification skill's ## Review section does" <<<"$b" \
      || { echo "profile-$p.js: Review never judges the verification line"; return 1; }
    grep -qF 'none of them blocks' <<<"$b" \
      || { echo "profile-$p.js: Review may block on a plan finding"; return 1; }
  done
}

@test "the Review clause reached the Method B skill of every phased profile" {
  for p in $PROFILES; do
    b="$(bullet "$ROOT/skills/workflow-$p/SKILL.md" Review)"
    grep -qF 'judged by the `phase-verification` skill' <<<"$b" \
      || { echo "workflow-$p/SKILL.md: the Review stage does not judge the line"; return 1; }
    grep -qF 'none of them blocking' <<<"$b" \
      || { echo "workflow-$p/SKILL.md: the Review stage may block on a plan finding"; return 1; }
  done
}

@test "a phase runs its verification checks once, not again after ticking them" {
  for f in "$ROOT"/workflows/profile-*.js; do
    grep -qF 'every checkbox in the phase except its verification checks is ticked' "$f" \
      || { echo "$(basename "$f"): ticked checks would run a second time"; return 1; }
  done
  for pair in feature:Execute bug:Fix refactor:Refactor test:Write; do
    p="${pair%%:*}"; s="${pair#*:}"
    bullet "$ROOT/skills/workflow-$p/SKILL.md" "$s" | grep -qF 'checkboxes except its verification checks are' \
      || { echo "workflow-$p/SKILL.md: $s would run ticked checks a second time"; return 1; }
  done
}

@test "exactly the four phased profiles carry the Plan clause" {
  # Vacuity guard: without it the loops above iterate over a list someone shortened.
  n="$(grep -l "Open every phase's detail section with a" "$ROOT"/workflows/profile-*.js | wc -l | tr -d ' ')"
  [ "$n" -eq 4 ] || { echo "$n profile script(s) carry the Plan clause, expected 4"; return 1; }
}

@test "exactly the four phased profiles and QUICK carry the Review clause" {
  n="$(grep -l "the way the phase-verification skill's ## Review section does" "$ROOT"/workflows/profile-*.js | wc -l | tr -d ' ')"
  [ "$n" -eq 5 ] || { echo "$n profile script(s) carry the Review clause, expected 5"; return 1; }
}
