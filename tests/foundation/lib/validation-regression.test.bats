#!/usr/bin/env bats
# changed: sweep
# What Validation runs was "the full regression", and three agents read it three ways. The skill that
# already holds Perimeter and Dependent now defines the task's regression, and the text that used to
# ask Validation for a full run points there.

setup() {
  ROOT="$(cd -- "$(dirname -- "$BATS_TEST_FILENAME")/../../.." && pwd)"
  SKILL="$ROOT/skills/phase-verification/SKILL.md"
}

section() { # $1 file, $2 heading text: the body up to the next ## heading
  awk -v h="## $2" '$0==h{f=1;next} f&&/^## /{exit} f' "$1"
}

@test "phase-verification defines Validation's regression" {
  grep -qxF "## Validation's regression" "$SKILL" || { echo "no ## Validation's regression"; return 1; }
  sec="$(section "$SKILL" "Validation's regression")"
  for f in 'every module the task changed' 'depends on one of them, transitively' 'the application' 'neither built nor tested' 'carried'; do
    grep -qF "$f" <<<"$sec" || { echo "the section lost: $f"; return 1; }
  done
  ! grep -qF 'The full regression belongs to Validation' "$SKILL" || { echo "the intro still says the full regression belongs to Validation"; return 1; }
  who="$(section "$SKILL" 'Who does what')"
  ! grep -qF 'it runs the full regression' <<<"$who" || { echo "Who does what still says it runs the full regression"; return 1; }
  grep -qF "Validation's regression" <<<"$who" || { echo "Who does what does not point at the section"; return 1; }
  rev="$(section "$SKILL" 'Review')"
  grep -E '^[0-9]+\. .*outside the set' <<<"$rev" | grep -qF 'Minor' || { echo "no Minor finding for a module outside the set"; return 1; }
  grep -E '^[0-9]+\. .*did not run' <<<"$rev" | grep -qF 'Major' || { echo "no Major finding for a module that did not run"; return 1; }
  grep -qF 'goes into `blocking_findings`' <<<"$rev" || { echo "the unrun-module finding does not block"; return 1; }
}

@test "the directive keeps Validation's regression set, not a full regression" {
  grep -qF "Validation's regression set" "$ROOT/conventions/stage-dispatch.md" || { echo "stage-dispatch.md"; return 1; }
  grep -qF "Validation's regression set" "$ROOT/workflow-src/prelude.js" || { echo "prelude.js"; return 1; }
  ! grep -qF "Validation's full regression" "$ROOT/conventions/stage-dispatch.md" "$ROOT/workflow-src/prelude.js" \
    || { echo "the directive still says full regression"; return 1; }
}

@test "no core text asks Validation for a full test run" {
  skip "until Task 6"
  run grep -rn 'full test run\|full regression' "$ROOT"/skills/workflow-* "$ROOT/workflows" \
    "$ROOT/conventions/stage-dispatch.md" "$ROOT/conventions/platform-contract.md"
  [ "$status" -eq 1 ] || { echo "$output"; return 1; }
}
