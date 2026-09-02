#!/usr/bin/env bats
# ManualChecks.md is the one artifact of a task a person executes rather than reads.
# A vague sentence in a walkthrough costs a re-read; a vague step here cannot be run at
# all. This suite holds the parts of that spec a reviewer cannot see: that both halves
# of the two-stage contract reached both execution forms of all four profiles.

setup() {
  ROOT="$(cd -- "$(dirname -- "$BATS_TEST_FILENAME")/../../.." && pwd)"
  SKILL="$ROOT/skills/manual-checks/SKILL.md"
  PROFILES="feature bug refactor test"
}

@test "the skill exists and resolves under its own name" {
  [ -f "$SKILL" ] || { echo "no skills/manual-checks/SKILL.md"; return 1; }
  grep -q '^name: manual-checks$' "$SKILL" || { echo "frontmatter name is not manual-checks"; return 1; }
}

@test "the skill carries every required field of a case" {
  for field in '**What it checks:**' '**Scene:**' '**Steps:**' '**By eye:**' '**By instrument:**' '**Failure looks like:**'; do
    grep -qF "$field" "$SKILL" || { echo "the skill never names the field $field"; return 1; }
  done
}

@test "the skill carries both rules that decide whether a case is executable" {
  grep -q '^## The instrument rule$' "$SKILL" || { echo "no instrument rule"; return 1; }
  grep -q '^## The symbol rule$' "$SKILL" || { echo "no symbol rule"; return 1; }
}

@test "the skill states both halves of the two-stage contract" {
  grep -q '## Manual acceptance' "$SKILL" || { echo "the skill never names the plan-side section"; return 1; }
  grep -q 'ManualChecks.md' "$SKILL" || { echo "the skill never names the artifact"; return 1; }
}

@test "the skill names the shared sections that keep a case from repeating its neighbours" {
  for section in '## Preparation' '## Reading the verdict' '## Troubleshooting'; do
    grep -qF "$section" "$SKILL" || { echo "the skill never names $section"; return 1; }
  done
  grep -qi 'conditional' "$SKILL" \
    || { echo "the shared sections are not marked conditional, so a two-case task gets all three"; return 1; }
}

@test "the skill states the floor that survives lite" {
  grep -q '^## Scale$' "$SKILL" || { echo "the skill says nothing about scale"; return 1; }
  grep -qi 'cuts no required field' "$SKILL" || { echo "lite is not held off the required fields"; return 1; }
}

@test "the skill ships no locales, like the other agent-facing skills" {
  # ops-checklist and task-walkthrough have none either: nothing here is user-facing,
  # and a locales/ directory would put this skill under lint-locales parity for no reader.
  [ ! -d "$ROOT/skills/manual-checks/locales" ] || { echo "manual-checks must not carry locales/"; return 1; }
}

# The Plan brief of a profile script runs from its own banner to the next stage's.
# Grepping the whole file would pass on a mention in the Validation brief, which is
# the one place this clause must NOT be, since by then the plan is already written.
plan_brief() {
  awk '/^\/\/ ── Plan ─/{p=1;next} p&&/^\/\/ ── /{exit} p' "$1"
}

# A stage's own bullet in a Method B skill, from its "- **Stage**" line to the next
# bullet. Whole-file greps do not work here: by Task 3 the Validation bullet quotes the
# plan-side section name, and every one of these tests would pass before its own edit.
bullet() { # $1 = SKILL.md, $2 = stage name
  awk -v s="- **$2**" 'index($0,s)==1{p=1;print;next} p&&/^- \*\*/{exit} p' "$1"
}

@test "every profile asks its Plan stage for the manual-acceptance list" {
  for p in $PROFILES; do
    plan_brief "$ROOT/workflows/profile-$p.js" | grep -q '## Manual acceptance' \
      || { echo "profile-$p.js: the Plan brief never asks for ## Manual acceptance"; return 1; }
  done
}

@test "the Plan brief offers the escape line for a fully automatable task" {
  for p in $PROFILES; do
    plan_brief "$ROOT/workflows/profile-$p.js" | grep -q 'Fully automatable' \
      || { echo "profile-$p.js: no escape line, so an empty list has no legal form"; return 1; }
  done
}

@test "the same requirement reached the Method B skill of every profile" {
  for p in $PROFILES; do
    bullet "$ROOT/skills/workflow-$p/SKILL.md" Plan | grep -q '## Manual acceptance' \
      || { echo "workflow-$p/SKILL.md: the Plan stage says nothing about ## Manual acceptance"; return 1; }
  done
}

@test "BUG says where the replay comes from instead of listing it twice" {
  # Both greps target the inserted sentence itself. A bare 'Reproduce.md' matches
  # two lines the bug Plan brief already carried, and a bare 'replay' matches three
  # in workflow-bug/SKILL.md — either one passes before the edit it exists to check.
  plan_brief "$ROOT/workflows/profile-bug.js" | grep -q 'reproduction replay is not' \
    || { echo "profile-bug.js: the Plan brief does not exempt the replay"; return 1; }
  bullet "$ROOT/skills/workflow-bug/SKILL.md" Plan | grep -q 'reproduction replay is not' \
    || { echo "workflow-bug/SKILL.md: the replay exemption did not reach the Plan bullet"; return 1; }
}

@test "exactly the four profiles with a Validation stage carry the clause" {
  # Vacuity guard: without it the loops above iterate over a list someone shortened.
  n="$(grep -l '## Manual acceptance' "$ROOT"/workflows/profile-*.js | wc -l | tr -d ' ')"
  [ "$n" -eq 4 ] || { echo "$n profile script(s) carry the clause, expected 4"; return 1; }
}
