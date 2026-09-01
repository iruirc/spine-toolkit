#!/usr/bin/env bats
# D12: a ceiling stated in a brief and never measured is the class of directive this
# repository has already watched go unobserved. The script is the measurement, so the
# script is what a test has to drive — and the last test here is what stops the two
# copies of the ceiling table (this script, the workflow prelude) from drifting apart.

setup() {
  ROOT="$(cd -- "$(dirname -- "$BATS_TEST_FILENAME")/../../.." && pwd)"
  LINT="$ROOT/scripts/lint-artifact-budget.sh"
  PROJ="$BATS_TEST_TMPDIR/proj"
  TASK="$PROJ/Tasks/ACTIVE/042-a-task"
  mkdir -p "$TASK"
  printf '## Scale\n\nlite\n' >"$PROJ/CLAUDE-spine-toolkit.md"
  printf '[TASK_TYPE] = [BUG]\n[NEED_TEST] = [true]\n' >"$TASK/Task.md"
}

lines() { python3 -c 'import sys; open(sys.argv[1],"w").write("x\n"*int(sys.argv[2]))' "$1" "$2"; }

@test "a lite task with an oversized Plan.md fails the lint" {
  lines "$TASK/Plan.md" 300
  run "$LINT" "$TASK"
  [ "$status" -eq 1 ]
  case "$output" in *"Plan.md"*300*200*) ;; *) echo "$output"; return 1 ;; esac
}

@test "the same Plan.md passes at full" {
  lines "$TASK/Plan.md" 300
  printf '## Scale\n\nfull\n' >"$PROJ/CLAUDE-spine-toolkit.md"
  run "$LINT" "$TASK"
  [ "$status" -eq 0 ]
}

@test "a task-level full beats a lite project" {
  lines "$TASK/Plan.md" 300
  printf '[TASK_TYPE] = [BUG]\n[SCALE] = [full]\n' >"$TASK/Task.md"
  run "$LINT" "$TASK"
  [ "$status" -eq 0 ]
}

@test "the template's commented override line is not a value" {
  # Every task file ships `# [SCALE] = [full]` as documentation. Reading it as the
  # value would exempt every task in every project from the ceiling, silently.
  lines "$TASK/Plan.md" 300
  printf '[TASK_TYPE] = [BUG]\n# [SCALE] = [full]        # lite | full\n' >"$TASK/Task.md"
  run "$LINT" "$TASK"
  [ "$status" -eq 1 ]
}

@test "an absent Scale block means full, and full is never measured" {
  lines "$TASK/Plan.md" 300
  printf '# CLAUDE-spine-toolkit.md\n\n## Mode\n\nmanual\n' >"$PROJ/CLAUDE-spine-toolkit.md"
  run "$LINT" "$TASK"
  [ "$status" -eq 0 ]
}

@test "the profiles with no implementing stage are not measured" {
  lines "$TASK/Review.md" 400
  printf '[TASK_TYPE] = [RESEARCH]\n' >"$TASK/Task.md"
  run "$LINT" "$TASK"
  [ "$status" -eq 0 ]
}

@test "an artifact inside its ceiling passes" {
  lines "$TASK/Plan.md" 199
  lines "$TASK/Done.md" 80
  run "$LINT" "$TASK"
  [ "$status" -eq 0 ]
}

@test "a step folder is measured against its own Task.md" {
  mkdir -p "$TASK/1.step"
  printf '[TASK_TYPE] = [FEATURE]\n[SCALE] = [full]\n' >"$TASK/1.step/Task.md"
  lines "$TASK/1.step/Plan.md" 300
  run "$LINT" "$TASK"
  [ "$status" -eq 0 ]
  printf '[TASK_TYPE] = [FEATURE]\n' >"$TASK/1.step/Task.md"
  run "$LINT" "$TASK"
  [ "$status" -eq 1 ]
}

@test "archived artifacts are not measured" {
  mkdir -p "$TASK/_archive"
  lines "$TASK/_archive/Plan-2026-04-25T143022.md" 900
  run "$LINT" "$TASK"
  [ "$status" -eq 0 ]
}

@test "the ceilings in the lint and in the workflow prelude are one table" {
  verdict="$(python3 - "$LINT" "$ROOT/workflows/profile-bug.js" <<'PY'
import re, sys
lint = re.search(r'^CAPS="([^"]*)"', open(sys.argv[1], encoding='utf-8').read(), re.M)
pre = re.search(r'^const CAP = \{([^}]*)\}', open(sys.argv[2], encoding='utf-8').read(), re.M)
if not lint or not pre:
    print('one of the two tables is missing'); raise SystemExit
a = sorted(lint.group(1).split())
b = sorted('%s:%s' % (k, v) for k, v in re.findall(r"'([^']+)':\s*(\d+)", pre.group(1)))
print('same' if a and a == b else 'differ: %s vs %s' % (a, b))
PY
)"
  [ "$verdict" = "same" ] || { echo "$verdict"; return 1; }
}
