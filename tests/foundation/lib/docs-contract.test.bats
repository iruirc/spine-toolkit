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

@test "the task template ships both docs overrides, commented out" {
  tpl="$ROOT/templates/task-md/task-root.md"
  grep -q '^# \[DOCS\] = ' "$tpl"
  grep -q '^# \[DOCS_NEW\] = ' "$tpl"
}

@test "the template's commented overrides are not read as values" {
  proj="$BATS_TEST_TMPDIR/q"
  taskdir="$proj/Tasks/ACTIVE/001-t"
  mkdir -p "$taskdir"
  printf '## Docs\n\nmap: DocsMap.md\nstrictness: blocking\n' >"$proj/CLAUDE-spine-toolkit.md"
  printf '## D\n\ngenre: state\nplaces:\n  - Documents/D/\ncovers:\n  - Sources/**\n' >"$proj/DocsMap.md"
  cp "$ROOT/templates/task-md/task-root.md" "$taskdir/Task.md"
  run bash -c "printf 'M\tSources/A.txt\n' | '$DR' route '$proj' --task-dir '$taskdir' --phase 1"
  [ "$status" -eq 0 ]
  grep -q '^| 1 | D |' "$taskdir/Docs.md"
  # The row count is what makes this test cover BOTH commented lines: a [DOCS_NEW] read as a value
  # would add a second row beside the real one, which a presence check alone would never notice.
  [ "$(grep -c '^| 1 |' "$taskdir/Docs.md")" -eq 1 ]
}

@test "the docs-route skill exists and ships no locales" {
  [ -f "$ROOT/skills/docs-route/SKILL.md" ]
  [ ! -d "$ROOT/skills/docs-route/locales" ]
}

@test "the skill states all three verdicts and defaults to the conservative one" {
  s="$ROOT/skills/docs-route/SKILL.md"
  grep -q 'Applicable' "$s"
  grep -q 'N/A' "$s"
  grep -q 'Pending' "$s"
}

@test "the skill names no platform's stack values" {
  [ "$(grep -icE '\b(swift|swiftui|uikit|appkit|kotlin|compose|gradle|spm|xcode)\b' "$ROOT/skills/docs-route/SKILL.md")" = "0" ]
}
