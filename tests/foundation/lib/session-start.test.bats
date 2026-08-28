#!/usr/bin/env bats
# The SessionStart hook is the only channel that reaches an already-installed
# project, and its marker check is what keeps it from costing context in every
# unrelated repo. Both halves are load-bearing: a wrong marker name makes the
# hook silent in configured projects, a missing check makes it fire everywhere.

setup() {
  ROOT="$(cd -- "$(dirname -- "$BATS_TEST_FILENAME")/../../.." && pwd)"
  TMP="$(mktemp -d)"
}

teardown() { rm -rf "$TMP"; }

@test "hook stays silent without a toolkit marker" {
  run bash -c "printf '{\"cwd\":\"$TMP\"}' | '$ROOT/hooks/session-start'"
  [ -z "$output" ]
}

@test "hook fires on the project config" {
  touch "$TMP/CLAUDE-spine-toolkit.md"
  run bash -c "printf '{\"cwd\":\"$TMP\"}' | '$ROOT/hooks/session-start'"
  [ -n "$output" ]
}

@test "hook fires on Tasks/ACTIVE" {
  mkdir -p "$TMP/Tasks/ACTIVE"
  run bash -c "printf '{\"cwd\":\"$TMP\"}' | '$ROOT/hooks/session-start'"
  [ -n "$output" ]
}
