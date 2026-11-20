#!/usr/bin/env bats
# A task repository behind a Tasks link, the project's SPINE.md above the link and nothing above the
# task's physical path. Through the link every core script that takes a task folder finds the
# config; the physical path, spelled through Tasks by task-dir.sh, is the same task; handed on bare,
# the resolver stops. A lint that resolved the path itself before asking task-ranges.sh or the
# resolver lost the config on every Validation and Review of such a task.
#
# Two layouts, the link pointing down and up:
#   down/proj/Tasks -> ../proj-tasks
#   up/a/b/proj/Tasks -> ../../Tasks

bats_require_minimum_version 1.5.0

setup() {
  ROOT="$(cd -- "$(dirname -- "$BATS_TEST_FILENAME")/../../.." && pwd)"
  S="$ROOT/scripts"
  W="$BATS_TEST_TMPDIR/work space"
  build "$W/down/proj" "$W/down/proj-tasks" ../proj-tasks
  build "$W/up/a/b/proj" "$W/up/a/Tasks" ../../Tasks
}

repo() { git -C "$1" init -q -b main; commit "$1" "$2"; }

commit() {
  echo "$2 $RANDOM" >>"$1/$2"
  git -C "$1" add -- "$2"
  git -C "$1" -c user.name=t -c user.email=t@t commit -qm "$2"
}

# build <project root> <physical task repository> <link target>: both repositories, the task, its
# Base.md, and one commit in the project after it.
build() {
  local p="$1" r="$2"
  mkdir -p "$p/Docs" "$r/ACTIVE/007-alpha"
  ln -s "$3" "$p/Tasks"
  printf '# Project\n' >"$p/SPINE.md"
  printf 'Tasks\n' >"$p/.gitignore"
  printf '# Report\n\nTask 007-alpha.\n\n## Where sources disagree\n\nNothing.\n' >"$p/Docs/Report.md"
  git -C "$p" init -q -b main
  git -C "$p" add SPINE.md .gitignore Docs
  git -C "$p" -c user.name=t -c user.email=t@t commit -qm init
  printf '[TASK_TYPE] = [FEATURE]\n' >"$r/ACTIVE/007-alpha/Task.md"
  repo "$r" tasks.txt
  "$S/task-ranges.sh" record "$p/Tasks/ACTIVE/007-alpha"
  commit "$p" a.txt
}

# layouts: "<project root>|<physical task repository>"
layouts() { printf '%s\n' "$W/down/proj|$W/down/proj-tasks" "$W/up/a/b/proj|$W/up/a/Tasks"; }

@test "task-dir.sh spells the physical path through Tasks" {
  while IFS='|' read -r P R; do
    run --separate-stderr "$S/task-dir.sh" "$R/ACTIVE/007-alpha" --from "$P"
    [ "$status" -eq 0 ] && [ "$output" = "$P/Tasks/ACTIVE/007-alpha" ] || { echo "$P: $status $output $stderr"; return 1; }
  done < <(layouts)
}

@test "the resolver: the project's config through the link, a stop on the physical path" {
  while IFS='|' read -r P R; do
    run --separate-stderr "$S/resolve-settings.sh" json "$P/Tasks/ACTIVE/007-alpha"
    [ "$status" -eq 0 ] || { echo "$P: $status $stderr"; return 1; }
    cfg="$(python3 -c 'import json,sys; print(json.load(sys.stdin)["project_config"])' <<<"$output")"
    [ "$cfg" -ef "$P/SPINE.md" ] || { echo "$P: $cfg"; return 1; }
    run --separate-stderr "$S/resolve-settings.sh" json "$R/ACTIVE/007-alpha"
    [ "$status" -eq 2 ] || { echo "$P: $status"; return 1; }
    grep -qF 'no project config (SPINE.md) at or above' <<<"$stderr" || { echo "$P: $stderr"; return 1; }
  done < <(layouts)
}

@test "task-ranges.sh ranges answers through the link" {
  while IFS='|' read -r P R; do
    run --separate-stderr "$S/task-ranges.sh" ranges "$P/Tasks/ACTIVE/007-alpha" --since base
    [ "$status" -eq 0 ] || { echo "$P: $status $stderr"; return 1; }
    python3 -c 'import json,sys; r=json.load(sys.stdin)["repos"]; sys.exit(0 if r["."]["commits"] == 1 else 1)' <<<"$output" \
      || { echo "$P: $output"; return 1; }
  done < <(layouts)
}

@test "lint-validation-scope.sh answers through the link" {
  while IFS='|' read -r P R; do
    t="$P/Tasks/ACTIVE/007-alpha"
    printf '[VALIDATION_STATUS] = FAILED\n\n## Regression set\n\n| Repository | Module | Why | Run | Tests | HEAD | Log |\n|---|---|---|---|---|---|---|\n' >"$t/Validation.md"
    run --separate-stderr "$S/lint-validation-scope.sh" "$t"
    [ "$status" -eq 1 ] || { echo "$P: $status $output $stderr"; return 1; }
    grep -qx 'Validation.md: missing: \. has changes and no row (## Regression set)' <<<"$output" || { echo "$P: $output"; return 1; }
  done < <(layouts)
}

@test "lint-report-links.sh finds the project root through the link" {
  while IFS='|' read -r P R; do
    t="$P/Tasks/ACTIVE/007-alpha"
    printf '# Plan\n\n[REPORT_DECISION] = needed\n[REPORT_PATH] = Docs/Report.md\n' >"$t/Plan.md"
    run --separate-stderr "$S/lint-report-links.sh" "$t"
    [ "$status" -ne 2 ] || { echo "$P: $status $output $stderr"; return 1; }
    ! grep -qF 'no project config' <<<"$output$stderr" || { echo "$P: $output $stderr"; return 1; }
  done < <(layouts)
}
