#!/usr/bin/env bats
# The config's `## Task defaults` and the task templates' optional lines are two halves of one
# vocabulary: a field in one and not the other is a field a user can set in a task and not in a
# project, or the reverse, and nothing but this test would say so.

setup() {
  ROOT="$(cd -- "$(dirname -- "$BATS_TEST_FILENAME")/../../.." && pwd)"
  TPL="$ROOT/templates/claude-toolkit-md/en.md"
}

fields_of_block() {
  awk '/^## Task defaults$/{f=1;next} f&&/^## /{exit} f' "$TPL" \
    | sed -n 's/^\[\([A-Z_]*\)\].*/\1/p' | sort
}

fields_of_task_template() {
  sed -n 's/^# *\[\([A-Z_]*\)\] *=.*/\1/p;s/^\[\([A-Z_]*\)\] *=.*/\1/p' "$ROOT/templates/task-md/$1.md" \
    | command grep -vE '^(TASK_TYPE|NEED_TEST|NEED_REVIEW|STATUS|DOCS_NEW)$' | sort -u
}

@test "the config's task defaults are exactly the fields a task can override" {
  for t in task-root task-step; do
    diff <(fields_of_block) <(fields_of_task_template "$t") \
      || { echo "## Task defaults and $t.md disagree"; return 1; }
  done
}

@test "every field of both config blocks is documented" {
  doc="$ROOT/docs/configuration.md"
  for f in $(sed -n 's/^\[\([A-Z_]*\)\].*/\1/p' "$TPL" | sort -u); do
    grep -qF "[$f]" "$doc" || { echo "docs/configuration.md does not document [$f]"; return 1; }
  done
}
