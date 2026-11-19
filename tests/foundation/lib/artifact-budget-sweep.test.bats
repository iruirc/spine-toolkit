#!/usr/bin/env bats
# changed: sweep skills workflows
# Split from artifact-budget.test.bats: the tests that walk the source trees.

setup() {
  ROOT="$(cd -- "$(dirname -- "$BATS_TEST_FILENAME")/../../.." && pwd)"
  LINT="$ROOT/scripts/lint-artifact-budget.sh"
  PROJ="$BATS_TEST_TMPDIR/proj"
  TASK="$PROJ/Tasks/ACTIVE/042-a-task"
  mkdir -p "$TASK"
  printf '## Task defaults\n\n[SCALE] = [lite]\n' >"$PROJ/CLAUDE-spine-toolkit.md"
  printf '[TASK_TYPE] = [BUG]\n[NEED_TEST] = [true]\n' >"$TASK/Task.md"
}

@test "every profile script reads the ceilings from the contract's budgets" {
  n=0
  for f in "$ROOT"/workflows/profile-*.js; do
    n=$((n + 1))
    grep -qF 'A.budgets' "$f" || { echo "$(basename "$f"): the prelude ignores budgets"; return 1; }
    grep -qF '${BUDGETS[file]}' "$f" || { echo "$(basename "$f"): cap() still names the default"; return 1; }
  done
  [ "$n" -eq 8 ] || { echo "scanned $n script(s), expected 8"; return 1; }
}

@test "the four phased Method B skills read the ceilings from the contract" {
  for p in feature bug refactor test; do
    grep -qF "Read the ceilings from the contract's \`budgets\` field" "$ROOT/skills/workflow-$p/SKILL.md" \
      || { echo "workflow-$p/SKILL.md still reads the ceilings from the script's table"; return 1; }
  done
}
