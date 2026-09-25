#!/usr/bin/env bats
# Every range Review reads and every catch-up offer comes from this script. A repository it
# misses is a delta nobody reviews; a commit it miscounts is a task reopened for nothing.

setup() {
  ROOT="$(cd -- "$(dirname -- "$BATS_TEST_FILENAME")/../../.." && pwd)"
  TR="$ROOT/scripts/task-ranges.sh"
  PROJ="$BATS_TEST_TMPDIR/proj"
  TASK="$PROJ/Tasks/ACTIVE/001-x"
  mkdir -p "$TASK" "$PROJ/Packages/Core"
  printf '## Paths\n\n- External packages: /Packages/*\n' >"$PROJ/CLAUDE-spine-toolkit.md"
  printf 'Packages/\nTasks/\n' >"$PROJ/.gitignore"
  repo "$PROJ" .gitignore
  repo "$PROJ/Packages/Core" core.txt
  repo "$PROJ/Tasks" tasks.txt
}

repo() { git -C "$1" init -q -b main; commit "$1" "$2"; }

commit() { # $1 repository, $2 file inside it: one commit that touches only that file
  echo "$2 $RANDOM" >>"$1/$2"
  git -C "$1" add -- "$2"
  git -C "$1" -c user.name=t -c user.email=t@t commit -qm "$2"
}

state() { # $1 repo key; stdin: ranges JSON → "<state> <commits>"
  python3 -c 'import json,sys; r=json.load(sys.stdin)["repos"][sys.argv[1]]; print(r["state"], r["commits"])' "$1"
}

@test "record writes one base line per repository and never rewrites it" {
  run "$TR" record "$TASK"
  [ "$status" -eq 0 ] || { echo "$output"; return 1; }
  grep -qE '^\[BASE_COMMIT\] = \.: [0-9a-f]{40}$' "$TASK/Base.md" || { cat "$TASK/Base.md"; return 1; }
  grep -qE '^\[BASE_COMMIT\] = Packages/Core: [0-9a-f]{40}$' "$TASK/Base.md" || { cat "$TASK/Base.md"; return 1; }
  [ "$(grep -c '^\[BASE_COMMIT\]' "$TASK/Base.md")" -eq 2 ] || { cat "$TASK/Base.md"; return 1; }
  before="$(cat "$TASK/Base.md")"
  commit "$PROJ" a.txt
  "$TR" record "$TASK"
  [ "$(cat "$TASK/Base.md")" = "$before" ] || { echo "record overwrote Base.md"; return 1; }
}

@test "tips prints each repository's HEAD under the kind asked" {
  run "$TR" tips "$TASK" --kind done
  [ "$status" -eq 0 ] || { echo "$output"; return 1; }
  grep -qxF "[DONE_COMMIT] = .: $(git -C "$PROJ" rev-parse HEAD)" <<<"$output" || { echo "$output"; return 1; }
  grep -qxF "[DONE_COMMIT] = Packages/Core: $(git -C "$PROJ/Packages/Core" rev-parse HEAD)" <<<"$output" || { echo "$output"; return 1; }
  run "$TR" tips "$TASK" --kind reviewed
  grep -q '^\[REVIEWED_COMMIT\] = \.: ' <<<"$output" || { echo "$output"; return 1; }
}

@test "ranges since base counts the task's commits in every repository" {
  "$TR" record "$TASK"
  commit "$PROJ" a.txt
  commit "$PROJ" b.txt
  commit "$PROJ/Packages/Core" c.txt
  run "$TR" ranges "$TASK" --since base
  [ "$status" -eq 0 ] || { echo "$output"; return 1; }
  [ "$(state . <<<"$output")" = "ok 2" ] || { echo "$output"; return 1; }
  [ "$(state Packages/Core <<<"$output")" = "ok 1" ] || { echo "$output"; return 1; }
  grep -qF '"since": "base"' <<<"$output" || { echo "$output"; return 1; }
}

@test "a commit only in a checkout shows up after Done" {
  "$TR" tips "$TASK" --kind done >"$TASK/Done.md"
  commit "$PROJ/Packages/Core" c.txt
  run "$TR" ranges "$TASK" --since done
  [ "$status" -eq 0 ] || { echo "$output"; return 1; }
  [ "$(state . <<<"$output")" = "ok 0" ] || { echo "$output"; return 1; }
  [ "$(state Packages/Core <<<"$output")" = "ok 1" ] || { echo "$output"; return 1; }
}

@test "a commit that touches only the tasks folder does not count" {
  # The tasks folder tracked by the project repository instead of its own.
  rm -rf "$PROJ/Tasks/.git"
  printf 'Packages/\n' >"$PROJ/.gitignore"
  commit "$PROJ" .gitignore
  "$TR" tips "$TASK" --kind done >"$TASK/Done.md"
  commit "$PROJ" Tasks/ACTIVE/001-x/Done.md
  run "$TR" ranges "$TASK" --since done
  [ "$(state . <<<"$output")" = "ok 0" ] || { echo "$output"; return 1; }
  commit "$PROJ" a.txt
  run "$TR" ranges "$TASK" --since done
  [ "$(state . <<<"$output")" = "ok 1" ] || { echo "$output"; return 1; }
}

@test "the tasks repository is never a repository of the task" {
  printf '## Paths\n\n- External packages: /Packages/*\n- Roots: %s\n' "$PROJ/Tasks" >"$PROJ/CLAUDE-spine-toolkit.md"
  run "$TR" tips "$TASK" --kind done
  [ "$status" -eq 0 ] || { echo "$output"; return 1; }
  if grep -q 'Tasks' <<<"$output"; then echo "$output"; return 1; fi
}

@test "a rewritten base reads as rewritten" {
  "$TR" record "$TASK"
  git -C "$PROJ" -c user.name=t -c user.email=t@t commit -q --amend -m amended
  run "$TR" ranges "$TASK" --since base
  [ "$status" -eq 0 ] || { echo "$output"; return 1; }
  [ "$(state . <<<"$output")" = "rewritten None" ] || { echo "$output"; return 1; }
  [ "$(state Packages/Core <<<"$output")" = "ok 0" ] || { echo "$output"; return 1; }
}

@test "no record reads unknown; base falls back to the main branch" {
  run "$TR" ranges "$TASK" --since reviewed
  [ "$(state . <<<"$output")" = "unknown None" ] || { echo "$output"; return 1; }
  git -C "$PROJ" checkout -qb feat
  commit "$PROJ" a.txt
  run "$TR" ranges "$TASK" --since base
  [ "$status" -eq 0 ] || { echo "$output"; return 1; }
  [ "$(state . <<<"$output")" = "ok 1" ] || { echo "$output"; return 1; }
  [ "$(state Packages/Core <<<"$output")" = "unknown None" ] || { echo "$output"; return 1; }
}

@test "work committed on main itself has no known base" {
  commit "$PROJ" a.txt
  run "$TR" ranges "$TASK" --since base
  [ "$status" -eq 0 ] || { echo "$output"; return 1; }
  [ "$(state . <<<"$output")" = "unknown None" ] || { echo "$output"; return 1; }
}

origin_at() { # $1 commit: origin/main stands there and is the remote's HEAD, as after a clone
  git -C "$PROJ" update-ref refs/remotes/origin/main "$1"
  git -C "$PROJ" symbolic-ref refs/remotes/origin/HEAD refs/remotes/origin/main
}

@test "unpushed commits of the local main branch stay out of the fallback base" {
  origin_at "$(git -C "$PROJ" rev-parse HEAD)"
  commit "$PROJ" unpushed.txt
  git -C "$PROJ" checkout -qb feat
  commit "$PROJ" a.txt
  run "$TR" ranges "$TASK" --since base
  [ "$status" -eq 0 ] || { echo "$output"; return 1; }
  [ "$(state . <<<"$output")" = "ok 1" ] || { echo "$output"; return 1; }
}

@test "a stale local main branch does not widen the fallback base" {
  git -C "$PROJ" checkout -qb feat
  commit "$PROJ" pulled.txt
  origin_at "$(git -C "$PROJ" rev-parse HEAD)"
  commit "$PROJ" a.txt
  run "$TR" ranges "$TASK" --since base
  [ "$status" -eq 0 ] || { echo "$output"; return 1; }
  [ "$(state . <<<"$output")" = "ok 1" ] || { echo "$output"; return 1; }
}

@test "work on a main branch ahead of origin has no known base" {
  origin_at "$(git -C "$PROJ" rev-parse HEAD)"
  commit "$PROJ" a.txt
  run "$TR" ranges "$TASK" --since base
  [ "$status" -eq 0 ] || { echo "$output"; return 1; }
  [ "$(state . <<<"$output")" = "unknown None" ] || { echo "$output"; return 1; }
}

@test "tips --kind done also records the last fix round Plan.md holds" {
  run "$TR" tips "$TASK" --kind done
  grep -qx '\[REVIEW_FIXES\] = 0' <<<"$output" || { echo "$output"; return 1; }
  printf '| R1 | Review fixes 1 | ✅ |\n| R3 | Review fixes 3 | ✅ |\n| R2 | Review fixes 2 | ✅ |\n' >"$TASK/Plan.md"
  run "$TR" tips "$TASK" --kind done
  grep -qx '\[REVIEW_FIXES\] = 3' <<<"$output" || { echo "$output"; return 1; }
  run "$TR" tips "$TASK" --kind reviewed
  ! grep -q REVIEW_FIXES <<<"$output" || { echo "$output"; return 1; }
  "$TR" tips "$TASK" --kind done >"$TASK/Done.md"
  run "$TR" ranges "$TASK" --since done
  [ "$(state . <<<"$output")" = "ok 0" ] || { echo "$output"; return 1; }
}

@test "the first record line of a repository wins" {
  stale="$(git -C "$PROJ" rev-parse HEAD)"
  commit "$PROJ" a.txt
  { "$TR" tips "$TASK" --kind done; printf '\n[DONE_COMMIT] = .: %s\n' "$stale"; } >"$TASK/Done.md"
  run "$TR" ranges "$TASK" --since done
  [ "$status" -eq 0 ] || { echo "$output"; return 1; }
  [ "$(state . <<<"$output")" = "ok 0" ] || { echo "$output"; return 1; }
}

@test "an old single-sha line is the project's" {
  printf '[REVIEW_STATUS] = APPROVED\n[REVIEWED_COMMIT] = %s\n' "$(git -C "$PROJ" rev-parse HEAD)" >"$TASK/Review.md"
  commit "$PROJ" a.txt
  run "$TR" ranges "$TASK" --since reviewed
  [ "$status" -eq 0 ] || { echo "$output"; return 1; }
  [ "$(state . <<<"$output")" = "ok 1" ] || { echo "$output"; return 1; }
  [ "$(state Packages/Core <<<"$output")" = "unknown None" ] || { echo "$output"; return 1; }
}

@test "unreachable names the commits a reset and a squash dropped, and only those" {
  "$TR" record "$TASK"
  base="$(git -C "$PROJ/Packages/Core" rev-parse HEAD)"
  commit "$PROJ/Packages/Core" c.txt; c1="$(git -C "$PROJ/Packages/Core" rev-parse --short HEAD)"
  commit "$PROJ" a.txt; a1="$(git -C "$PROJ" rev-parse --short HEAD)"
  commit "$PROJ" b.txt; a2="$(git -C "$PROJ" rev-parse --short HEAD)"
  commit "$PROJ" d.txt; a3="$(git -C "$PROJ" rev-parse --short HEAD)"
  git -C "$PROJ/Packages/Core" reset -q --hard "$base"
  git -C "$PROJ" reset -q --soft HEAD~2
  git -C "$PROJ" -c user.name=t -c user.email=t@t commit -qm squashed
  sq="$(git -C "$PROJ" rev-parse --short HEAD)"
  run "$TR" unreachable "$TASK" "$c1" "$a1" "$a2" "$a3" "$sq"
  [ "$status" -eq 0 ] || { echo "$output"; return 1; }
  [ "$output" = "$(printf '%s\n%s\n%s' "$c1" "$a2" "$a3")" ] || { echo "$output"; return 1; }
}

@test "unreachable counts the base itself as outside the task" {
  "$TR" record "$TASK"
  base="$(git -C "$PROJ" rev-parse --short HEAD)"
  run "$TR" unreachable "$TASK" "$base"
  [ "$status" -eq 0 ] || { echo "$output"; return 1; }
  [ "$output" = "$base" ] || { echo "$output"; return 1; }
}

@test "unreachable falls back to HEAD when the base was rewritten" {
  "$TR" record "$TASK"
  old="$(git -C "$PROJ" rev-parse --short HEAD)"
  git -C "$PROJ" -c user.name=t -c user.email=t@t commit -q --amend -m amended
  commit "$PROJ" a.txt; a1="$(git -C "$PROJ" rev-parse --short HEAD)"
  run "$TR" unreachable "$TASK" "$old" "$a1"
  [ "$status" -eq 0 ] || { echo "$output"; return 1; }
  [ "$output" = "$old" ] || { echo "$output"; return 1; }
}

@test "unreachable accepts a live commit of the task repository itself" {
  "$TR" record "$TASK"
  commit "$PROJ/Tasks" plan.txt; t1="$(git -C "$PROJ/Tasks" rev-parse --short HEAD)"
  run "$TR" unreachable "$TASK" "$t1"
  [ "$status" -eq 0 ] || { echo "$output"; return 1; }
  [ -z "$output" ] || { echo "a live task-repository commit read as gone: $output"; return 1; }
}

@test "unreachable accepts a commit a local branch holds while HEAD is elsewhere" {
  "$TR" record "$TASK"
  git -C "$PROJ" checkout -qb feat
  commit "$PROJ" a.txt; a1="$(git -C "$PROJ" rev-parse --short HEAD)"
  git -C "$PROJ" checkout -q main
  run "$TR" unreachable "$TASK" "$a1"
  [ "$status" -eq 0 ] || { echo "$output"; return 1; }
  [ -z "$output" ] || { echo "a commit on another branch read as gone: $output"; return 1; }
}

@test "unreachable needs at least one sha" {
  run "$TR" unreachable "$TASK"
  [ "$status" -eq 2 ] || { echo "no sha: $status $output"; return 1; }
  grep -qF 'usage: task-ranges.sh unreachable' <<<"$output" || { echo "$output"; return 1; }
}

@test "a record it cannot trust stops with exit 2" {
  printf '[DONE_COMMIT] = .: not-a-sha\n' >"$TASK/Done.md"
  run "$TR" ranges "$TASK" --since done
  [ "$status" -eq 2 ] || { echo "malformed line: $status $output"; return 1; }
  printf '[DONE_COMMIT] = Gone/Pkg: %s\n' "$(git -C "$PROJ" rev-parse HEAD)" >"$TASK/Done.md"
  run "$TR" ranges "$TASK" --since done
  [ "$status" -eq 2 ] || { echo "missing repo: $status $output"; return 1; }
  grep -qF 'Gone/Pkg' <<<"$output" || { echo "$output"; return 1; }
  run "$TR" ranges "$TASK" --since later
  [ "$status" -eq 2 ] || { echo "bad --since: $status"; return 1; }
  run "$TR" nope "$TASK"
  [ "$status" -eq 2 ] || { echo "bad subcommand: $status"; return 1; }
}
