#!/usr/bin/env bats
# Every setting a task runs with comes from one chain and one reader (scripts/resolve-settings.sh).
# The chain is what a project's choice travels along; a chain resolved in prose cannot be tested,
# which is why five surfaces used to resolve it five ways.

setup() {
  ROOT="$(cd -- "$(dirname -- "$BATS_TEST_FILENAME")/../../.." && pwd)"
  RESOLVE="$ROOT/scripts/resolve-settings.sh"
  PROJ="$BATS_TEST_TMPDIR/proj"
  TASK="$PROJ/Tasks/ACTIVE/042-a-task"
  mkdir -p "$TASK"
  printf '# CLAUDE-spine-toolkit.md\n\n## Mode\n\nmanual\n' >"$PROJ/CLAUDE-spine-toolkit.md"
  printf '[TASK_TYPE] = [BUG]\n[NEED_TEST] = [true]\n' >"$TASK/Task.md"
  ERR="$BATS_TEST_TMPDIR/err"
}

field() { python3 -c 'import json,sys; print(json.load(sys.stdin)[sys.argv[1]])' "$1"; }
source_of() { python3 -c 'import json,sys; print(json.load(sys.stdin)["sources"][sys.argv[1]])' "$1"; }
map_value() { python3 -c 'import json,sys; print(json.load(sys.stdin)[sys.argv[1]][sys.argv[2]])' "$1" "$2"; }

@test "a project that says nothing resolves every field to its default" {
  run "$RESOLVE" json "$TASK"
  [ "$status" -eq 0 ]
  [ "$(field mode <<<"$output")" = manual ] || { echo "$output"; return 1; }
  [ "$(field scale <<<"$output")" = full ] || { echo "$output"; return 1; }
  [ "$(field walkthrough <<<"$output")" = deep ] || { echo "$output"; return 1; }
  [ "$(field drive_app <<<"$output")" = auto ] || { echo "$output"; return 1; }
  [ "$(field manual_checks <<<"$output")" = auto ] || { echo "$output"; return 1; }
  [ "$(field driver <<<"$output")" = auto ] || { echo "$output"; return 1; }
  [ "$(field phase_verification <<<"$output")" = proportional ] || { echo "$output"; return 1; }
  [ "$(field docs_lever <<<"$output")" = on ] || { echo "$output"; return 1; }
  [ "$(field settings_report <<<"$output")" = diff ] || { echo "$output"; return 1; }
}

@test "the task beats the project, and the source says which won" {
  printf '## Validation\n\ndrive_app: auto\nphase_verification: proportional\n' >>"$PROJ/CLAUDE-spine-toolkit.md"
  printf '[TASK_TYPE] = [BUG]\n[DRIVE_APP] = [off]\n' >"$TASK/Task.md"
  run "$RESOLVE" json "$TASK"
  [ "$(field drive_app <<<"$output")" = off ] || { echo "$output"; return 1; }
  [ "$(source_of drive_app <<<"$output")" = task ] || { echo "$output"; return 1; }
  [ "$(source_of phase_verification <<<"$output")" = project ] || { echo "$output"; return 1; }
}

@test "a lite task writes no walkthrough, and the source names the field that decided" {
  printf '## Reporting\n\nwalkthrough: deep\n' >>"$PROJ/CLAUDE-spine-toolkit.md"
  printf '[TASK_TYPE] = [BUG]\n[SCALE] = [lite]\n' >"$TASK/Task.md"
  run "$RESOLVE" json "$TASK"
  [ "$(field walkthrough <<<"$output")" = off ] || { echo "$output"; return 1; }
  [ "$(source_of walkthrough <<<"$output")" = scale ] || { echo "$output"; return 1; }
}

@test "a lite task that asks for a walkthrough gets one" {
  printf '[TASK_TYPE] = [BUG]\n[SCALE] = [lite]\n[WALKTHROUGH] = [brief]\n' >"$TASK/Task.md"
  run "$RESOLVE" json "$TASK"
  [ "$(field walkthrough <<<"$output")" = brief ] || { echo "$output"; return 1; }
  [ "$(source_of walkthrough <<<"$output")" = task ] || { echo "$output"; return 1; }
}

@test "a step inherits the epic and overrides it key by key" {
  EPIC="$PROJ/Tasks/ACTIVE/050-an-epic"
  STEP="$EPIC/1-first.step"
  mkdir -p "$STEP"
  printf '[TASK_TYPE] = [EPIC]\n[DRIVE_APP] = [off]\n[MANUAL_CHECKS] = [always]\n' >"$EPIC/Task.md"
  printf '[TASK_TYPE] = [FEATURE]\n[MANUAL_CHECKS] = [auto]\n' >"$STEP/Task.md"
  run "$RESOLVE" json "$STEP"
  [ "$(field drive_app <<<"$output")" = off ] || { echo "$output"; return 1; }
  [ "$(source_of drive_app <<<"$output")" = epic ] || { echo "$output"; return 1; }
  [ "$(field manual_checks <<<"$output")" = auto ] || { echo "$output"; return 1; }
  [ "$(source_of manual_checks <<<"$output")" = task ] || { echo "$output"; return 1; }
}

@test "an unusable entry is reported, skipped, and the next source applies" {
  printf '## Validation\n\ndrive_app: off\n' >>"$PROJ/CLAUDE-spine-toolkit.md"
  printf '[TASK_TYPE] = [BUG]\n[DRIVE_APP] = [maybe]\n' >"$TASK/Task.md"
  out="$("$RESOLVE" json "$TASK" 2>"$ERR")"
  [ "$(field drive_app <<<"$out")" = off ] || { echo "$out"; return 1; }
  grep -qF "Task.md [DRIVE_APP]: 'maybe' not recognized, skipped" "$ERR" || { cat "$ERR"; return 1; }
}

@test "a commented-out template line is documentation, not a value" {
  printf '[TASK_TYPE] = [BUG]\n# [DRIVE_APP] = [off]\n' >"$TASK/Task.md"
  run "$RESOLVE" json "$TASK"
  [ "$(field drive_app <<<"$output")" = auto ] || { echo "$output"; return 1; }
  [ "$(source_of drive_app <<<"$output")" = default ] || { echo "$output"; return 1; }
}

@test "show prints the fields that were chosen, in Task.md syntax, and counts the rest" {
  printf '## Mode\n\nauto\n' >"$PROJ/CLAUDE-spine-toolkit.md"
  printf '[TASK_TYPE] = [BUG]\n[SCALE] = [lite]\n' >"$TASK/Task.md"
  run "$RESOLVE" show "$TASK"
  [ "$status" -eq 0 ]
  grep -qE '^\[SCALE\] += \[lite\] +# task$' <<<"$output" || { echo "$output"; return 1; }
  grep -qE '^\[WORKFLOW_MODE\] += \[auto\] +# project$' <<<"$output" || { echo "$output"; return 1; }
  grep -qE '^# [0-9]+ more at their default$' <<<"$output" || { echo "$output"; return 1; }
}

@test "raw prints a block's value lines and drops its guidance" {
  printf '## Paths\n\n- External packages: Packages/*\n\n(guidance\nover two lines)\n' >"$PROJ/CLAUDE-spine-toolkit.md"
  run "$RESOLVE" raw "$PROJ" Paths
  [ "$status" -eq 0 ]
  [ "$output" = "- External packages: Packages/*" ] || { echo "$output"; return 1; }
}

@test "a usage error exits 2" {
  run "$RESOLVE" json
  [ "$status" -eq 2 ]
  run "$RESOLVE" json "$PROJ/no-such-dir"
  [ "$status" -eq 2 ]
}

@test "settings_report reads full from the Progress block, and progress still reads its own first line" {
  printf '## Progress\n\nlive\nsettings: full\n' >>"$PROJ/CLAUDE-spine-toolkit.md"
  run "$RESOLVE" json "$TASK"
  [ "$(field settings_report <<<"$output")" = full ] || { echo "$output"; return 1; }
  [ "$(source_of settings_report <<<"$output")" = project ] || { echo "$output"; return 1; }
  [ "$(field progress <<<"$output")" = live ] || { echo "$output"; return 1; }
}

@test "two Task.md MODELS lines fold in file order, the last entry for a repeated key wins" {
  printf '[TASK_TYPE] = [BUG]\n[MODELS] = [architect: opus]\n[MODELS] = [tester: haiku, architect: sonnet]\n' >"$TASK/Task.md"
  run "$RESOLVE" json "$TASK"
  [ "$status" -eq 0 ]
  [ "$(map_value models architect <<<"$output")" = sonnet ] || { echo "$output"; return 1; }
  [ "$(map_value models tester <<<"$output")" = haiku ] || { echo "$output"; return 1; }
}

@test "a task's model key beats the project's, and a key the task does not name keeps the project's value" {
  printf '## Models\n\narchitect: opus\nreviewer: opus\n' >"$PROJ/CLAUDE-spine-toolkit.md"
  printf '[TASK_TYPE] = [BUG]\n[MODELS] = [architect: sonnet]\n' >"$TASK/Task.md"
  run "$RESOLVE" json "$TASK"
  [ "$(map_value models architect <<<"$output")" = sonnet ] || { echo "$output"; return 1; }
  [ "$(map_value models reviewer <<<"$output")" = opus ] || { echo "$output"; return 1; }
}

@test "a task's platform model entry is skipped silently, leaving the project's value in place" {
  printf '## Models\n\narchitect: opus\n' >"$PROJ/CLAUDE-spine-toolkit.md"
  printf '[TASK_TYPE] = [BUG]\n[MODELS] = [architect: platform]\n' >"$TASK/Task.md"
  out="$("$RESOLVE" json "$TASK" 2>"$ERR")"
  [ ! -s "$ERR" ] || { cat "$ERR"; return 1; }
  [ "$(map_value models architect <<<"$out")" = opus ] || { echo "$out"; return 1; }
}

@test "a step's [MODELS] falls back to the epic's Task.md" {
  EPIC="$PROJ/Tasks/ACTIVE/050-an-epic"
  STEP="$EPIC/1-first.step"
  mkdir -p "$STEP"
  printf '[TASK_TYPE] = [EPIC]\n[MODELS] = [architect: opus]\n' >"$EPIC/Task.md"
  printf '[TASK_TYPE] = [FEATURE]\n' >"$STEP/Task.md"
  run "$RESOLVE" json "$STEP"
  [ "$(map_value models architect <<<"$output")" = opus ] || { echo "$output"; return 1; }
  [ "$(source_of models <<<"$output")" = epic ] || { echo "$output"; return 1; }
}

@test "a budgets override is recorded with its own source, and show prints it" {
  printf '## Budgets\n\nPlan.md: 150\n' >"$PROJ/CLAUDE-spine-toolkit.md"
  run "$RESOLVE" json "$TASK"
  [ "$status" -eq 0 ]
  [ "$(map_value budgets Plan.md <<<"$output")" = 150 ] || { echo "$output"; return 1; }
  [ "$(source_of budgets <<<"$output")" = project ] || { echo "$output"; return 1; }
  [ "$(source_of budgets.Plan.md <<<"$output")" = project ] || { echo "$output"; return 1; }
  run "$RESOLVE" show "$TASK"
  grep -qE '^\[BUDGETS\] += \[Plan\.md: 150\] +# project$' <<<"$output" || { echo "$output"; return 1; }
}

@test "a budgets override equal to the default is still the project's choice, not the default's" {
  printf '## Budgets\n\nPlan.md: 200\n' >"$PROJ/CLAUDE-spine-toolkit.md"
  run "$RESOLVE" json "$TASK"
  [ "$(map_value budgets Plan.md <<<"$output")" = 200 ] || { echo "$output"; return 1; }
  [ "$(source_of budgets <<<"$output")" = project ] || { echo "$output"; return 1; }
  [ "$(source_of budgets.Plan.md <<<"$output")" = project ] || { echo "$output"; return 1; }
}

@test "no script but the resolver parses the config file" {
  n=0
  for f in "$ROOT"/scripts/*.sh; do
    case "$(basename "$f")" in resolve-settings.sh) continue ;; esac
    n=$((n + 1))
    ! grep -q "CLAUDE-spine-toolkit.md'" "$f" || { echo "$(basename "$f") parses the config itself"; return 1; }
  done
  [ "$n" -ge 10 ] || { echo "scanned $n script(s), expected at least 10"; return 1; }
}
