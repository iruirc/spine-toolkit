#!/usr/bin/env bats
# Resolution step 1 finds the task folder and spells it through the session's Tasks. A task repository
# reached through a Tasks link has no config above its physical path, so a physical path handed on to
# the resolver runs the task on nothing: this script is where every way of naming a task becomes the
# one spelling the rest of the run uses.
#
# Two layouts, the link pointing down and up:
#   down/proj/Tasks -> ../proj-tasks
#   up/a/b/proj/Tasks -> ../../Tasks

bats_require_minimum_version 1.5.0

setup() {
  ROOT="$(cd -- "$(dirname -- "$BATS_TEST_FILENAME")/../../.." && pwd)"
  TD="$ROOT/scripts/task-dir.sh"
  W="$BATS_TEST_TMPDIR/work space"
  mkdir -p "$W/down/proj/src" "$W/down/proj-tasks" "$W/up/a/b/proj/src" "$W/up/a/Tasks" "$W/elsewhere"
  ln -s ../proj-tasks "$W/down/proj/Tasks"
  ln -s ../../Tasks "$W/up/a/b/proj/Tasks"
  for r in "$W/down/proj-tasks" "$W/up/a/Tasks"; do
    mkdir -p "$r/ACTIVE/007-alpha/02-core.step" "$r/ACTIVE/x"
    printf '[TASK_TYPE] = [EPIC]\n' >"$r/ACTIVE/007-alpha/Task.md"
    printf '[TASK_TYPE] = [FEATURE]\n' >"$r/ACTIVE/007-alpha/02-core.step/Task.md"
  done
  : >"$W/down/proj/SPINE.md"
  : >"$W/up/a/b/proj/SPINE.md"
}

# layouts: "<project root>|<physical task repository>"
layouts() { printf '%s\n' "$W/down/proj|$W/down/proj-tasks" "$W/up/a/b/proj|$W/up/a/Tasks"; }

@test "an id finds the root task through Tasks" {
  while IFS='|' read -r P R; do
    run --separate-stderr "$TD" 007 --from "$P"
    [ "$status" -eq 0 ] || { echo "$P: $status $stderr"; return 1; }
    [ "$output" = "$P/Tasks/ACTIVE/007-alpha" ] || { echo "$P: $output"; return 1; }
  done < <(layouts)
}

@test "a step is found by its full name and by its number" {
  while IFS='|' read -r P R; do
    for id in 02-core 02; do
      run --separate-stderr "$TD" "$id" --from "$P"
      [ "$status" -eq 0 ] || { echo "$P $id: $status $stderr"; return 1; }
      [ "$output" = "$P/Tasks/ACTIVE/007-alpha/02-core.step" ] || { echo "$P $id: $output"; return 1; }
    done
  done < <(layouts)
}

@test "--from below the project root finds the same Tasks" {
  while IFS='|' read -r P R; do
    run --separate-stderr "$TD" 007 --from "$P/src"
    [ "$output" = "$P/Tasks/ACTIVE/007-alpha" ] || { echo "$P: $status $output $stderr"; return 1; }
  done < <(layouts)
}

@test "--from defaults to the current directory" {
  while IFS='|' read -r P R; do
    cd "$P/src"
    run --separate-stderr "$TD" 007
    [ "$output" = "$P/Tasks/ACTIVE/007-alpha" ] || { echo "$P: $status $output $stderr"; return 1; }
  done < <(layouts)
}

@test "a path through the link is kept as given, normalized" {
  while IFS='|' read -r P R; do
    for given in "$P/Tasks/ACTIVE/007-alpha/" "$P/Tasks/ACTIVE/x/../007-alpha"; do
      run --separate-stderr "$TD" "$given" --from "$P"
      [ "$status" -eq 0 ] || { echo "$given: $status $stderr"; return 1; }
      [ "$output" = "$P/Tasks/ACTIVE/007-alpha" ] || { echo "$given: $output"; return 1; }
    done
  done < <(layouts)
}

@test "the physical path is spelled through Tasks" {
  while IFS='|' read -r P R; do
    run --separate-stderr "$TD" "$R/ACTIVE/007-alpha/02-core.step" --from "$P"
    [ "$status" -eq 0 ] || { echo "$P: $status $stderr"; return 1; }
    [ "$output" = "$P/Tasks/ACTIVE/007-alpha/02-core.step" ] || { echo "$P: $output"; return 1; }
  done < <(layouts)
}

@test "a relative path is read from the current directory, not from --from" {
  while IFS='|' read -r P R; do
    cd "$R/ACTIVE"
    run --separate-stderr "$TD" 007-alpha/ --from "$P"
    [ "$status" -eq 0 ] || { echo "$P: $status $stderr"; return 1; }
    [ "$output" = "$P/Tasks/ACTIVE/007-alpha" ] || { echo "$P: $output"; return 1; }
  done < <(layouts)
}

@test "a path outside Tasks is exit 5" {
  while IFS='|' read -r P R; do
    run --separate-stderr "$TD" "$W/elsewhere" --from "$P"
    [ "$status" -eq 5 ] || { echo "$P: $status $output"; return 1; }
    [ "$stderr" = "$W/elsewhere is not under $P/Tasks" ] || { echo "$P: $stderr"; return 1; }
  done < <(layouts)
}

@test "an unknown id is exit 3" {
  while IFS='|' read -r P R; do
    run --separate-stderr "$TD" 999 --from "$P"
    [ "$status" -eq 3 ] || { echo "$P: $status $output"; return 1; }
    [ "$stderr" = "not found: 999 under $P/Tasks" ] || { echo "$P: $stderr"; return 1; }
  done < <(layouts)
}

@test "two matches are exit 4 with both on stdout" {
  while IFS='|' read -r P R; do
    mkdir -p "$R/ACTIVE/008-beta/02-ui.step"
    run --separate-stderr "$TD" 02 --from "$P"
    [ "$status" -eq 4 ] || { echo "$P: $status $output"; return 1; }
    [ "$stderr" = "ambiguous: 02" ] || { echo "$P: $stderr"; return 1; }
    expected="$(printf '%s\n' "$P/Tasks/ACTIVE/007-alpha/02-core.step" "$P/Tasks/ACTIVE/008-beta/02-ui.step")"
    [ "$output" = "$expected" ] || { echo "$P: $output"; return 1; }
  done < <(layouts)
}

@test "no Tasks at or above --from is exit 2" {
  run --separate-stderr "$TD" 007 --from "$W"
  [ "$status" -eq 2 ] || { echo "$status $output"; return 1; }
  grep -qF "no Tasks folder at or above $W" <<<"$stderr" || { echo "$stderr"; return 1; }
}

@test "a dangling Tasks link and a loop under Tasks end with a diagnosis, not a hang" {
  mkdir -p "$W/broken"
  ln -s missing "$W/broken/Tasks"
  run --separate-stderr "$TD" 007 --from "$W/broken"
  [ "$status" -eq 2 ] || { echo "$status $output $stderr"; return 1; }
  ln -s . "$W/down/proj-tasks/ACTIVE/loop"
  run --separate-stderr "$TD" 007 --from "$W/down/proj"
  [ "$status" -eq 0 ] || { echo "$status $stderr"; return 1; }
  [ "$output" = "$W/down/proj/Tasks/ACTIVE/007-alpha" ] || { echo "$output"; return 1; }
}

@test "a path that is not a folder, and no argument, are exit 2" {
  run --separate-stderr "$TD" "$W/down/proj/Tasks/nope/" --from "$W/down/proj"
  [ "$status" -eq 2 ] || { echo "$status $output"; return 1; }
  run --separate-stderr "$TD"
  [ "$status" -eq 2 ] || { echo "$status $output"; return 1; }
}

@test "a full folder name is an id: a root task, an epic's N.step, and an exact name beats a longer one" {
  while IFS='|' read -r P R; do
    mkdir -p "$R/ACTIVE/007-alpha/2.step" "$R/ACTIVE/007-alpha-two"
    for pair in "007-alpha|$P/Tasks/ACTIVE/007-alpha" "02-core.step|$P/Tasks/ACTIVE/007-alpha/02-core.step" \
                "2.step|$P/Tasks/ACTIVE/007-alpha/2.step"; do
      run --separate-stderr "$TD" "${pair%%|*}" --from "$P"
      [ "$status" -eq 0 ] && [ "$output" = "${pair#*|}" ] || { echo "${pair%%|*}: $status $output $stderr"; return 1; }
    done
  done < <(layouts)
}

@test "the same N.step in two epics: ambiguous by name, found by the path the epic hands over" {
  while IFS='|' read -r P R; do
    mkdir -p "$R/ACTIVE/007-alpha/2.step" "$R/ACTIVE/008-beta/2.step"
    run --separate-stderr "$TD" 2.step --from "$P"
    [ "$status" -eq 4 ] || { echo "$P: $status $output"; return 1; }
    run --separate-stderr "$TD" "$P/Tasks/ACTIVE/008-beta/2.step" --from "$P"
    [ "$status" -eq 0 ] && [ "$output" = "$P/Tasks/ACTIVE/008-beta/2.step" ] || { echo "$P: $status $output"; return 1; }
  done < <(layouts)
}

@test "a dangling Tasks is a stop, not a reason to take a Tasks further up" {
  mkdir -p "$W/outer/Tasks/ACTIVE/007-alpha" "$W/outer/inner"
  ln -s missing "$W/outer/inner/Tasks"
  run --separate-stderr "$TD" 007 --from "$W/outer/inner"
  [ "$status" -eq 2 ] || { echo "$status $output $stderr"; return 1; }
  grep -qF "$W/outer/inner/Tasks is not a folder" <<<"$stderr" || { echo "$stderr"; return 1; }
}

@test "a status folder that is a link is searched for steps too" {
  mkdir -p "$W/ext/050-gamma/03-ui.step"
  ln -s ../../ext "$W/down/proj-tasks/DONE"
  run --separate-stderr "$TD" 03 --from "$W/down/proj"
  [ "$status" -eq 0 ] && [ "$output" = "$W/down/proj/Tasks/DONE/050-gamma/03-ui.step" ] || { echo "$status $output $stderr"; return 1; }
}
