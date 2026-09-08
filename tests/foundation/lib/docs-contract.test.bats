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
  grep -q '`progress`' "$CONV"
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
    # The constant is interpolated and gated, not merely declared: a prelude that defined it and
    # never used it would satisfy the two greps above, since its own text names the script.
    grep -q '^\${DOCS_NOTE}\${body}`$' "$f" || { echo "DOCS_NOTE not interpolated before the body in $f"; return 1; }
    grep -q "A.docs === 'off'" "$f" || { echo "DOCS_NOTE is not gated on the contract field in $f"; return 1; }
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
  # The word appears in prose either way; what has to be true is that the claim sits in the
  # section holding what the axis does NOT govern, which is where a reader looks for it.
  section="$(awk '/^## What the axis does not govern/{f=1} f' "$ROOT/conventions/task-scale.md")"
  case "$section" in *strictness*) ;; *) echo "the claim is not in that section"; return 1 ;; esac
}

@test "the Docs/ rudiment is gone from every surface" {
  # This file names both strings in order to search for them, so it excludes itself; without
  # the exclusion the test can never pass and would be deleted rather than fixed.
  self=':!tests/foundation/lib/docs-contract.test.bats'
  hits="$(git -C "$ROOT" grep -l 'Docs/{architecture' -- . "$self" || true)"
  [ -z "$hits" ] || { echo "$hits"; return 1; }
  hits="$(git -C "$ROOT" grep -l 'auq_create_docs_structure' -- . "$self" || true)"
  [ -z "$hits" ] || { echo "$hits"; return 1; }
}

@test "setup offers the registry instead" {
  grep -q 'auq_create_docs_map' "$ROOT/skills/setup/SKILL.md"
  grep -q '^## auq_create_docs_map$' "$ROOT/skills/setup/locales/en.md"
  grep -q '^## auq_create_docs_map$' "$ROOT/skills/setup/locales/ru.md"
}

@test "Done regenerates the progress components on every surface that names the step" {
  # Three documents describe the Done step: Method A's prelude note, Method B's section, and the
  # skill an agent applies. A step named in two of the three is how the methods drift.
  for f in "$ROOT"/skills/workflow-*/SKILL.md; do
    section_2b "$f" | grep -q '`progress`' || { echo "no progress call in $f"; return 1; }
  done
  for f in "$ROOT"/workflows/profile-*.js; do
    grep -q 'DOCS_NOTE.*"progress"' "$f" || { echo "no progress call in $f"; return 1; }
  done
  grep -q '^| Done | `progress' "$ROOT/skills/docs-route/SKILL.md"
}

@test "task-walkthrough states which half of a progress component is generated" {
  grep -q 'spine:steps' "$ROOT/skills/task-walkthrough/SKILL.md"
}
