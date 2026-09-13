#!/usr/bin/env bats
# A step's [STATUS] is written by task-new and task-move, shown by task-status and
# read back by the epic's step walker through a schema enum. Six copies of one
# vocabulary: a value one of them lacks is a step the walker cannot report.

setup() {
  ROOT="$(cd -- "$(dirname -- "$BATS_TEST_FILENAME")/../../.." && pwd)"
  SCRIPT="$ROOT/workflows/profile-epic.js"
  CANON='BLOCKED DEFERRED DONE IN_PROGRESS PENDING SKIPPED'
}

# The upper-case status words on stdin, sorted and space-joined.
words() { grep -oE '[A-Z][A-Z_]{3,}' | grep -vE '^(STATUS|TASK_TYPE)$' | sort -u | paste -sd' ' -; }

@test "the step template declares the canonical vocabulary" {
  got="$(grep -F '[STATUS] = [{{STATUS}}]' "$ROOT/templates/task-md/task-step.md" | sed 's/^[^#]*#//' | words)"
  [ "$got" = "$CANON" ] || { echo "template: $got"; return 1; }
}

@test "task-new, task-move and task-status spell the same vocabulary" {
  got="$(grep -F '| `{{STATUS}}` |' "$ROOT/skills/task-new/SKILL.md" | sed 's/^[^)]*)//' | words)"
  [ "$got" = "$CANON" ] || { echo "task-new: $got"; return 1; }
  got="$(awk '/^## Available Step Statuses/{f=1;next} /^## /{f=0} f' "$ROOT/skills/task-move/SKILL.md" | words)"
  [ "$got" = "$CANON" ] || { echo "task-move: $got"; return 1; }
  got="$(grep -F "the step's \`[STATUS]\`" "$ROOT/skills/task-status/SKILL.md" | sed 's/^[^(]*(//' | words)"
  [ "$got" = "$CANON" ] || { echo "task-status: $got"; return 1; }
}

@test "workflow-epic declares the same vocabulary for a step" {
  got="$(grep -oE '`\[STATUS\]` ∈ \{[^}]*\}' "$ROOT/skills/workflow-epic/SKILL.md" | head -1 | words)"
  [ "$got" = "$CANON" ] || { echo "workflow-epic: $got"; return 1; }
}

@test "the step walker's schema accepts every value task-new can write" {
  got="$(awk '/^const STEP = \{/{f=1} f && /status: \{/{print; exit}' "$SCRIPT" | sed 's/^[^[]*\[//' | words)"
  [ "$got" = "$CANON" ] || { echo "STEP.status enum: $got"; return 1; }
}

@test "the statuses the walker skips are a subset of the vocabulary" {
  skip_list="$(grep -E '^const SKIP_STATUS = ' "$SCRIPT" | sed 's/^[^=]*=//' | words)"
  [ -n "$skip_list" ] || { echo "no SKIP_STATUS list to check"; return 1; }
  for s in $skip_list; do
    grep -qw "$s" <<<"$CANON" || { echo "SKIP_STATUS names $s, which no step can carry"; return 1; }
  done
}

@test "nothing tells an agent to write a pre-vocabulary status" {
  hits="$(grep -rnE '\[STATUS\] = \[?(TODO|ACTIVE)([^A-Z_]|$)' "$ROOT/skills" "$ROOT/workflows" "$ROOT/templates" "$ROOT/commands" || true)"
  [ -z "$hits" ] || { echo "a step is told to start at a pre-vocabulary status:"; echo "$hits"; return 1; }
}

@test "the pre-vocabulary spellings are read, not rejected" {
  # Steps written before the vocabulary settled say TODO and ACTIVE. Neither is skipped,
  # so reading them as PENDING and IN_PROGRESS keeps every such epic walking as it did.
  grep -qF 'TODO and ACTIVE are the pre-vocabulary spellings of PENDING and IN_PROGRESS' "$ROOT/skills/workflow-epic/SKILL.md" \
    || { echo "workflow-epic does not say how TODO and ACTIVE are read"; return 1; }
  grep -qF 'TODO or ACTIVE is the pre-vocabulary spelling of PENDING or IN_PROGRESS' "$SCRIPT" \
    || { echo "the step reader is not told how to report TODO and ACTIVE"; return 1; }
}
