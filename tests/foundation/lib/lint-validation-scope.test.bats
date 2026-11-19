#!/usr/bin/env bats
# A Validation that ran the project's own repository and never looked at the package next to it
# passed twice and left the red test to Review. This lint is the measurement the validator's own
# word was not: every repository the task touched has a row, and a row's count is the validator's own.

setup() {
  ROOT="$(cd -- "$(dirname -- "$BATS_TEST_FILENAME")/../../.." && pwd)"
  LINT="$ROOT/scripts/lint-validation-scope.sh"
  TR="$ROOT/scripts/task-ranges.sh"
  PROJ="$BATS_TEST_TMPDIR/proj"
  TASK="$PROJ/Tasks/ACTIVE/001-x"
  mkdir -p "$TASK/validation-evidence/t" "$PROJ/Packages/Core"
  printf '## Paths\n\n- External packages: /Packages/*\n' >"$PROJ/CLAUDE-spine-toolkit.md"
  printf 'Packages/\nTasks/\n' >"$PROJ/.gitignore"
  repo "$PROJ" .gitignore
  repo "$PROJ/Packages/Core" core.txt
  repo "$PROJ/Tasks" tasks.txt
  touch "$TASK/validation-evidence/t/app.log" "$TASK/validation-evidence/t/core.log"
  "$TR" record "$TASK"
}

repo() { git -C "$1" init -q -b main; commit "$1" "$2"; }

commit() { # $1 repository, $2 file inside it: one commit that touches only that file
  echo "$2 $RANDOM" >>"$1/$2"
  git -C "$1" add -- "$2"
  git -C "$1" -c user.name=t -c user.email=t@t commit -qm "$2"
}

track_tasks() { # the tasks folder tracked by the project repository instead of its own
  rm -rf "$PROJ/Tasks/.git"
  printf 'Packages/\n' >"$PROJ/.gitignore"
  commit "$PROJ" .gitignore
}

head7() { git -C "$1" rev-parse --short=7 HEAD; }

# row <repo> <module> <run> <tests> <head> <log>
row() { printf '| %s | %s | changed | %s | %s | %s | %s |\n' "$1" "$2" "$3" "$4" "$5" "$6"; }
# the two rows of a run that is current: the project's and Core's, each at its own HEAD
app_row() { row . App ran 12 "$(head7 "$PROJ")" validation-evidence/t/app.log; }
core_row() { row Packages/Core Core ran 7 "$(head7 "$PROJ/Packages/Core")" validation-evidence/t/core.log; }

# vmd <status> <row>...: a Validation.md with the header, the rows, Not reached and, for PASSED,
# the records the validator writes into the closing block
vmd() {
  local status="$1"
  shift
  {
    printf '[VALIDATION_STATUS] = %s\n\n## Summary\n\nBuilt and ran it.\n\n## Regression set\n\n' "$status"
    printf '| Repository | Module | Why | Run | Tests | HEAD | Log |\n|---|---|---|---|---|---|---|\n'
    printf '%s\n' "$@"
    printf '\nNot reached: none\n'
    if [ "$status" = PASSED ]; then printf '\n'; "$TR" tips "$TASK" --kind validated; fi
  } >"$TASK/Validation.md"
}

finds() { # the lint's output has a finding of this class
  grep -q "^Validation.md: $1:" <<<"$output" || { echo "no $1 finding: $output"; return 1; }
}

@test "a complete record passes" {
  commit "$PROJ" a.txt
  commit "$PROJ/Packages/Core" c.txt
  vmd PASSED "$(app_row)" "$(core_row)"
  run "$LINT" "$TASK"
  [ "$status" -eq 0 ] || { echo "$output"; return 1; }
  [ -z "$output" ] || { echo "$output"; return 1; }
}

@test "no regression set is a section finding" {
  printf '[VALIDATION_STATUS] = FAILED\n\n## Summary\n\nNothing.\n' >"$TASK/Validation.md"
  run "$LINT" "$TASK"
  [ "$status" -eq 1 ] || { echo "$status $output"; return 1; }
  finds section
}

@test "a table without the exact header is a section finding" {
  commit "$PROJ" a.txt
  vmd FAILED "$(app_row)"
  sed -i.bak 's/| Why |/| Reason |/' "$TASK/Validation.md"
  run "$LINT" "$TASK"
  [ "$status" -eq 1 ] || { echo "$status $output"; return 1; }
  finds section
}

@test "a repository with commits and no row is missing" {
  commit "$PROJ" a.txt
  commit "$PROJ/Packages/Core" c.txt
  vmd FAILED "$(app_row)"
  run "$LINT" "$TASK"
  [ "$status" -eq 1 ] || { echo "$status $output"; return 1; }
  finds missing
  grep -q 'missing:.*Packages/Core' <<<"$output" || { echo "$output"; return 1; }
  ! grep -q 'missing:.*[( ]\.[ )]' <<<"$output" || { echo "$output"; return 1; }
}

@test "uncommitted work counts as a change" {
  commit "$PROJ" a.txt
  echo more >>"$PROJ/Packages/Core/core.txt"
  vmd FAILED "$(app_row)"
  run "$LINT" "$TASK"
  [ "$status" -eq 1 ] || { echo "$status $output"; return 1; }
  grep -q 'missing:.*Packages/Core' <<<"$output" || { echo "$output"; return 1; }
}

@test "an unknown range still needs a row" {
  rm "$TASK/Base.md"
  git -C "$PROJ/Packages/Core" checkout -q --orphan fresh
  commit "$PROJ/Packages/Core" c.txt
  vmd FAILED "$(app_row)"
  run "$LINT" "$TASK"
  [ "$status" -eq 1 ] || { echo "$status $output"; return 1; }
  grep -q 'missing:.*Packages/Core' <<<"$output" || { echo "$output"; return 1; }
}

@test "a ran row needs a count and a log" {
  commit "$PROJ" a.txt
  vmd FAILED "$(row . App ran — "$(head7 "$PROJ")" validation-evidence/t/nope.log)"
  run "$LINT" "$TASK"
  [ "$status" -eq 1 ] || { echo "$status $output"; return 1; }
  finds count
  finds log
}

@test "a log outside the task folder is not a log of the task" {
  commit "$PROJ" a.txt
  : >"$BATS_TEST_TMPDIR/elsewhere.log"
  vmd FAILED "$(row . App ran 12 "$(head7 "$PROJ")" "$BATS_TEST_TMPDIR/elsewhere.log")"
  run "$LINT" "$TASK"
  [ "$status" -eq 1 ] || { echo "$status $output"; return 1; }
  finds log
}

@test "a ran row behind a code commit is stale" {
  commit "$PROJ" a.txt
  commit "$PROJ/Packages/Core" c.txt
  vmd FAILED "$(app_row)" "$(core_row)"
  commit "$PROJ/Packages/Core" d.txt
  run "$LINT" "$TASK"
  [ "$status" -eq 1 ] || { echo "$status $output"; return 1; }
  finds stale
  grep -q 'stale:.*Packages/Core' <<<"$output" || { echo "$output"; return 1; }
}

@test "a ran row whose HEAD is no commit of the repository is stale" {
  commit "$PROJ" a.txt
  vmd FAILED "$(row . App ran 12 deadbee validation-evidence/t/app.log)"
  run "$LINT" "$TASK"
  [ "$status" -eq 1 ] || { echo "$status $output"; return 1; }
  finds stale
}

@test "a commit only in the tasks folder leaves a ran row current" {
  track_tasks
  commit "$PROJ/Packages/Core" c.txt
  vmd PASSED "$(app_row)" "$(core_row)"
  commit "$PROJ" Tasks/ACTIVE/001-x/Notes.md
  run "$LINT" "$TASK"
  [ "$status" -eq 0 ] || { echo "$status $output"; return 1; }
  [ -z "$output" ] || { echo "$output"; return 1; }
}

@test "a wholly carried repository with new commits is a finding" {
  commit "$PROJ" a.txt
  old="$(head7 "$PROJ/Packages/Core")"
  commit "$PROJ/Packages/Core" c.txt
  vmd FAILED "$(app_row)" "$(row Packages/Core Core "carried $old" 7 "$old" validation-evidence/t/core.log)"
  run "$LINT" "$TASK"
  [ "$status" -eq 1 ] || { echo "$status $output"; return 1; }
  finds carried
  grep -q 'carried:.*Packages/Core' <<<"$output" || { echo "$output"; return 1; }
}

@test "a carried row next to a ran row of the same repository passes" {
  commit "$PROJ" a.txt
  old="$(head7 "$PROJ/Packages/Core")"
  commit "$PROJ/Packages/Core" c.txt
  vmd FAILED "$(app_row)" "$(row Packages/Core Storage "carried $old" 7 "$old" validation-evidence/t/core.log)" "$(core_row)"
  run "$LINT" "$TASK"
  [ "$status" -eq 0 ] || { echo "$status $output"; return 1; }
  [ -z "$output" ] || { echo "$output"; return 1; }
}

@test "a carried repository nothing changed in after its sha passes" {
  commit "$PROJ" a.txt
  old="$(head7 "$PROJ/Packages/Core")"
  vmd FAILED "$(app_row)" "$(row Packages/Core Core "carried $old" 7 "$old" validation-evidence/t/core.log)"
  run "$LINT" "$TASK"
  [ "$status" -eq 0 ] || { echo "$status $output"; return 1; }
}

@test "a carried sha off the history is a finding" {
  commit "$PROJ" a.txt
  vmd FAILED "$(app_row)" "$(row Packages/Core Core "carried deadbee" 7 deadbee validation-evidence/t/core.log)"
  run "$LINT" "$TASK"
  [ "$status" -eq 1 ] || { echo "$status $output"; return 1; }
  grep -q 'carried:.*deadbee' <<<"$output" || { echo "$output"; return 1; }
}

@test "PASSED without validated records is a record finding" {
  commit "$PROJ" a.txt
  commit "$PROJ/Packages/Core" c.txt
  vmd FAILED "$(app_row)" "$(core_row)"
  sed -i.bak 's/FAILED/PASSED/' "$TASK/Validation.md"
  run "$LINT" "$TASK"
  [ "$status" -eq 1 ] || { echo "$status $output"; return 1; }
  finds record
  vmd FAILED "$(app_row)" "$(core_row)"
  run "$LINT" "$TASK"
  [ "$status" -eq 0 ] || { echo "$status $output"; return 1; }
  ! grep -q 'record:' <<<"$output" || { echo "$output"; return 1; }
}

@test "a PASSED record that lacks one repository of the table names it" {
  commit "$PROJ" a.txt
  commit "$PROJ/Packages/Core" c.txt
  vmd PASSED "$(app_row)" "$(core_row)"
  grep -v '^\[VALIDATED_COMMIT\] = Packages/Core: ' "$TASK/Validation.md" >"$TASK/V2.md"
  mv "$TASK/V2.md" "$TASK/Validation.md"
  grep -q '^\[VALIDATED_COMMIT\] = \.: ' "$TASK/Validation.md"
  run "$LINT" "$TASK"
  [ "$status" -eq 1 ] || { echo "$status $output"; return 1; }
  grep -q 'record:.*Packages/Core' <<<"$output" || { echo "$output"; return 1; }
}

@test "a single-module project passes with one row" {
  printf '## Paths\n' >"$PROJ/CLAUDE-spine-toolkit.md"
  rm -rf "$PROJ/Packages" "$TASK/Base.md"
  "$TR" record "$TASK"
  commit "$PROJ" a.txt
  vmd PASSED "$(row . — ran 12 "$(head7 "$PROJ")" validation-evidence/t/app.log)"
  run "$LINT" "$TASK"
  [ "$status" -eq 0 ] || { echo "$status $output"; return 1; }
  [ -z "$output" ] || { echo "$output"; return 1; }
}

@test "a row naming a repository the task does not have is a section finding, not a crash" {
  commit "$PROJ" a.txt
  vmd FAILED "$(app_row)" "$(row Packages/Nope Nope ran 1 deadbee validation-evidence/t/core.log)"
  run "$LINT" "$TASK"
  [ "$status" -eq 1 ] || { echo "$status $output"; return 1; }
  finds section
}

@test "no Validation.md is nothing to measure" {
  run "$LINT" "$TASK"
  [ "$status" -eq 0 ] || { echo "$status $output"; return 1; }
  [ -z "$output" ] || { echo "$output"; return 1; }
}

@test "a repository git cannot read stops the lint with exit 2" {
  commit "$PROJ" a.txt
  vmd FAILED "$(app_row)"
  printf 'not an index' >"$PROJ/Packages/Core/.git/index"
  run "$LINT" "$TASK"
  [ "$status" -eq 2 ] || { echo "$status $output"; return 1; }
}

@test "usage: a task directory and nothing else" {
  run "$LINT"
  [ "$status" -eq 2 ]
  run "$LINT" "$TASK/nope"
  [ "$status" -eq 2 ]
}
