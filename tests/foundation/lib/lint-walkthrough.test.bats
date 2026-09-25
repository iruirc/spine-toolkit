#!/usr/bin/env bats
# A refresh that only ever appends kept sections of commits a reset and a squash had dropped, and
# the Done agent called the file consistent. This lint is the measurement that claim never had.

setup() {
  ROOT="$(cd -- "$(dirname -- "$BATS_TEST_FILENAME")/../../.." && pwd)"
  LINT="$ROOT/scripts/lint-walkthrough.sh"
  PROJ="$BATS_TEST_TMPDIR/proj"
  TASK="$PROJ/Tasks/ACTIVE/001-x"
  mkdir -p "$TASK"
  printf '## Paths\n' >"$PROJ/CLAUDE-spine-toolkit.md"
  printf 'Tasks/\n' >"$PROJ/.gitignore"
  git -C "$PROJ" init -q -b main
  commit .gitignore
  "$ROOT/scripts/task-ranges.sh" record "$TASK"
  commit a.txt; A1="$(git -C "$PROJ" rev-parse --short HEAD)"
  commit b.txt; A2="$(git -C "$PROJ" rev-parse --short HEAD)"
  commit c.txt; GONE="$(git -C "$PROJ" rev-parse --short HEAD)"
  git -C "$PROJ" reset -q --hard HEAD~1
}

commit() {
  echo "$1 $RANDOM" >>"$PROJ/$1"
  git -C "$PROJ" add -- "$1"
  git -C "$PROJ" -c user.name=t -c user.email=t@t commit -qm "$1"
}

walkthrough() { printf '# Walkthrough\n[COVERS] = %s..%s\n\n## What changed\n\n1. x\n\n## Commits\n\n%s\n\n## How it works\n\n- `%s` is only named here.\n' "$A1" "$A2" "$1" "$GONE" >"$TASK/Walkthrough.md"; }

@test "a deep section and a bookkeeping range naming a dropped commit are findings" {
  walkthrough "$(printf '### 1. `%s` — first\n\n- `%s` inside a section is prose, not a log line.\n\n### 2. `%s` — dropped\n\n### Bookkeeping\n\n- `%s..%s` — two commits.' "$A1" "$GONE" "$GONE" "$A2" "$GONE")"
  run "$LINT" "$TASK"
  [ "$status" -eq 1 ] || { echo "$status $output"; return 1; }
  [ "$output" = "$(printf 'Walkthrough.md: %s (### 2) is not in the task'"'"'s history\nWalkthrough.md: %s (Bookkeeping) is not in the task'"'"'s history' "$GONE" "$GONE")" ] \
    || { echo "$output"; return 1; }
}

@test "a brief log line naming a dropped commit is a finding" {
  walkthrough "$(printf -- '- `%s` `feat: a` — first.\n- `%s` `feat: c` — dropped.' "$A1" "$GONE")"
  run "$LINT" "$TASK"
  [ "$status" -eq 1 ] || { echo "$status $output"; return 1; }
  [ "$output" = "Walkthrough.md: $GONE (brief) is not in the task's history" ] || { echo "$output"; return 1; }
}

@test "grouped and prefixed headings and multi-sha lines are read whole" {
  walkthrough "$(printf '### 10–14. `%s`, `%s` — grouped\n\n### 18. app **`%s`** — prefixed\n\n### Bookkeeping\n\n- `%s`, `%s` (`app`) — two lines.' "$A1" "$GONE" "$GONE" "$A2" "$GONE")"
  run "$LINT" "$TASK"
  [ "$status" -eq 1 ] || { echo "$status $output"; return 1; }
  [ "$output" = "$(printf 'Walkthrough.md: %s (### 10–14) is not in the task'"'"'s history\nWalkthrough.md: %s (### 18) is not in the task'"'"'s history\nWalkthrough.md: %s (Bookkeeping) is not in the task'"'"'s history' "$GONE" "$GONE" "$GONE")" ] \
    || { echo "$output"; return 1; }
}

@test "a longer fence holding a shorter one does not hide what follows it" {
  walkthrough "$(printf '### 1. `%s` — first\n\n````markdown\n```swift\nlet x = 1\n````\n\n### 2. `%s` — dropped' "$A1" "$GONE")"
  run "$LINT" "$TASK"
  [ "$status" -eq 1 ] || { echo "$status $output"; return 1; }
  [ "$output" = "Walkthrough.md: $GONE (### 2) is not in the task's history" ] || { echo "$output"; return 1; }
}

@test "a file whose log is the task's history passes silently" {
  walkthrough "$(printf '### 1. `%s` — first\n\n### Bookkeeping\n\n- `%s` — one commit.' "$A1" "$A2")"
  run "$LINT" "$TASK"
  [ "$status" -eq 0 ] || { echo "$status $output"; return 1; }
  [ -z "$output" ] || { echo "$output"; return 1; }
}

@test "no walkthrough, no base and an epic are not measured" {
  run "$LINT" "$TASK"
  [ "$status" -eq 0 ] || { echo "no file: $status $output"; return 1; }
  walkthrough "$(printf '### 1. `%s` — dropped' "$GONE")"
  printf '[TASK_TYPE] = [EPIC]\n' >"$TASK/Task.md"
  run "$LINT" "$TASK"
  [ "$status" -eq 0 ] || { echo "epic: $status $output"; return 1; }
  printf '[TASK_TYPE] = [FEATURE]\n' >"$TASK/Task.md"
  rm "$TASK/Base.md"
  run "$LINT" "$TASK"
  [ "$status" -eq 0 ] || { echo "no base: $status $output"; return 1; }
}

@test "a usage error exits 2" {
  run "$LINT"
  [ "$status" -eq 2 ] || { echo "no args: $status"; return 1; }
  run "$LINT" "$BATS_TEST_TMPDIR/nowhere"
  [ "$status" -eq 2 ] || { echo "no dir: $status"; return 1; }
}
