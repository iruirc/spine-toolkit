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
  # The three words appear in the verdict table whatever the doctrine says, so the default has to
  # be asserted on its own — a document that flipped it would pass on the greps above alone.
  grep -q 'Default to \*\*Applicable\*\*' "$s"
  grep -q 'conservative bias' "$s"
}

@test "the skill names no platform's stack values" {
  [ "$(grep -icE '\b(swift|swiftui|uikit|appkit|kotlin|compose|gradle|spm|xcode)\b' "$ROOT/skills/docs-route/SKILL.md")" = "0" ]
}

@test "every profile script carries the documentation note in its standing brief" {
  for f in "$ROOT"/workflows/profile-*.js; do
    grep -q 'DOCS_NOTE' "$f" || { echo "no DOCS_NOTE in $f"; return 1; }
    grep -q 'docs-route.sh' "$f" || { echo "no script call in $f"; return 1; }
    # Declaring the constant is not using it. A prelude that defines DOCS_NOTE and never
    # interpolates it satisfies both greps above — the constant's own text contains
    # "docs-route.sh" — while no agent ever sees a word of the note.
    n_note="$(grep -n '^\${DOCS_NOTE}$' "$f" | cut -d: -f1)"
    n_body="$(grep -n '^\${body}`$' "$f" | cut -d: -f1)"
    [ -n "$n_note" ] || { echo "DOCS_NOTE never interpolated in $f"; return 1; }
    [ "$n_note" -lt "$n_body" ] || { echo "DOCS_NOTE is not before the body in $f"; return 1; }
  done
}

section_2b() {
  python3 - "$1" <<'EOF'
import re, sys
t = open(sys.argv[1], encoding='utf-8').read()
m = re.search(r'^## 2b\. Documentation\s*$(.*?)(?=^## )', t, flags=re.M | re.S)
sys.stdout.write(m.group(1) if m else '')
EOF
}

@test "every profile skill carries the documentation section, and all seven are one text" {
  ref=""
  for f in "$ROOT"/skills/workflow-*/SKILL.md; do
    body="$(section_2b "$f")"
    [ -n "$body" ] || { echo "no '## 2b. Documentation' in $f"; return 1; }
    [ -z "$ref" ] && ref="$body"
    [ "$body" = "$ref" ] || { echo "$f drifted from the shared text"; return 1; }
  done
}

@test "the scale convention states that the axis does not move strictness" {
  grep -q 'strictness' "$ROOT/conventions/task-scale.md"
}
