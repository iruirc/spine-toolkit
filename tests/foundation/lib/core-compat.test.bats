#!/usr/bin/env bats
# A session whose core is older than its platform needs: scripts/lib/core_compat.py reads the
# platform's spine-toolkit range, resolve-settings.sh puts the verdict into json and open, and the
# orchestrator stops on it at step 5.7.

setup() {
  ROOT="$(cd -- "$(dirname -- "$BATS_TEST_FILENAME")/../../.." && pwd)"
}

# py <code>: runs the code with scripts/lib on the path and core_compat's names imported.
py() {
  python3 -c "
import sys
sys.dont_write_bytecode = True
sys.path.insert(0, '$ROOT/scripts/lib')
from core_compat import parse_version, in_range
$1"
}

@test "a version inside >=2.44.0 <3 is in range" {
  run py "print(in_range('2.44.0', '>=2.44.0 <3'), in_range('2.45.1', '>=2.44.0 <3'))"
  [ "$output" = "True True" ] || { echo "$output"; return 1; }
}

@test "a version on either side of >=2.44.0 <3 is out of range" {
  run py "print(in_range('2.43.9', '>=2.44.0 <3'), in_range('3.0.0', '>=2.44.0 <3'))"
  [ "$output" = "False False" ] || { echo "$output"; return 1; }
}

@test "a short version is padded with zeros" {
  run py "print(parse_version('3'), in_range('2.44', '>=2.44.0'))"
  [ "$output" = "(3, 0, 0) True" ] || { echo "$output"; return 1; }
}

@test "= > <= match exactly what they say" {
  run py "print(in_range('2.44.0', '=2.44.0'), in_range('2.44.0', '>2.44.0'), in_range('2.44.0', '<=2.44.0'))"
  [ "$output" = "True False True" ] || { echo "$output"; return 1; }
}

@test "a range or version it cannot read is None, never False" {
  run py "print(in_range('2.44.0', '^2.44.0'), in_range('2.44.0', ''), in_range('2.44.0-rc1', '>=2'), in_range('2.44.0', '>=2.44.0 || <1'))"
  [ "$output" = "None None None None" ] || { echo "$output"; return 1; }
}
