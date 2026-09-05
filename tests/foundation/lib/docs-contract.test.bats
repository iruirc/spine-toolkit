#!/usr/bin/env bats
# The registry format has three copies: the script that parses it, the convention that states
# it, and the template a project starts from. A template that does not parse is the copy a
# project actually gets, so it is checked by running the parser over it rather than by reading.

setup() {
  ROOT="$(cd -- "$(dirname -- "$BATS_TEST_FILENAME")/../../.." && pwd)"
  DR="$ROOT/scripts/docs-route.sh"
  CONV="$ROOT/conventions/docs-components.md"
  TPL="$ROOT/templates/docs-map/DocsMap.md"
}

@test "the convention names both declarable genres and no third one" {
  grep -q '`state`' "$CONV"
  grep -q '`tracker`' "$CONV"
}

@test "the convention names no platform's stack values" {
  [ "$(grep -icE '\b(swift|swiftui|uikit|appkit|kotlin|compose|gradle|spm|xcode)\b' "$CONV")" = "0" ]
}

@test "the shipped template parses as a registry" {
  proj="$BATS_TEST_TMPDIR/p"
  mkdir -p "$proj"
  printf '## Docs\n\nmap: DocsMap.md\nstrictness: advisory\n' >"$proj/CLAUDE-spine-toolkit.md"
  cp "$TPL" "$proj/DocsMap.md"
  run "$DR" registry "$proj"
  [ "$status" -eq 0 ]
}
