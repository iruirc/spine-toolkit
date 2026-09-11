#!/usr/bin/env bats
# A phase ends green so it can be reverted or bisected alone; how much "green" means
# was defined nowhere, and a planner without a criterion re-ran the full regression in
# nine phases of ten. This suite holds the rule's text and every surface pointing at it.

setup() {
  ROOT="$(cd -- "$(dirname -- "$BATS_TEST_FILENAME")/../../.." && pwd)"
  SKILL="$ROOT/skills/phase-verification/SKILL.md"
  PROFILES="feature bug refactor test"
}

# A section's body, heading excluded, up to the next H2.
section() { # $1 = file, $2 = heading text without "## "
  awk -v h="## $2" '$0==h{f=1;next} f&&/^## /{exit} f' "$1"
}

@test "the skill exists and resolves under its own name" {
  [ -f "$SKILL" ] || { echo "no skills/phase-verification/SKILL.md"; return 1; }
  grep -q '^name: phase-verification$' "$SKILL" || { echo "frontmatter name is not phase-verification"; return 1; }
}

@test "the skill hands the full regression to Validation" {
  grep -qF 'The full regression belongs to Validation.' "$SKILL" \
    || { echo "nothing says a phase does not repeat Validation's run"; return 1; }
}

@test "the skill defines the three rungs" {
  rungs="$(section "$SKILL" 'The rungs')"
  for r in '| `internal` |' '| `surface` |' '| `behaviour` |'; do
    grep -qF "$r" <<<"$rungs" || { echo "## The rungs has no row $r"; return 1; }
  done
}

@test "the skill picks the rung by ordered questions backed by a usage search" {
  pick="$(section "$SKILL" 'Choosing the rung')"
  [ -n "$pick" ] || { echo "no ## Choosing the rung"; return 1; }
  grep -qF 'usage search' <<<"$pick" || { echo "the rung rests on memory, not on a search"; return 1; }
  grep -qF 'Doubt raises one rung, never to `full`' <<<"$pick" \
    || { echo "doubt has no bounded direction"; return 1; }
}

@test "the skill fixes the line's shape and writes it at full too" {
  line="$(section "$SKILL" 'The line')"
  grep -qF '**Verification:** <internal|surface|behaviour|full> — ' <<<"$line" \
    || { echo "the line's shape moved"; return 1; }
  grep -qF 'written at `full` too' <<<"$line" \
    || { echo "a missing line could mean a project choice or an old plan"; return 1; }
}

@test "a rung is raised by the diff and lowered by nobody" {
  who="$(section "$SKILL" 'Who does what')"
  grep -qF 'nobody lowers a rung' <<<"$who" || { echo "the ratchet has no floor"; return 1; }
}

@test "only dependents building from the perimeter's source count, and none is skipped" {
  grep -qF 'pinned to a published version' "$SKILL" \
    || { echo "a pinned consumer is counted as a dependent"; return 1; }
  agg="$(section "$SKILL" 'Dependents with no aggregate build')"
  grep -qF 'there is no skipping' <<<"$agg" || { echo "no aggregate reads as permission to skip"; return 1; }
  grep -qF 'Never merge consecutive `surface` phases' <<<"$agg" \
    || { echo "merging surface phases is not ruled out"; return 1; }
}

@test "the switch resolves to proportional and offers no off" {
  sw="$(section "$SKILL" 'The switch')"
  grep -qF 'Task.md [PHASE_VERIFICATION]  →  CLAUDE-spine-toolkit.md ## Validation → phase_verification  →  proportional' <<<"$sw" \
    || { echo "the resolution chain moved"; return 1; }
  grep -qF 'There is no `off`' <<<"$sw" || { echo "the switch does not rule out off"; return 1; }
}

@test "Review's findings are named and none of them blocks" {
  rev="$(section "$SKILL" 'Review')"
  grep -qF 'None of them blocks' <<<"$rev" || { echo "the findings may block"; return 1; }
  grep -qF '`blocking_findings`' <<<"$rev" || { echo "nothing keeps them out of blocking_findings"; return 1; }
}

@test "the skill stays within its budget and ships no locales" {
  n="$(wc -l < "$SKILL" | tr -d ' ')"
  [ "$n" -le 90 ] || { echo "SKILL.md is $n lines, budget 90"; return 1; }
  [ ! -d "$ROOT/skills/phase-verification/locales" ] || { echo "phase-verification must not carry locales/"; return 1; }
}

@test "task-new says when a task should run the full regression in every phase" {
  N="$ROOT/skills/task-new/SKILL.md"
  grep -qF '`[PHASE_VERIFICATION] = [<proportional|full>]`' "$N" \
    || { echo "task-new does not offer the override"; return 1; }
  grep -qF 'a wrong rung would cost more than the builds' "$N" \
    || { echo "task-new does not say when full is the right call"; return 1; }
}

@test "the scale convention says the axis does not move the rung" {
  gov="$(section "$ROOT/conventions/task-scale.md" 'What the axis does not govern')"
  grep -qF 'phase_verification' <<<"$gov" \
    || { echo "a lite task could read as licence for a lower rung"; return 1; }
}

# Same extractors as manual-checks.test.bats: a stage's brief in a profile script,
# and a stage's own bullet in a Method B skill.
plan_brief() {
  awk '/^\/\/ ── Plan ─/{p=1;next} p&&/^\/\/ ── /{exit} p' "$1"
}
bullet() { # $1 = SKILL.md, $2 = stage name
  awk -v s="- **$2**" 'index($0,s)==1{p=1;print;next} p&&/^- \*\*/{exit} p' "$1"
}

@test "every phased profile's Plan brief asks for the line and points at the skill" {
  for p in $PROFILES; do
    b="$(plan_brief "$ROOT/workflows/profile-$p.js")"
    grep -qF 'with a **Verification:** line' <<<"$b" \
      || { echo "profile-$p.js: the Plan brief never asks for the line"; return 1; }
    grep -qF 'phase-verification skill' <<<"$b" \
      || { echo "profile-$p.js: the Plan brief does not point at the skill"; return 1; }
    grep -qF 'The full regression belongs to Validation' <<<"$b" \
      || { echo "profile-$p.js: the Plan brief does not hand the full run to Validation"; return 1; }
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

@test "exactly the four phased profiles carry the Plan clause" {
  # Vacuity guard: without it the loops above iterate over a list someone shortened.
  n="$(grep -l "Open every phase's detail section with a" "$ROOT"/workflows/profile-*.js | wc -l | tr -d ' ')"
  [ "$n" -eq 4 ] || { echo "$n profile script(s) carry the Plan clause, expected 4"; return 1; }
}
