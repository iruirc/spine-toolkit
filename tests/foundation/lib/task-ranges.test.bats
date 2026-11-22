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

@test "commits lists a range from its first commit on, oldest first" {
  commit "$PROJ" a.txt; a1="$(git -C "$PROJ" rev-parse HEAD)"
  commit "$PROJ" b.txt; a2="$(git -C "$PROJ" rev-parse HEAD)"
  commit "$PROJ" c.txt; a3="$(git -C "$PROJ" rev-parse HEAD)"
  run "$TR" commits "$TASK" "${a1:0:7}..${a3:0:7}"
  [ "$status" -eq 0 ] || { echo "$output"; return 1; }
  [ "$output" = "$(printf '%s\n%s\n%s' "$a1" "$a2" "$a3")" ] || { echo "$output"; return 1; }
}

@test "commits leaves out what a merge brought in" {
  commit "$PROJ" a.txt; a1="$(git -C "$PROJ" rev-parse HEAD)"
  git -C "$PROJ" checkout -qb upstream HEAD~1
  commit "$PROJ" u.txt
  git -C "$PROJ" checkout -q main
  git -C "$PROJ" -c user.name=t -c user.email=t@t merge -q --no-ff -m merge upstream; m="$(git -C "$PROJ" rev-parse HEAD)"
  commit "$PROJ" c.txt; a3="$(git -C "$PROJ" rev-parse HEAD)"
  run "$TR" commits "$TASK" "$a1..$a3"
  [ "$status" -eq 0 ] || { echo "$output"; return 1; }
  [ "$output" = "$(printf '%s\n%s\n%s' "$a1" "$m" "$a3")" ] || { echo "$output"; return 1; }
}

@test "commits finds a range in the task repository itself" {
  commit "$PROJ/Tasks" ACTIVE/001-x/Plan.md; t1="$(git -C "$PROJ/Tasks" rev-parse HEAD)"
  commit "$PROJ/Tasks" ACTIVE/001-x/Plan.md; t2="$(git -C "$PROJ/Tasks" rev-parse HEAD)"
  run "$TR" commits "$TASK" "$t1..$t2"
  [ "$status" -eq 0 ] || { echo "$output"; return 1; }
  [ "$output" = "$(printf '%s\n%s' "$t1" "$t2")" ] || { echo "$output"; return 1; }
}

@test "commits refuses a range no repository holds, and a malformed one" {
  a="$(git -C "$PROJ" rev-parse --short HEAD)"; c="$(git -C "$PROJ/Packages/Core" rev-parse --short HEAD)"
  run "$TR" commits "$TASK" "$a..$c"
  [ "$status" -eq 2 ] || { echo "split range: $status $output"; return 1; }
  grep -qF "no repository of the task holds $a..$c" <<<"$output" || { echo "$output"; return 1; }
  run "$TR" commits "$TASK" "$a"
  [ "$status" -eq 2 ] || { echo "no range: $status $output"; return 1; }
  grep -qF 'usage: task-ranges.sh commits' <<<"$output" || { echo "$output"; return 1; }
}

@test "last names each repository's newest own commit, outside the tasks folder" {
  "$TR" record "$TASK"
  run "$TR" last "$TASK"
  [ "$status" -eq 0 ] && [ -z "$output" ] || { echo "nothing yet: $status $output"; return 1; }
  commit "$PROJ" a.txt; a="$(git -C "$PROJ" rev-parse HEAD)"
  commit "$PROJ/Tasks" ACTIVE/001-x/Plan.md
  run "$TR" last "$TASK"
  [ "$output" = ". $a" ] || { echo "one repository: $output"; return 1; }
  commit "$PROJ/Packages/Core" core.txt; c="$(git -C "$PROJ/Packages/Core" rev-parse HEAD)"
  run "$TR" last "$TASK"
  [ "$output" = "$(printf '. %s\nPackages/Core %s' "$a" "$c")" ] || { echo "two repositories: $output"; return 1; }
  git -C "$PROJ/Packages/Core" reset -q --hard HEAD~1
  commit "$PROJ/Packages/Core" other.txt
  sed -i.bak "s|Packages/Core: .*|Packages/Core: $c|" "$TASK/Base.md"
  run "$TR" last "$TASK"
  grep -qxF 'Packages/Core unknown' <<<"$output" || { echo "rewritten: $output"; return 1; }
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

@test "commits leaves out what other tasks committed in a shared tasks repository" {
  mkdir -p "$TASK" "$PROJ/Tasks/ACTIVE/002-y"
  echo a >"$TASK/Plan.md"; git -C "$PROJ/Tasks" add -A; git -C "$PROJ/Tasks" -c user.name=t -c user.email=t@t commit -qm mine1; t1="$(git -C "$PROJ/Tasks" rev-parse HEAD)"
  echo b >"$PROJ/Tasks/ACTIVE/002-y/Plan.md"; git -C "$PROJ/Tasks" add -A; git -C "$PROJ/Tasks" -c user.name=t -c user.email=t@t commit -qm theirs
  echo c >>"$TASK/Plan.md"; git -C "$PROJ/Tasks" add -A; git -C "$PROJ/Tasks" -c user.name=t -c user.email=t@t commit -qm mine2; t2="$(git -C "$PROJ/Tasks" rev-parse HEAD)"
  run "$TR" commits "$TASK" "$t1..$t2"
  [ "$status" -eq 0 ] || { echo "$output"; return 1; }
  [ "$output" = "$(printf '%s\n%s' "$t1" "$t2")" ] || { echo "$output"; return 1; }
}

# Markers are read at any position, first match per repository: Tasks/DONE holds files with them on
# top, new files carry them in a closing block after the prose and the Run line.
layout() { # $1 top|closing|stale, $2 done|reviewed
  local file=Done.md tips; [ "$2" = reviewed ] && file=Review.md
  tips="$("$TR" tips "$TASK" --kind "$2")"
  {
    [ "$2" = reviewed ] && [ "$1" != top ] && printf '[REVIEW_STATUS] = APPROVED\n\n'
    case "$1" in
      top) printf '%s\n**Run:** drive_app=off\n\nThe cart now keeps its promo code.\n' "$tips" ;;
      closing) printf 'The cart now keeps its promo code.\n\n%s\n\n**Run:** drive_app=off\n**Device:** Phone B\n' "$tips" ;;
      stale)
        printf 'The cart now keeps its promo code.\n\n%s\n\n**Run:** drive_app=off\n\n## History\n\n' "$tips"
        sed 's/: [0-9a-f]*$/: 0000000000000000000000000000000000000000/' <<<"$tips" ;;
    esac
  } >"$TASK/$file"
}

@test "since done and since reviewed give one answer for markers on top, in a closing block, and with a stale copy below" {
  for since in done reviewed; do
    for l in top closing stale; do
      layout "$l" "$since"
      commit "$PROJ" "$since-$l.txt"
      run "$TR" ranges "$TASK" --since "$since"
      [ "$status" -eq 0 ] || { echo "$since/$l: $status $output"; return 1; }
      [ "$(state . <<<"$output")" = "ok 1" ] || { echo "$since/$l: $output"; return 1; }
      [ "$(state Packages/Core <<<"$output")" = "ok 0" ] || { echo "$since/$l: $output"; return 1; }
    done
  done
}

@test "a malformed marker in the closing block stops with exit 2, as one on top does" {
  for since in done reviewed; do
    layout closing "$since"
    kind=DONE; file=Done.md; [ "$since" = reviewed ] && { kind=REVIEWED; file=Review.md; }
    printf '[%s_COMMIT] = .: not-a-sha\n' "$kind" >>"$TASK/$file"
    run "$TR" ranges "$TASK" --since "$since"
    [ "$status" -eq 2 ] || { echo "$since: $status $output"; return 1; }
  done
}

track_tasks() { # the tasks folder tracked by the project repository instead of its own
  rm -rf "$PROJ/Tasks/.git"
  printf 'Packages/\n' >"$PROJ/.gitignore"
  commit "$PROJ" .gitignore
}

@test "tips and ranges know the validated kind" {
  run "$TR" tips "$TASK" --kind validated
  [ "$status" -eq 0 ] || { echo "$output"; return 1; }
  grep -qxF "[VALIDATED_COMMIT] = .: $(git -C "$PROJ" rev-parse HEAD)" <<<"$output" || { echo "$output"; return 1; }
  { printf '[VALIDATION_STATUS] = PASSED\n\n'; printf '%s\n' "$output"; } >"$TASK/Validation.md"
  commit "$PROJ/Packages/Core" c.txt
  run "$TR" ranges "$TASK" --since validated
  [ "$status" -eq 0 ] || { echo "$output"; return 1; }
  [ "$(state . <<<"$output")" = "ok 0" ] || { echo "$output"; return 1; }
  [ "$(state Packages/Core <<<"$output")" = "ok 1" ] || { echo "$output"; return 1; }
  grep -qF '"since": "validated"' <<<"$output" || { echo "$output"; return 1; }
}

@test "a Validation.md without records is unknown, never a fallback base" {
  git -C "$PROJ" checkout -qb feat
  commit "$PROJ" a.txt
  printf '[VALIDATION_STATUS] = FAILED\n' >"$TASK/Validation.md"
  run "$TR" ranges "$TASK" --since validated
  [ "$status" -eq 0 ] || { echo "$output"; return 1; }
  [ "$(state . <<<"$output")" = "unknown None" ] || { echo "$output"; return 1; }
  [ "$(state Packages/Core <<<"$output")" = "unknown None" ] || { echo "$output"; return 1; }
}

@test "dirty names a repository with uncommitted work outside the tasks folder" {
  track_tasks
  git -C "$PROJ" add CLAUDE-spine-toolkit.md
  git -C "$PROJ" -c user.name=t -c user.email=t@t commit -qm config
  run "$TR" dirty "$TASK"
  [ "$status" -eq 0 ] || { echo "$output"; return 1; }
  [ -z "$output" ] || { echo "$output"; return 1; }
  echo "more" >>"$PROJ/Packages/Core/core.txt"
  run "$TR" dirty "$TASK"
  [ "$status" -eq 0 ] || { echo "$output"; return 1; }
  [ "$output" = "Packages/Core" ] || { echo "$output"; return 1; }
  git -C "$PROJ/Packages/Core" checkout -q -- core.txt
  echo "note" >"$TASK/Notes.md"
  run "$TR" dirty "$TASK"
  [ "$status" -eq 0 ] || { echo "$output"; return 1; }
  [ -z "$output" ] || { echo "$output"; return 1; }
  echo "new" >"$PROJ/new.txt"
  run "$TR" dirty "$TASK"
  [ "$output" = "." ] || { echo "$output"; return 1; }
}

@test "record keeps a fingerprint of each repository's uncommitted state, a clean one has none" {
  echo "local" >>"$PROJ/Packages/Core/core.txt"
  run "$TR" record "$TASK"
  [ "$status" -eq 0 ] || { echo "$output"; return 1; }
  grep -qE '^\[BASE_DIRTY\] = Packages/Core: [0-9a-f]{40}$' "$TASK/Base.md" || { cat "$TASK/Base.md"; return 1; }
  # the project root holds the untracked config; a clean repository gets no line
  git -C "$PROJ/Packages/Core" stash -q
  rm "$TASK/Base.md"
  "$TR" record "$TASK"
  ! grep -q '^\[BASE_DIRTY\] = Packages/Core' "$TASK/Base.md" || { cat "$TASK/Base.md"; return 1; }
}

@test "dirty leaves out the uncommitted state the base recorded, and names what changed after" {
  # an environment switch made before the task: a tracked file edited, an untracked one added
  echo "local" >>"$PROJ/Packages/Core/core.txt"
  echo "env" >"$PROJ/Packages/Core/env.txt"
  "$TR" record "$TASK"
  run "$TR" dirty "$TASK"
  [ "$status" -eq 0 ] || { echo "$output"; return 1; }
  [ -z "$output" ] || { echo "$output"; return 1; }
  # staging the same content is no new work
  git -C "$PROJ/Packages/Core" add core.txt
  run "$TR" dirty "$TASK"
  [ -z "$output" ] || { echo "$output"; return 1; }
  # the same file with other content is
  echo "again" >>"$PROJ/Packages/Core/core.txt"
  run "$TR" dirty "$TASK"
  [ "$output" = "Packages/Core" ] || { echo "$output"; return 1; }
  git -C "$PROJ/Packages/Core" checkout -q -- core.txt  # back to the staged, recorded content
  # a new file is
  echo "task" >"$PROJ/Packages/Core/task.txt"
  run "$TR" dirty "$TASK"
  [ "$output" = "Packages/Core" ] || { echo "$output"; return 1; }
  # a clean checkout has nothing to validate, whatever the base recorded
  git -C "$PROJ/Packages/Core" checkout -q HEAD -- core.txt
  rm "$PROJ/Packages/Core/task.txt" "$PROJ/Packages/Core/env.txt"
  run "$TR" dirty "$TASK"
  [ -z "$output" ] || { echo "$output"; return 1; }
}

@test "dirty counts every uncommitted state when Base.md has no fingerprint for it" {
  "$TR" record "$TASK"
  echo "local" >>"$PROJ/Packages/Core/core.txt"
  run "$TR" dirty "$TASK"
  [ "$output" = "Packages/Core" ] || { echo "$output"; return 1; }
  # a Base.md written before the fingerprint existed: the project's untracked config counts again
  grep -v '^\[BASE_DIRTY\]' "$TASK/Base.md" >"$TASK/Base.old" && mv "$TASK/Base.old" "$TASK/Base.md"
  run "$TR" dirty "$TASK"
  grep -qx "Packages/Core" <<<"$output" || { echo "$output"; return 1; }
  grep -qx "." <<<"$output" || { echo "$output"; return 1; }
}

@test "count measures commits after a sha, the tasks folder aside" {
  track_tasks
  sha="$(git -C "$PROJ/Packages/Core" rev-parse HEAD)"
  commit "$PROJ/Packages/Core" c.txt
  commit "$PROJ/Packages/Core" d.txt
  run "$TR" count "$TASK" Packages/Core "$sha"
  [ "$status" -eq 0 ] || { echo "$output"; return 1; }
  [ "$output" = "2" ] || { echo "$output"; return 1; }
  run "$TR" count "$TASK" Packages/Core "${sha:0:7}"
  [ "$output" = "2" ] || { echo "$output"; return 1; }
  head="$(git -C "$PROJ" rev-parse HEAD)"
  commit "$PROJ" Tasks/ACTIVE/001-x/Validation.md
  run "$TR" count "$TASK" . "$head"
  [ "$status" -eq 0 ] || { echo "$output"; return 1; }
  [ "$output" = "0" ] || { echo "$output"; return 1; }
  run "$TR" count "$TASK" Packages/Core deadbee
  [ "$status" -eq 0 ] || { echo "$output"; return 1; }
  [ "$output" = "rewritten" ] || { echo "$output"; return 1; }
  run "$TR" count "$TASK" Nope "$sha"
  [ "$status" -eq 2 ] || { echo "$status $output"; return 1; }
}

@test "dirty stops with exit 2 on a repository git cannot read, never calls it clean" {
  printf 'not an index' >"$PROJ/Packages/Core/.git/index"
  run "$TR" dirty "$TASK"
  [ "$status" -eq 2 ] || { echo "$status $output"; return 1; }
  grep -q 'Packages/Core' <<<"$output" || { echo "$output"; return 1; }
}

@test "the usage line names every command" {
  run "$TR" bogus
  [ "$status" -eq 2 ]
  for c in record tips ranges since dirty count unreachable commits last names owners; do
    grep -qF "$c" <<<"$output" || { echo "usage lacks $c: $output"; return 1; }
  done
}

@test "names prints each repository of the task by its checkout folder" {
  run "$TR" names "$TASK"
  [ "$status" -eq 0 ] || { echo "$output"; return 1; }
  [ "$output" = "$(printf 'proj .\nCore Packages/Core\nTasks Tasks')" ] || { echo "$output"; return 1; }
}

@test "names gives checkouts that share a folder name their paths" {
  mkdir -p "$PROJ/Vendor/Core"
  printf '## Paths\n\n- External packages: /Packages/*\n- External packages: /Vendor/*\n' >"$PROJ/CLAUDE-spine-toolkit.md"
  repo "$PROJ/Vendor/Core" v.txt
  run "$TR" names "$TASK"
  [ "$status" -eq 0 ] || { echo "$output"; return 1; }
  grep -qxF 'Packages/Core Packages/Core' <<<"$output" && grep -qxF 'Vendor/Core Vendor/Core' <<<"$output" \
    && grep -qxF 'proj .' <<<"$output" || { echo "$output"; return 1; }
}

@test "owners names the repository that holds each sha, and none for a stranger" {
  "$TR" record "$TASK"
  commit "$PROJ/Packages/Core" c.txt; C="$(git -C "$PROJ/Packages/Core" rev-parse --short HEAD)"
  commit "$PROJ/Tasks" t.txt; T="$(git -C "$PROJ/Tasks" rev-parse --short HEAD)"
  run "$TR" owners "$TASK" "$C" deadbee1 "$T"
  [ "$status" -eq 0 ] || { echo "$output"; return 1; }
  [ "$output" = "$(printf '%s Core\ndeadbee1\n%s Tasks' "$C" "$T")" ] || { echo "$output"; return 1; }
}

@test "owners needs at least one sha" {
  run "$TR" owners "$TASK"
  [ "$status" -eq 2 ]
}

field() { # $1 repo key, $2 field; stdin: ranges JSON → the value, or "absent"
  python3 -c 'import json,sys; r=json.load(sys.stdin)["repos"][sys.argv[1]]; print(r.get(sys.argv[2], "absent"))' "$1" "$2"
}

@test "since picks the review base by the action and Review.md" {
  for a in run continue redo restart restart-full; do
    [ "$("$TR" since "$TASK" --action "$a")" = base ] || { echo "$a without Review.md"; return 1; }
  done
  [ "$("$TR" since "$TASK" --action catch-up)" = done ] || { echo "catch-up"; return 1; }
  [ "$("$TR" since "$TASK" --action fix-review)" = reviewed ] || { echo "fix-review"; return 1; }
  "$TR" tips "$TASK" --kind reviewed >"$TASK/Review.md"
  for a in run continue redo fix-review; do
    [ "$("$TR" since "$TASK" --action "$a")" = reviewed ] || { echo "$a with Review.md"; return 1; }
  done
  for a in restart restart-full; do
    [ "$("$TR" since "$TASK" --action "$a")" = base ] || { echo "$a with Review.md"; return 1; }
  done
  [ "$("$TR" since "$TASK" --action catch-up)" = done ] || { echo "catch-up with Review.md"; return 1; }
}

@test "since refuses a missing or unknown action" {
  run "$TR" since "$TASK"
  [ "$status" -eq 2 ] || { echo "$output"; return 1; }
  run "$TR" since "$TASK" --action review
  [ "$status" -eq 2 ] || { echo "$output"; return 1; }
}

@test "fallback measures a rewritten repository from the base and leaves the others on reviewed" {
  "$TR" record "$TASK"
  commit "$PROJ" a.txt
  commit "$PROJ/Packages/Core" b.txt
  "$TR" tips "$TASK" --kind reviewed >"$TASK/Review.md"
  git -C "$PROJ/Packages/Core" reset -q --hard HEAD~1
  commit "$PROJ/Packages/Core" c.txt
  run "$TR" ranges "$TASK" --since reviewed --fallback base
  [ "$status" -eq 0 ] || { echo "$output"; return 1; }
  [ "$(state . <<<"$output")" = "ok 0" ] || { echo "$output"; return 1; }
  [ "$(field . fallback <<<"$output")" = absent ] || { echo "$output"; return 1; }
  [ "$(field . since <<<"$output")" = absent ] || { echo "$output"; return 1; }
  [ "$(state Packages/Core <<<"$output")" = "ok 1" ] || { echo "$output"; return 1; }
  [ "$(field Packages/Core since <<<"$output")" = base ] || { echo "$output"; return 1; }
  [ "$(field Packages/Core fallback <<<"$output")" = rewritten ] || { echo "$output"; return 1; }
  [ "$(python3 -c 'import json,sys; print(json.load(sys.stdin)["since"])' <<<"$output")" = reviewed ] || { echo "$output"; return 1; }
}

@test "fallback measures a repository the review never recorded from the base" {
  "$TR" record "$TASK"
  commit "$PROJ/Packages/Core" b.txt
  "$TR" tips "$TASK" --kind reviewed | grep -F '= .:' >"$TASK/Review.md"
  run "$TR" ranges "$TASK" --since reviewed --fallback base
  [ "$status" -eq 0 ] || { echo "$output"; return 1; }
  [ "$(state Packages/Core <<<"$output")" = "ok 1" ] || { echo "$output"; return 1; }
  [ "$(field Packages/Core fallback <<<"$output")" = unknown ] || { echo "$output"; return 1; }
}

@test "fallback with no base either keeps range null and says so" {
  commit "$PROJ" a.txt
  : >"$TASK/Review.md"
  run "$TR" ranges "$TASK" --since reviewed --fallback base
  [ "$status" -eq 0 ] || { echo "$output"; return 1; }
  [ "$(state . <<<"$output")" = "unknown None" ] || { echo "$output"; return 1; }
  [ "$(field . range <<<"$output")" = None ] || { echo "$output"; return 1; }
  [ "$(field . fallback <<<"$output")" = unknown ] || { echo "$output"; return 1; }
}

@test "fallback refuses base and validated" {
  run "$TR" ranges "$TASK" --since base --fallback base
  [ "$status" -eq 2 ] || { echo "$output"; return 1; }
  run "$TR" ranges "$TASK" --since validated --fallback base
  [ "$status" -eq 2 ] || { echo "$output"; return 1; }
}

@test "without fallback ranges prints what it printed before" {
  "$TR" record "$TASK"
  git -C "$PROJ" -c user.name=t -c user.email=t@t commit -q --amend -m amended
  run "$TR" ranges "$TASK" --since base
  [ "$status" -eq 0 ] || { echo "$output"; return 1; }
  ! grep -qF fallback <<<"$output" || { echo "$output"; return 1; }
  run "$TR" ranges "$TASK" --since reviewed
  ! grep -qF fallback <<<"$output" || { echo "$output"; return 1; }
}

@test "a range counted before the fix commit holds it once the commit lands" {
  "$TR" record "$TASK"
  commit "$PROJ/Packages/Core" b.txt
  "$TR" tips "$TASK" --kind reviewed >"$TASK/Review.md"
  before="$("$TR" ranges "$TASK" --since reviewed --fallback base)"
  [ "$(state . <<<"$before")" = "ok 0" ] || { echo "$before"; return 1; }
  [ "$(state Packages/Core <<<"$before")" = "ok 0" ] || { echo "$before"; return 1; }
  commit "$PROJ/Packages/Core" fix.txt
  after="$("$TR" ranges "$TASK" --since reviewed --fallback base)"
  [ "$(state Packages/Core <<<"$after")" = "ok 1" ] || { echo "$after"; return 1; }
  [ "$(field Packages/Core range <<<"$after")" = "$(field Packages/Core range <<<"$before")" ] || { echo "$before / $after"; return 1; }
  [ "$("$TR" since "$TASK" --action fix-review)" = reviewed ] || return 1
}
