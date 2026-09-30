#!/usr/bin/env bats
# A case whose only code reference sat in ## Scope passed the cold reader, which never sees code,
# and Review, which had the rule in its brief. This lint is the measurement neither made.

setup() {
  ROOT="$(cd -- "$(dirname -- "$BATS_TEST_FILENAME")/../../.." && pwd)"
  LINT="$ROOT/scripts/lint-manual-checks.sh"
  F="$BATS_TEST_TMPDIR/ManualChecks.md"
}

write() { # $@ case bodies, one per argument
  { printf '# Manual Checks — 001\n[COVERS] = abc1234\n\n## Scope\n\nBuilt and tested (probe.src:9).\n\n## Cases\n\n'
    n=0; for body in "$@"; do n=$((n + 1)); printf '### %s. Case %s\n\n%s\n\n' "$n" "$n" "$body"; done
    printf '## Not covered\n\nnone\n'; } >"$F"
}

@test "a case carrying a code reference passes" {
  write '**Failure looks like:** the edge passes the line (snap_resolver:88)'
  run "$LINT" "$F"
  [ "$status" -eq 0 ] || { echo "$output"; return 1; }
  [ -z "$output" ] || { echo "$output"; return 1; }
}

@test "a case with no reference is named, even when ## Scope carries one" {
  write '**Failure looks like:** the edge passes the line (snap_resolver:88)' '**Failure looks like:** the greeting reads oddly'
  run "$LINT" "$F"
  [ "$status" -eq 1 ] || { echo "status $status: $output"; return 1; }
  [ "$output" = "ManualChecks.md: case 2: no code reference (## Grounding)" ] || { echo "$output"; return 1; }
}

@test "a reference in the steps table counts, a bare number in parentheses does not" {
  write '| 1 | Press Save | — | the toast shows (save_flow.src:12) |' '**By eye:** it waits (2 s)'
  run "$LINT" "$F"
  [ "$status" -eq 1 ] || { echo "status $status: $output"; return 1; }
  [ "$output" = "ManualChecks.md: case 2: no code reference (## Grounding)" ] || { echo "$output"; return 1; }
}

@test "a file with no cases, and a missing file, are nothing to measure" {
  write
  run "$LINT" "$F"
  [ "$status" -eq 0 ] || { echo "$output"; return 1; }
  run "$LINT" "$BATS_TEST_TMPDIR/absent.md"
  [ "$status" -eq 0 ] || { echo "$output"; return 1; }
}

@test "no argument is a usage error" {
  run "$LINT"
  [ "$status" -eq 2 ] || { echo "status $status"; return 1; }
}
