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

# A log written on the spot: one row per argument, `phases modules driver execute validation review fix_rounds fix_time`.
write_log() {
  local log="$1" n=0 line
  shift
  {
    echo '# Agent run log'
    echo
    echo '| date | task_id | type | mode | phases | modules | driver | forecast | actual | execute | validation | review | fix_rounds | fix_time | gates_forecast | gates | source | in_range | variance_reason |'
    echo '|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|'
    for line in "$@"; do
      n=$((n + 1))
      read -r ph mo dr ex va re fr ft <<<"$line"
      echo "| 2026-02-0$n | 00$n-x | FEATURE | manual | $ph | $mo | $dr | 1h00m–2h00m | 1h30m | $ex | $va | $re | $fr | $ft | 1–2 | 1 | workflow | in | |"
    done
  } >"$log"
}

@test "a negative driver_scenario is dropped and named on stderr" {
  log="$BATS_TEST_TMPDIR/log.md"
  # driver = no: 30/1 twice, so a driver run is expected to cost 30 per module; the driver rows cost 10 and 20: 10-30, 20-30
  write_log "$log" '2 1 no 20 30 10 0 0' '2 1 no 20 30 10 0 0' '2 1 yes 20 10 10 0 0' '2 1 yes 20 20 10 0 0'
  run --separate-stderr "$RC" "$log"
  [ "$status" -eq 0 ]
  [[ "$output" != *driver_scenario* ]] || { echo "$output"; false; }
  [[ "$output" == *'| execute_per_phase | 10–10 | median 10, 4 rows |'* ]] || { echo "$output"; false; }
  [ "$stderr" = 'run-calibration: driver_scenario: 2 non-positive samples dropped' ] || { echo "$stderr"; false; }
}

@test "a zero fix_time is dropped and named on stderr" {
  log="$BATS_TEST_TMPDIR/log.md"
  write_log "$log" '2 1 no 20 10 10 1 0' '2 1 no 20 10 10 0 0' '2 1 no 20 10 10 0 0'
  run --separate-stderr "$RC" "$log"
  [ "$status" -eq 0 ]
  [[ "$output" != *fix_round* ]] || { echo "$output"; false; }
  [ "$stderr" = 'run-calibration: fix_round: 1 non-positive samples dropped' ] || { echo "$stderr"; false; }
}

@test "driver rows only: driver_scenario has nothing to subtract" {
  log="$BATS_TEST_TMPDIR/log.md"
  write_log "$log" '2 1 yes 20 40 10 0 0' '2 1 yes 20 40 10 0 0' '2 1 yes 20 40 10 0 0'
  run --separate-stderr "$RC" "$log"
  [ "$status" -eq 0 ]
  [[ "$output" != *driver_scenario* ]] || { echo "$output"; false; }
  [[ "$output" != *validation_per_module* ]] || { echo "$output"; false; }
  [ "$stderr" = 'run-calibration: driver_scenario: no driver = no rows to subtract' ] || { echo "$stderr"; false; }
}

@test "a log with the wrong header names it on stderr and counts no rows" {
  log="$BATS_TEST_TMPDIR/log.md"
  printf '%s\n' '| date | task_id | actual |' '|---|---|---|' '| 2026-02-01 | 001-x | 1h |' >"$log"
  run --separate-stderr "$RC" "$log"
  [ "$status" -eq 0 ]
  [ "$output" = 'run-calibration: 0 usable rows, need 3; nothing proposed' ] || { echo "$output"; false; }
  [ "$stderr" = "run-calibration: no table with the agent-run-log header in $log" ] || { echo "$stderr"; false; }
}

@test "an unknown source value is a malformed row" {
  log="$BATS_TEST_TMPDIR/log.md"
  cp "$FX/five-rows.md" "$log"
  printf '%s\n' '| 2026-01-06 | 006-x | FEATURE | manual | 2 | 1 | no | 1h00m–2h00m | 1h30m | 20 | 10 | 12 | 0 | 0 | 1–2 | 1 | svn | in | |' >>"$log"
  run --separate-stderr "$RC" "$log"
  [ "$status" -eq 0 ]
  [[ "$stderr" == *'run-calibration: line 10: source is '*', skipped'* ]] || { echo "$stderr"; false; }
  [[ "$output" == *'| review | 14–18 | median 16, 5 rows |'* ]] || { echo "$output"; false; }
}

@test "a bad driver value is a malformed row" {
  log="$BATS_TEST_TMPDIR/log.md"
  cp "$FX/five-rows.md" "$log"
  printf '%s\n' '| 2026-01-06 | 006-x | FEATURE | manual | 2 | 1 | maybe | 1h00m–2h00m | 1h30m | 20 | 10 | 12 | 0 | 0 | 1–2 | 1 | workflow | in | |' >>"$log"
  run --separate-stderr "$RC" "$log"
  [ "$status" -eq 0 ]
  [[ "$stderr" == *'run-calibration: line 10: driver is '*', skipped'* ]] || { echo "$stderr"; false; }
  [[ "$output" == *'| review | 14–18 | median 16, 5 rows |'* ]] || { echo "$output"; false; }
}

@test "a row with no phases or no modules still feeds the keys that do not divide by them" {
  log="$BATS_TEST_TMPDIR/log.md"
  # phases 0: no execute_per_phase, validation 20/2 = 10, review 10
  # modules 0: execute 20/2 = 10, no validation_per_module, review 12, fix 40/1
  # both counts: execute 10, validation 10/1 = 10, review 14, fix 50/1
  # modules 0 with a driver: execute 10, driver 30 - 0*10 = 30, review 16
  write_log "$log" '0 2 no 0 20 10 0 0' '2 0 no 20 0 12 1 40' '2 1 no 20 10 14 1 50' '2 0 yes 20 30 16 0 0'
  run --separate-stderr "$RC" "$log"
  [ "$status" -eq 0 ]
  [ -z "$stderr" ] || { echo "$stderr"; false; }
  # review 10,12,14,16 -> 11.5..14.5 rounds half up to 12..15, median 13; fix 40,50 -> 42.5..47.5, median 45
  expected="$(printf '%s\n' \
    '| execute_per_phase | 10–10 | median 10, 3 rows |' \
    '| validation_per_module | 10–10 | median 10, 2 rows |' \
    '| driver_scenario | 30–30 | median 30, 1 rows |' \
    '| review | 12–15 | median 13, 4 rows |' \
    '| fix_round | 43–48 | median 45, 2 rows |')"
  [ "$output" = "$expected" ] || { echo "$output"; false; }
}
