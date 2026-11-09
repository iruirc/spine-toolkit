#!/usr/bin/env bats
# A task reached through a symlinked Tasks folder is the same task as the one reached directly, and
# a stage searches the same folders either way. The filesystem follows a link before it reads the
# `..` after it; a lexical normalization deletes `Tasks/..` instead, and lands in a folder that does
# not exist — with exit 0 and a plausible JSON, which is why only an existence check catches it.
#
# The layout is the one a shared task repository gives:
#   tasks/        SPINE.md, its ## Paths written from here, and the tasks
#   docs/
#   dev/Tasks -> ../tasks
#   dev/app/Tasks -> ../Tasks       (a chain of two links)
#   dev/meta/Tasks -> ../Tasks
#   dev/packages/core/

setup() {
  ROOT="$(cd -- "$(dirname -- "$BATS_TEST_FILENAME")/../../.." && pwd)"
  RESOLVE="$ROOT/scripts/resolve-settings.sh"
  DR="$ROOT/scripts/docs-route.sh"
  W="$BATS_TEST_TMPDIR/work space"
  mkdir -p "$W/tasks/ACTIVE/001-proto/02-core.step" "$W/docs" "$W/dev/app" "$W/dev/meta" "$W/dev/packages/core"
  ln -s ../tasks "$W/dev/Tasks"
  ln -s ../Tasks "$W/dev/app/Tasks"
  ln -s ../Tasks "$W/dev/meta/Tasks"
  printf '[LANG] = [ru]\n[SCALE] = [lite]\n\n## Paths\n\n- External packages: ../dev/packages/*\n- Roots: ../dev/app\n- Roots: ../dev/meta\n- Roots: ../docs\n' >"$W/tasks/SPINE.md"
  printf '[TASK_TYPE] = [EPIC]\n[WALKTHROUGH] = [brief]\n' >"$W/tasks/ACTIVE/001-proto/Task.md"
  printf '[TASK_TYPE] = [FEATURE]\n' >"$W/tasks/ACTIVE/001-proto/02-core.step/Task.md"
  T=ACTIVE/001-proto
  ERR="$BATS_TEST_TMPDIR/err"
}

field() { python3 -c 'import json,sys; print(json.load(sys.stdin)[sys.argv[1]])' "$1"; }

# Every root names a folder that exists, and the set of folders they name, physically.
physical_roots() {
  python3 -c '
import json, os, sys
roots = json.load(sys.stdin)["roots"]
missing = [r for r in roots if not os.path.isdir(r)]
if missing:
    sys.exit("missing: %s" % missing)
print("\n".join(sorted(os.path.realpath(r) for r in roots)))'
}

expected_roots() {
  for d in tasks docs dev/app dev/meta dev/packages/core; do
    python3 -c 'import os,sys; print(os.path.realpath(sys.argv[1]))' "$W/$d"
  done | sort
}

@test "the direct path: settings from the task repository, every root exists" {
  out="$("$RESOLVE" json "$W/tasks/$T" 2>"$ERR")"
  [ "$(field lang <<<"$out")" = ru ] || { echo "$out"; return 1; }
  [ "$(field scale <<<"$out")" = lite ] || { echo "$out"; return 1; }
  [ "$(physical_roots <<<"$out")" = "$(expected_roots)" ] || { echo "$out"; return 1; }
}

@test "through a Tasks link, a chain of two links and the meta checkout: the same config, the same folders" {
  for via in "dev/Tasks" "dev/app/Tasks" "dev/meta/Tasks"; do
    out="$("$RESOLVE" json "$W/$via/$T" 2>"$ERR")" || { cat "$ERR"; return 1; }
    [ "$(field lang <<<"$out")" = ru ] || { echo "$via: $out"; return 1; }
    [ "$(field scale <<<"$out")" = lite ] || { echo "$via: $out"; return 1; }
    cfg="$(field project_config <<<"$out")"
    [ "$cfg" -ef "$W/tasks/SPINE.md" ] || { echo "$via: $cfg"; return 1; }
    got="$(physical_roots <<<"$out")" || { echo "$via: $got"; echo "$out"; return 1; }
    [ "$got" = "$(expected_roots)" ] || { echo "$via: $out"; return 1; }
  done
}

@test "a config in the app checkout does not override the task repository's own" {
  printf '[LANG] = [en]\n[SCALE] = [full]\n' >"$W/dev/app/SPINE.md"
  out="$("$RESOLVE" json "$W/dev/app/Tasks/$T" 2>"$ERR")"
  [ "$(field lang <<<"$out")" = ru ] || { echo "$out"; return 1; }
  [ "$(field scale <<<"$out")" = lite ] || { echo "$out"; return 1; }
  [ "$(field project_config <<<"$out")" -ef "$W/tasks/SPINE.md" ] || { echo "$out"; return 1; }
  [ "$(physical_roots <<<"$out")" = "$(expected_roots)" ] || { echo "$out"; return 1; }
}

@test "a task repository without a config takes the config of the checkout it was opened through" {
  # The lookup walks the path as given (conventions/task-settings.md → Project config). Pinned, so
  # a change to a physical walk is a decision someone makes, not a side effect.
  rm "$W/tasks/SPINE.md"
  printf '[LANG] = [en]\n' >"$W/dev/app/SPINE.md"
  printf '[LANG] = [ru]\n' >"$W/dev/meta/SPINE.md"
  out="$("$RESOLVE" json "$W/tasks/$T" 2>"$ERR")"
  [ "$(field project_config <<<"$out")" = None ] || { echo "$out"; return 1; }
  out="$("$RESOLVE" json "$W/dev/app/Tasks/$T" 2>"$ERR")"
  [ "$(field lang <<<"$out")" = en ] || { echo "$out"; return 1; }
  [ "$(field project_config <<<"$out")" -ef "$W/dev/app/SPINE.md" ] || { echo "$out"; return 1; }
  out="$("$RESOLVE" json "$W/dev/meta/Tasks/$T" 2>"$ERR")"
  [ "$(field lang <<<"$out")" = ru ] || { echo "$out"; return 1; }
  [ "$(field project_config <<<"$out")" -ef "$W/dev/meta/SPINE.md" ] || { echo "$out"; return 1; }
}

@test "a folder reached through the link is not listed twice" {
  printf '[LANG] = [ru]\n\n## Paths\n\n- Roots: ../tasks\n- Roots: ../docs\n' >"$W/tasks/SPINE.md"
  out="$("$RESOLVE" json "$W/dev/app/Tasks/$T" 2>"$ERR")"
  got="$(physical_roots <<<"$out")" || { echo "$got"; echo "$out"; return 1; }
  expected="$(for d in tasks docs; do python3 -c 'import os,sys; print(os.path.realpath(sys.argv[1]))' "$W/$d"; done | sort)"
  [ "$got" = "$expected" ] || { echo "$out"; return 1; }
}

@test "a .step opened through a link inherits the epic's settings" {
  out="$("$RESOLVE" json "$W/dev/app/Tasks/$T/02-core.step" 2>"$ERR")"
  [ "$(field walkthrough <<<"$out")" = brief ] || { echo "$out"; return 1; }
  [ "$(python3 -c 'import json,sys; print(json.load(sys.stdin)["sources"]["walkthrough"])' <<<"$out")" = epic ] \
    || { echo "$out"; return 1; }
  [ "$(physical_roots <<<"$out")" = "$(expected_roots)" ] || { echo "$out"; return 1; }
}

@test "a symlinked SPINE.md keeps its relative paths based where the link sits" {
  # Resolving the file would move the base of every ## Paths line to the folder the file lives in:
  # here, one level deeper, where no ../ line names a folder that exists.
  mkdir -p "$W/shared/config"
  mv "$W/tasks/SPINE.md" "$W/shared/config/SPINE.md"
  ln -s ../shared/config/SPINE.md "$W/tasks/SPINE.md"
  out="$("$RESOLVE" json "$W/dev/app/Tasks/$T" 2>"$ERR")"
  [ "$(physical_roots <<<"$out")" = "$(expected_roots)" ] || { echo "$out"; return 1; }
}

@test "a Roots line naming a linked checkout resolves to the checkout" {
  ln -s app "$W/dev/app-link"
  printf '[LANG] = [ru]\n\n## Paths\n\n- Roots: ../dev/app-link\n' >"$W/tasks/SPINE.md"
  out="$("$RESOLVE" json "$W/dev/Tasks/$T" 2>"$ERR")"
  got="$(physical_roots <<<"$out")" || { echo "$got"; echo "$out"; return 1; }
  expected="$(for d in tasks dev/app; do python3 -c 'import os,sys; print(os.path.realpath(sys.argv[1]))' "$W/$d"; done | sort)"
  [ "$got" = "$expected" ] || { echo "$out"; return 1; }
}

@test "a missing target, a link loop and a dangling Tasks link end with a diagnosis, not a hang" {
  ln -s loop-b "$W/dev/packages/loop-a"
  ln -s loop-a "$W/dev/packages/loop-b"
  printf '[LANG] = [ru]\n\n## Paths\n\n- External packages: ../dev/packages/*\n- Roots: ../nowhere\n' >"$W/tasks/SPINE.md"
  out="$("$RESOLVE" json "$W/dev/app/Tasks/$T" 2>"$ERR")"
  got="$(physical_roots <<<"$out")" || { echo "$got"; echo "$out"; return 1; }
  expected="$(for d in tasks dev/packages/core; do python3 -c 'import os,sys; print(os.path.realpath(sys.argv[1]))' "$W/$d"; done | sort)"
  [ "$got" = "$expected" ] || { echo "$out"; return 1; }
  grep -qF "Roots '../nowhere' names no folder" "$ERR" || { cat "$ERR"; return 1; }
  ln -s ../gone "$W/dev/Broken"
  run "$RESOLVE" json "$W/dev/Broken/$T"
  [ "$status" -eq 2 ]
  case "$output" in *"not a directory"*) ;; *) echo "$output"; return 1 ;; esac
}

@test "docs-route finds a package registry the same way through the link as directly" {
  printf '## Core\n\ngenre: state\nplaces:\n  - Docs/\ncovers:\n  - Sources/**\n' >"$W/dev/packages/core/DocsMap.md"
  direct="$("$DR" registry "$W/tasks" --paths </dev/null)"
  case "$direct" in *"Core"*) ;; *) echo "$direct"; return 1 ;; esac
  for via in "dev/Tasks" "dev/app/Tasks"; do
    linked="$("$DR" registry "$W/$via" --paths </dev/null)"
    [ "$linked" = "$direct" ] || { echo "$via:"; diff <(echo "$direct") <(echo "$linked"); return 1; }
  done
}
