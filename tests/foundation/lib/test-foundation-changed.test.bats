#!/usr/bin/env bats
# `test-foundation.sh changed` picks the test files that name what a branch touched. Each test
# builds a small repository, changes one thing on a branch and reads the selection from
# `changed --list`; the script copied into the repository resolves its root there.

bats_require_minimum_version 1.5.0

setup() {
  ROOT="$(cd -- "$(dirname -- "$BATS_TEST_FILENAME")/../../.." && pwd)"
  R="$BATS_TEST_TMPDIR/r"
  mkdir -p "$R/scripts" "$R/tests/foundation/helpers" "$R/tests/foundation/lib"
  mkdir -p "$R/skills/task-report" "$R/skills/task-report-x"
  cp "$ROOT/scripts/test-foundation.sh" "$R/scripts/test-foundation.sh"
  echo a >"$R/scripts/a.sh"
  echo o >"$R/scripts/orphan.sh"
  echo s >"$R/skills/task-report/SKILL.md"
  echo s >"$R/skills/task-report-x/SKILL.md"
  echo h >"$R/tests/foundation/helpers/h.bash"
  local lib="$R/tests/foundation/lib"
  printf '# names scripts/a.sh\n' >"$lib/a.test.bats"
  printf '# names skills/task-report/\n' >"$lib/report.test.bats"
  printf '# names skills/task-report-x\n' >"$lib/report-x.test.bats"
  printf '#!/usr/bin/env bats\n# changed: sweep\n' >"$lib/sweep.test.bats"
  printf '# names nothing\n' >"$lib/other.test.bats"
  git -C "$R" init -q -b main
  git -C "$R" add -A
  git -C "$R" -c user.name=t -c user.email=t@t commit -qm base
  git -C "$R" checkout -q -b work
}

commit() {
  git -C "$R" add -A
  git -C "$R" -c user.name=t -c user.email=t@t commit -qm "$1"
}

# Runs the copy of the script in the repository; stdout is $output, stderr is $stderr_text.
changed() {
  run --separate-stderr "$R/scripts/test-foundation.sh" changed --list
  stderr_text="${stderr:-}"
}

# The selection as file names, one per line, directories left whole.
names() {
  printf '%s\n' "$output" | sed '/^$/d' | while IFS= read -r p; do
    case "$p" in */tests/foundation/lib) echo "DIR" ;; *) basename "$p" ;; esac
  done
}

@test "a script selects the tests that name it" {
  echo more >>"$R/scripts/a.sh"
  changed
  [ "$status" -eq 0 ]
  [ "$(names)" = "a.test.bats" ]
}

@test "a skill file selects its skill's tests and the sweeps" {
  echo more >>"$R/skills/task-report/SKILL.md"
  changed
  [ "$status" -eq 0 ]
  [ "$(names)" = $'report.test.bats\nsweep.test.bats' ]
}

@test "a renamed script still selects the tests that name the old path" {
  git -C "$R" mv scripts/a.sh scripts/b.sh
  commit rename
  changed
  [ "$status" -eq 0 ]
  [ "$(names)" = "a.test.bats" ]
}

@test "an untracked file under skills selects the sweeps" {
  mkdir -p "$R/skills/new"
  echo n >"$R/skills/new/SKILL.md"
  changed
  [ "$status" -eq 0 ]
  [ "$(names)" = "sweep.test.bats" ]
}

@test "a changed test file selects itself" {
  echo more >>"$R/tests/foundation/lib/other.test.bats"
  changed
  [ "$status" -eq 0 ]
  [ "$(names)" = "other.test.bats" ]
}

@test "a helper change selects the whole suite" {
  echo more >>"$R/tests/foundation/helpers/h.bash"
  changed
  [ "$status" -eq 0 ]
  [ "$(names)" = "DIR" ]
}

@test "a file no test names is reported, not run" {
  echo more >>"$R/scripts/orphan.sh"
  changed
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  [[ "$stderr_text" == *"scripts/orphan.sh -> no test names it"* ]]
}

@test "nothing changed selects nothing" {
  changed
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  [[ "$stderr_text" == *"nothing differs"* ]]
}

@test "no merge base exits 2 and names TEST_BASE" {
  echo more >>"$R/scripts/a.sh"
  TEST_BASE=nope changed
  [ "$status" -eq 2 ]
  [[ "$stderr_text" == *"TEST_BASE"* ]]
}
