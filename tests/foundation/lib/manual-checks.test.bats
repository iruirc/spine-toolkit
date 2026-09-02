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
