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

@test "an unrecognized Scale value resolves to full and is reported, not silent" {
  lines "$TASK/Plan.md" 300
  printf '## Scale\n\ngarbage\n' >"$PROJ/CLAUDE-spine-toolkit.md"
  run "$LINT" "$TASK"
  [ "$status" -eq 0 ]
  case "$output" in *"garbage"*"treating as full"*) ;; *) echo "$output"; return 1 ;; esac
}

@test "the profiles with no implementing stage are not measured" {
  lines "$TASK/Review.md" 400
  printf '[TASK_TYPE] = [RESEARCH]\n' >"$TASK/Task.md"
  run "$LINT" "$TASK"
  [ "$status" -eq 0 ]
}

@test "an epic's own Plan.md is exempt, but a step folder inside it is still measured" {
  printf '[TASK_TYPE] = [EPIC]\n' >"$TASK/Task.md"
  lines "$TASK/Plan.md" 300
  run "$LINT" "$TASK"
  [ "$status" -eq 0 ]

  mkdir -p "$TASK/1.step"
  printf '[TASK_TYPE] = [FEATURE]\n' >"$TASK/1.step/Task.md"
  lines "$TASK/1.step/Plan.md" 300
  run "$LINT" "$TASK"
  [ "$status" -eq 1 ]
  case "$output" in *"1.step/Plan.md"*) ;; *) echo "$output"; return 1 ;; esac
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

# A step's Task.md with all three anchors, padded to $2 lines.
step_task() { # $1 = step dir, $2 = total lines (>= 15)
  mkdir -p "$1"
  printf '[TASK_TYPE] = [FEATURE]\n\n## 3. [Task]\n\n### Expected behaviour\n\n| a | b |\n\n### Questions for Research\n\nwhere\n\n### Acceptance\n\ndone\n' >"$1/Task.md"
  python3 -c 'import sys; p,n=sys.argv[1],int(sys.argv[2]); c=open(p).read().count("\n"); open(p,"a").write("x\n"*max(0,n-c))' "$1/Task.md" "$2"
}

epic() { printf '[TASK_TYPE] = [EPIC]\n' >"$TASK/Task.md"; }

@test "--task-docs passes a step inside its ceiling with all three anchors" {
  epic; step_task "$TASK/1.step" 100
  run "$LINT" --task-docs "$TASK"
  [ "$status" -eq 0 ] || { echo "$output"; return 1; }
}

@test "--task-docs fails a step over its ceiling, at full" {
  printf '## Scale\n\nfull\n' >"$PROJ/CLAUDE-spine-toolkit.md"
  epic; step_task "$TASK/1.step" 101
  run "$LINT" --task-docs "$TASK"
  [ "$status" -eq 1 ]
  case "$output" in *"1.step/Task.md: 101 lines, ceiling 100"*) ;; *) echo "$output"; return 1 ;; esac
}

@test "--task-docs names a missing anchor" {
  epic; step_task "$TASK/1.step" 20
  sed -i.bak '/^### Acceptance$/d' "$TASK/1.step/Task.md"
  run "$LINT" --task-docs "$TASK"
  [ "$status" -eq 1 ]
  case "$output" in *'anchor "### Acceptance" missing'*) ;; *) echo "$output"; return 1 ;; esac
}

@test "an empty anchor and a bare dash fail, a dash with a reason passes" {
  epic; mkdir -p "$TASK/1.step"
  printf '[TASK_TYPE] = [RESEARCH]\n\n## 3. [Task]\n\n### Expected behaviour\n\n—\n\n### Questions for Research\n\n### Acceptance\n\ndone\n' >"$TASK/1.step/Task.md"
  run "$LINT" --task-docs "$TASK"
  [ "$status" -eq 1 ]
  case "$output" in *'"### Expected behaviour" is a bare dash'*) ;; *) echo "$output"; return 1 ;; esac
  case "$output" in *'"### Questions for Research" has no text'*) ;; *) echo "$output"; return 1 ;; esac
  printf '[TASK_TYPE] = [RESEARCH]\n\n## 3. [Task]\n\n### Expected behaviour\n\n— a research step delivers findings, not behaviour\n\n### Questions for Research\n\nwhere\n\n### Acceptance\n\ndone\n' >"$TASK/1.step/Task.md"
  run "$LINT" --task-docs "$TASK"
  [ "$status" -eq 0 ] || { echo "$output"; return 1; }
}

@test "without --task-docs a step's Task.md is never read, even at lite" {
  # An epic written before the anchors existed runs every stage of every step through this
  # script; reading its Task.md here would send an old step back for a trim on every stage.
  epic; mkdir -p "$TASK/1.step"
  printf '[TASK_TYPE] = [FEATURE]\n' >"$TASK/1.step/Task.md"
  python3 -c 'import sys; open(sys.argv[1],"a").write("x\n"*400)' "$TASK/1.step/Task.md"
  run "$LINT" "$TASK"
  [ "$status" -eq 0 ] || { echo "$output"; return 1; }
}

@test "## Budgets moves a step's ceiling" {
  printf '## Scale\n\nfull\n\n## Budgets\n\nTask.md: 120\n' >"$PROJ/CLAUDE-spine-toolkit.md"
  epic; step_task "$TASK/1.step" 120
  run "$LINT" --task-docs "$TASK"
  [ "$status" -eq 0 ] || { echo "$output"; return 1; }
  step_task "$TASK/1.step" 121
  run "$LINT" --task-docs "$TASK"
  [ "$status" -eq 1 ]
}

@test "## Budgets moves a lite ceiling, and only its number" {
  printf '## Scale\n\nlite\n\n## Budgets\n\nPlan.md: 300\n' >"$PROJ/CLAUDE-spine-toolkit.md"
  lines "$TASK/Plan.md" 250
  run "$LINT" "$TASK"
  [ "$status" -eq 0 ] || { echo "$output"; return 1; }
  printf '## Scale\n\nfull\n\n## Budgets\n\nPlan.md: 10\n' >"$PROJ/CLAUDE-spine-toolkit.md"
  run "$LINT" "$TASK"
  [ "$status" -eq 0 ] || { echo "a budget made a full task measured: $output"; return 1; }
}

@test "an unrecognized budget keeps the default and is reported" {
  printf '## Scale\n\nlite\n\n## Budgets\n\nPlan.md: many\nNotes.md: 10\n' >"$PROJ/CLAUDE-spine-toolkit.md"
  lines "$TASK/Plan.md" 201
  run "$LINT" "$TASK"
  [ "$status" -eq 1 ]
  case "$output" in *"budget 'Plan.md: many' not recognized"*) ;; *) echo "$output"; return 1 ;; esac
  case "$output" in *"budget 'Notes.md: 10' not recognized"*) ;; *) echo "$output"; return 1 ;; esac
}

@test "the template's guidance under ## Budgets is not a budget" {
  awk '/^## Budgets$/{f=1} f&&/^## /&&!/^## Budgets$/{exit} f' "$ROOT/templates/claude-toolkit-md/en.md" >>"$PROJ/CLAUDE-spine-toolkit.md"
  lines "$TASK/Plan.md" 199
  run "$LINT" "$TASK"
  [ "$status" -eq 0 ] || { echo "$output"; return 1; }
  case "$output" in *"not recognized"*) echo "$output"; return 1 ;; esac
}

@test "--budgets prints the resolved map in the contract's brace syntax" {
  printf '## Budgets\n\nTask.md: 120\n' >"$PROJ/CLAUDE-spine-toolkit.md"
  run "$LINT" --budgets "$TASK"
  [ "$status" -eq 0 ]
  [ "$output" = "{Done.md: 80, Plan.md: 200, Reproduce.md: 120, Review.md: 120, Task.md: 120, Validation.md: 100}" ] \
    || { echo "$output"; return 1; }
}

@test "an unknown flag is a usage error" {
  run "$LINT" --bogus "$TASK"
  [ "$status" -eq 2 ]
}

@test "the scale convention sends a project's Budgets through the script" {
  C="$ROOT/conventions/task-scale.md"
  sect="$(awk '/^## Budgets are measured$/{f=1;next} f&&/^## /{exit} f' "$C")"
  grep -qF -- '--budgets' <<<"$sect" || { echo "the convention does not say how a ceiling reaches an agent"; return 1; }
  grep -qF 'at every scale' <<<"$sect" || { echo "the convention still reads every ceiling as lite-only"; return 1; }
}

@test "every profile script reads the ceilings from the contract's budgets" {
  n=0
  for f in "$ROOT"/workflows/profile-*.js; do
    n=$((n + 1))
    grep -qF 'A.budgets' "$f" || { echo "$(basename "$f"): the prelude ignores budgets"; return 1; }
    grep -qF '${BUDGETS[file]}' "$f" || { echo "$(basename "$f"): cap() still names the default"; return 1; }
  done
  [ "$n" -eq 7 ] || { echo "scanned $n script(s), expected 7"; return 1; }
}

@test "the four phased Method B skills read the ceilings from the contract" {
  for p in feature bug refactor test; do
    grep -qF "Read the ceilings from the contract's \`budgets\` field" "$ROOT/skills/workflow-$p/SKILL.md" \
      || { echo "workflow-$p/SKILL.md still reads the ceilings from the script's table"; return 1; }
  done
}
