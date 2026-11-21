#!/usr/bin/env bats
# run-calibration.sh reads the agent-run log and proposes coefficients for ## AgentRunCoefficients:
# a median and an interquartile range per key, from the workflow rows that are not EPIC rows.
# Every fixture is a log of neutral task ids; the expected numbers are worked out by hand in the comments.

bats_require_minimum_version 1.5.0

setup() {
  ROOT="$(cd -- "$(dirname -- "$BATS_TEST_FILENAME")/../../.." && pwd)"
  RC="$ROOT/scripts/run-calibration.sh"
  FX="$ROOT/tests/foundation/fixtures/run-calibration"
}

@test "fewer than three usable rows proposes nothing and says how many" {
  run --separate-stderr "$RC" "$FX/two-rows.md"
  [ "$status" -eq 0 ]
  [ "$output" = 'run-calibration: 2 usable rows, need 3; nothing proposed' ] || { echo "$output"; false; }
}

@test "git and EPIC rows are not used" {
  run --separate-stderr "$RC" "$FX/mixed.md"
  [ "$status" -eq 0 ]
  [ -z "$stderr" ] || { echo "$stderr"; false; }
  # three workflow rows: execute/phases 12,10,10; validation/modules 10,12,10; review 12,14,16
  expected="$(printf '%s\n' \
    '| execute_per_phase | 10–11 | median 10, 3 rows |' \
    '| validation_per_module | 10–11 | median 10, 3 rows |' \
    '| review | 13–15 | median 14, 3 rows |')"
  [ "$output" = "$expected" ] || { echo "$output"; false; }
}

@test "medians and quartiles per key" {
  run --separate-stderr "$RC" "$FX/five-rows.md"
  [ "$status" -eq 0 ]
  [ -z "$stderr" ] || { echo "$stderr"; false; }
  # execute/phases 12,10,10,8,9 -> 9..10 median 10; review 12,14,16,18,20 -> 14..18 median 16
  [[ "$output" == *$'| execute_per_phase | 9–10 | median 10, 5 rows |'* ]] || { echo "$output"; false; }
  [[ "$output" == *$'| review | 14–18 | median 16, 5 rows |'* ]] || { echo "$output"; false; }
  [ "$(printf '%s\n' "$output" | wc -l | tr -d ' ')" = 5 ] || { echo "$output"; false; }
  [ "$(printf '%s\n' "$output" | cut -d'|' -f2 | tr -d ' ' | paste -sd, -)" = \
    'execute_per_phase,validation_per_module,driver_scenario,review,fix_round' ] || { echo "$output"; false; }
}

@test "driver rows are kept apart" {
  run --separate-stderr "$RC" "$FX/five-rows.md"
  [ "$status" -eq 0 ]
  # driver = no rows: 10/1, 24/2, 20/2 = 10,12,10 -> 10..11 median 10, three rows
  [[ "$output" == *$'| validation_per_module | 10–11 | median 10, 3 rows |'* ]] || { echo "$output"; false; }
  # driver = yes rows: 40 - 1*10 = 30 and 80 - 3*10 = 50 -> 35..45 median 40, two rows
  [[ "$output" == *$'| driver_scenario | 35–45 | median 40, 2 rows |'* ]] || { echo "$output"; false; }
}

@test "fix_round uses only rows with fix rounds" {
  run --separate-stderr "$RC" "$FX/five-rows.md"
  [ "$status" -eq 0 ]
  # 40/1 and 120/2 = 40,60 -> 45..55 median 50; the three rows with no fix rounds are left out
  [[ "$output" == *$'| fix_round | 45–55 | median 50, 2 rows |'* ]] || { echo "$output"; false; }
}

@test "a key with no data of its own prints no line" {
  run --separate-stderr "$RC" "$FX/mixed.md"
  [ "$status" -eq 0 ]
  [[ "$output" != *driver_scenario* ]] || { echo "$output"; false; }
  [[ "$output" != *fix_round* ]] || { echo "$output"; false; }
}

@test "a malformed row is skipped with a warning" {
  log="$BATS_TEST_TMPDIR/log.md"
  cp "$FX/five-rows.md" "$log"
  printf '%s\n' '| 2026-01-06 | 006-x | FEATURE | manual | 2 | 1 | no |' >>"$log"
  printf '%s\n' '| 2026-01-07 | 007-x | FEATURE | manual | 2 | 1 | no | 1h00m–2h00m | 1h30m | soon | 10 | 12 | 0 | 0 | 1–2 | 1 | workflow | in | |' >>"$log"
  run --separate-stderr "$RC" "$log"
  [ "$status" -eq 0 ]
  [[ "$stderr" == *'run-calibration: line 10: '*', skipped'* ]] || { echo "$stderr"; false; }
  [[ "$stderr" == *'run-calibration: line 11: '*', skipped'* ]] || { echo "$stderr"; false; }
  # the five good rows are all that count
  [[ "$output" == *$'| execute_per_phase | 9–10 | median 10, 5 rows |'* ]] || { echo "$output"; false; }
}

@test "a missing log" {
  run --separate-stderr "$RC" "$BATS_TEST_TMPDIR/none.md"
  [ "$status" -eq 0 ]
  [ "$output" = "run-calibration: no log at $BATS_TEST_TMPDIR/none.md; nothing proposed" ] || { echo "$output"; false; }
}

@test "no argument exits 2" {
  run --separate-stderr "$RC"
  [ "$status" -eq 2 ]
  [[ "$stderr" == *usage* ]] || { echo "$stderr"; false; }
}
