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
  printf '## Task defaults\n\n[SCALE] = [lite]\n' >"$PROJ/CLAUDE-spine-toolkit.md"
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
  printf '## Task defaults\n\n[SCALE] = [full]\n' >"$PROJ/CLAUDE-spine-toolkit.md"
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

@test "an absent [SCALE] means full, and full is never measured" {
  lines "$TASK/Plan.md" 300
  printf '# CLAUDE-spine-toolkit.md\n\n## Task defaults\n\n[WORKFLOW_MODE] = [manual]\n' >"$PROJ/CLAUDE-spine-toolkit.md"
  run "$LINT" "$TASK"
  [ "$status" -eq 0 ]
}

@test "an unrecognized [SCALE] resolves to full and is reported, not silent" {
  lines "$TASK/Plan.md" 300
  printf '## Task defaults\n\n[SCALE] = [garbage]\n' >"$PROJ/CLAUDE-spine-toolkit.md"
  run "$LINT" "$TASK"
  [ "$status" -eq 0 ]
  case "$output" in *"garbage"*"not recognized"*) ;; *) echo "$output"; return 1 ;; esac
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

@test "the ceilings in the resolver and in the workflow prelude are one table" {
  verdict="$(python3 - "$ROOT/scripts/resolve-settings.sh" "$ROOT/workflows/profile-bug.js" <<'PY'
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
  printf '## Task defaults\n\n[SCALE] = [full]\n' >"$PROJ/CLAUDE-spine-toolkit.md"
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

@test "[BUDGETS] moves a step's ceiling" {
  printf '## Project settings\n\n[BUDGETS] = [Task.md: 120]\n\n## Task defaults\n\n[SCALE] = [full]\n' >"$PROJ/CLAUDE-spine-toolkit.md"
  epic; step_task "$TASK/1.step" 120
  run "$LINT" --task-docs "$TASK"
  [ "$status" -eq 0 ] || { echo "$output"; return 1; }
  step_task "$TASK/1.step" 121
  run "$LINT" --task-docs "$TASK"
  [ "$status" -eq 1 ]
}

@test "[BUDGETS] moves a lite ceiling, and only its number" {
  printf '## Project settings\n\n[BUDGETS] = [Plan.md: 300]\n\n## Task defaults\n\n[SCALE] = [lite]\n' >"$PROJ/CLAUDE-spine-toolkit.md"
  lines "$TASK/Plan.md" 250
  run "$LINT" "$TASK"
  [ "$status" -eq 0 ] || { echo "$output"; return 1; }
  printf '## Project settings\n\n[BUDGETS] = [Plan.md: 10]\n\n## Task defaults\n\n[SCALE] = [full]\n' >"$PROJ/CLAUDE-spine-toolkit.md"
  run "$LINT" "$TASK"
  [ "$status" -eq 0 ] || { echo "a budget made a full task measured: $output"; return 1; }
}

@test "an unrecognized budget keeps the default and is reported" {
  printf '## Project settings\n\n[BUDGETS] = [Plan.md: many, Notes.md: 10]\n\n## Task defaults\n\n[SCALE] = [lite]\n' >"$PROJ/CLAUDE-spine-toolkit.md"
  lines "$TASK/Plan.md" 201
  run "$LINT" "$TASK"
  [ "$status" -eq 1 ]
  case "$output" in *"[BUDGETS]: 'Plan.md: many' not recognized"*) ;; *) echo "$output"; return 1 ;; esac
  case "$output" in *"[BUDGETS]: 'Notes.md: 10' not recognized"*) ;; *) echo "$output"; return 1 ;; esac
}

@test "the template's own [BUDGETS] line is not a budget" {
  grep -F '[BUDGETS]' "$ROOT/templates/claude-toolkit-md/en.md" >>"$PROJ/CLAUDE-spine-toolkit.md"
  lines "$TASK/Plan.md" 199
  run "$LINT" "$TASK"
  [ "$status" -eq 0 ] || { echo "$output"; return 1; }
  case "$output" in *"not recognized"*) echo "$output"; return 1 ;; esac
}

@test "--budgets prints the resolved map in the contract's brace syntax" {
  printf '## Project settings\n\n[BUDGETS] = [Task.md: 120]\n' >"$PROJ/CLAUDE-spine-toolkit.md"
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

@test "--task-docs skips a step with [STATUS] = [DONE] even with no anchors" {
  epic; mkdir -p "$TASK/1.step"
  printf '[TASK_TYPE] = [FEATURE]\n[STATUS] = [DONE]\n' >"$TASK/1.step/Task.md"
  run "$LINT" --task-docs "$TASK"
  [ "$status" -eq 0 ] || { echo "$output"; return 1; }
}

@test "--task-docs measures a step with [STATUS] = [PENDING]" {
  epic; mkdir -p "$TASK/1.step"
  printf '[TASK_TYPE] = [FEATURE]\n[STATUS] = [PENDING]\n' >"$TASK/1.step/Task.md"
  run "$LINT" --task-docs "$TASK"
  [ "$status" -eq 1 ]
}

@test "--task-docs measures a step with [STATUS] = [TODO]" {
  epic; mkdir -p "$TASK/1.step"
  printf '[TASK_TYPE] = [FEATURE]\n[STATUS] = [TODO]\n' >"$TASK/1.step/Task.md"
  run "$LINT" --task-docs "$TASK"
  [ "$status" -eq 1 ]
}

@test "a budget value with a non-ASCII digit keeps the default and is reported, not a crash" {
  printf '## Project settings\n\n[BUDGETS] = [Plan.md: ²]\n' >"$PROJ/CLAUDE-spine-toolkit.md"
  run "$LINT" --budgets "$TASK"
  [ "$status" -eq 0 ] || { echo "$output"; return 1; }
  case "$output" in *"Plan.md: 200"*) ;; *) echo "$output"; return 1 ;; esac
  case "$output" in *"not recognized"*) ;; *) echo "$output"; return 1 ;; esac
}

@test "a lone hyphen or en dash under an anchor is reported as a bare dash" {
  epic; mkdir -p "$TASK/1.step"
  printf '[TASK_TYPE] = [FEATURE]\n\n## 3. [Task]\n\n### Expected behaviour\n\n-\n\n### Questions for Research\n\nwhere\n\n### Acceptance\n\n–\n' >"$TASK/1.step/Task.md"
  run "$LINT" --task-docs "$TASK"
  [ "$status" -eq 1 ]
  case "$output" in *'"### Expected behaviour" is a bare dash'*) ;; *) echo "$output"; return 1 ;; esac
  case "$output" in *'"### Acceptance" is a bare dash'*) ;; *) echo "$output"; return 1 ;; esac
}

@test "an anchor under ## 2. [Description] instead of ## 3. [Task] is reported missing" {
  epic; mkdir -p "$TASK/1.step"
  printf '[TASK_TYPE] = [FEATURE]\n\n## 2. [Description]\n\n### Expected behaviour\n\n| a | b |\n\n### Questions for Research\n\nwhere\n\n### Acceptance\n\ndone\n' >"$TASK/1.step/Task.md"
  run "$LINT" --task-docs "$TASK"
  [ "$status" -eq 1 ]
  case "$output" in *'anchor "### Expected behaviour" missing'*) ;; *) echo "$output"; return 1 ;; esac
  case "$output" in *'anchor "### Questions for Research" missing'*) ;; *) echo "$output"; return 1 ;; esac
  case "$output" in *'anchor "### Acceptance" missing'*) ;; *) echo "$output"; return 1 ;; esac
}

@test "--task-docs leaves the epic's own root Task.md alone" {
  epic; step_task "$TASK/1.step" 50
  run "$LINT" --task-docs "$TASK"
  [ "$status" -eq 0 ] || { echo "$output"; return 1; }
}

@test "--budgets keeps stdout to the map while a warning goes to stderr" {
  printf '## Project settings\n\n[BUDGETS] = [Plan.md: ²]\n' >"$PROJ/CLAUDE-spine-toolkit.md"
  out="$("$LINT" --budgets "$TASK" 2>/dev/null)"
  [ "$out" = "{Done.md: 80, Plan.md: 200, Reproduce.md: 120, Review.md: 120, Task.md: 100, Validation.md: 100}" ] \
    || { echo "$out"; return 1; }
}

@test "a pushed step states its ceilings from the same contract" {
  # A pushed step states its ceilings from the same contract the orchestrator measures against.
  block="$(sed -n '/const stepArgs/,/^    })$/p' "$ROOT/workflows/profile-epic.js")"
  grep -qF 'budgets: A.budgets' <<<"$block" || { echo "stepArgs never states its ceilings"; return 1; }
}

@test "the four phased Method B skills read the ceilings from the contract" {
  for p in feature bug refactor test; do
    grep -qF "Read the ceilings from the contract's \`budgets\` field" "$ROOT/skills/workflow-$p/SKILL.md" \
      || { echo "workflow-$p/SKILL.md still reads the ceilings from the script's table"; return 1; }
  done
}

# Copies the lint next to a stub resolve-settings.sh, so a resolver failure can be forced without
# touching the real script: ${BASH_SOURCE[0]} makes the lint look for its resolver beside itself.
broken_resolver() {
  cp "$LINT" "$BATS_TEST_TMPDIR/lint.sh"
  printf '#!/usr/bin/env bash\necho "boom: resolver exploded" >&2\nexit 2\n' >"$BATS_TEST_TMPDIR/resolve-settings.sh"
  chmod +x "$BATS_TEST_TMPDIR/resolve-settings.sh"
}

@test "a resolver failure is an error, not a default: measuring stops at exit 2, no silent pass" {
  broken_resolver
  lines "$TASK/Plan.md" 300
  run "$BATS_TEST_TMPDIR/lint.sh" "$TASK"
  [ "$status" -eq 2 ]
  case "$output" in *"boom: resolver exploded"*) ;; *) echo "$output"; return 1 ;; esac
  case "$output" in *"artifact budget passed"*) echo "still passed: $output"; return 1 ;; *) ;; esac
}

@test "a resolver failure is an error, not a default: --budgets stops at exit 2, never prints {}" {
  broken_resolver
  run "$BATS_TEST_TMPDIR/lint.sh" --budgets "$TASK"
  [ "$status" -eq 2 ]
  case "$output" in *"boom: resolver exploded"*) ;; *) echo "$output"; return 1 ;; esac
  [ "$output" != "{}" ] || { echo "printed an empty map"; return 1; }
}

@test "--budgets forwards only the resolver lines about the ceilings it asked for" {
  # The orchestrator announces every line this call prints as a budget problem, so a tuning typo
  # forwarded here reaches the user under the wrong name — and again from the tuning call.
  printf '## Project settings\n\n[BUDGETS] = [Plan.md: many]\n\n## Task defaults\n\n[MODELS] = [architect: gpt]\n' >"$PROJ/CLAUDE-spine-toolkit.md"
  run "$LINT" --budgets "$TASK"
  [ "$status" -eq 0 ] || { echo "$output"; return 1; }
  case "$output" in *"Plan.md: many' not recognized"*) ;; *) echo "dropped its own field: $output"; return 1 ;; esac
  case "$output" in *"architect: gpt"*) echo "forwarded another field's line: $output"; return 1 ;; *) ;; esac
}

@test "a resolver warning shared by two task dirs is printed once, not once per directory" {
  printf '## Project settings\n\n[BUDGETS] = [Plan.md: many]\n\n## Task defaults\n\n[SCALE] = [full]\n' >"$PROJ/CLAUDE-spine-toolkit.md"
  TASK2="$PROJ/Tasks/ACTIVE/043-b-task"
  mkdir -p "$TASK2"
  printf '[TASK_TYPE] = [BUG]\n' >"$TASK2/Task.md"
  run "$LINT" "$TASK" "$TASK2"
  [ "$status" -eq 0 ] || { echo "$output"; return 1; }
  n="$(printf '%s\n' "$output" | grep -c "Plan.md: many' not recognized")"
  [ "$n" -eq 1 ] || { echo "printed $n time(s): $output"; return 1; }
}
