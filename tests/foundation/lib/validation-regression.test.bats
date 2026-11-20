#!/usr/bin/env bats
# changed: sweep skills workflows
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
  run grep -rn 'full test run\|full regression' "$ROOT"/skills/workflow-* "$ROOT/workflows" \
    "$ROOT/conventions/stage-dispatch.md" "$ROOT/conventions/platform-contract.md"
  [ "$status" -eq 1 ] || { echo "$output"; return 1; }
}

@test "every Method B Validation reads validation_ranges and Review reads its record" {
  for p in feature bug refactor test quick; do
    f="$ROOT/skills/workflow-$p/SKILL.md"
    for t in '`validation_ranges`' '## Regression set' '`[VALIDATED_COMMIT]`' 'lint-validation-scope.sh' "## Validation's regression" 'module of the set that Validation did not run' '`blocking_findings`, even when the re-run is green'; do
      grep -qF -- "$t" "$f" || { echo "workflow-$p/SKILL.md lost: $t"; return 1; }
    done
    ! grep -qF 'full test run' "$f" || { echo "workflow-$p/SKILL.md still asks for a full test run"; return 1; }
  done
  grep -qF 'validation_ranges.rerun' "$ROOT/conventions/stage-dispatch.md" || { echo "stage-dispatch.md does not name validation_ranges.rerun"; return 1; }
}

subsection() { # $1 file, $2 heading text: the body up to the next ## or ### heading
  awk -v h="### $2" '$0==h{f=1;next} f&&/^##/{exit} f' "$1"
}

@test "phase-verification classifies failures outside the task" {
  grep -qxF '### Failures outside the task' "$SKILL" || { echo "no ### Failures outside the task"; return 1; }
  sec="$(subsection "$SKILL" 'Failures outside the task')"
  for t in 'usage search' 'Doubt keeps it inside' 'even when the test is in the registry' 'a missing registry is an empty one' \
    '`PASSED_WITH_FLAKES`' '`FAILED` > `FLAKY` > `PASSED_WITH_FLAKES` > `PASSED`' 'up to 3' 'first green' 'no second full run' \
    '`outside_failures`' '`known_failures_cleared`' '`known`' '`flaky`' '`red`' 'conventions/known-failures.md'; do
    grep -qF -- "$t" <<<"$sec" || { echo "the subsection lost: $t"; return 1; }
  done
  [ "$(grep -c '^|' <<<"$sec")" -eq 8 ] || { echo "the status table is not a header, a rule and six rows"; return 1; }
}

@test "a re-run carries green whole-module runs of phases and of earlier Validations" {
  sec="$(section "$SKILL" "Validation's regression")"
  for t in '`ran:`' 'carried <sha> (phase <N>)' 'carried <sha> (validation)' 'whatever its status' 'latest'; do
    grep -qF -- "$t" <<<"$sec" || { echo "the re-run paragraph lost: $t"; return 1; }
  done
}

@test "task-documents defines ## Outside the task" {
  doc="$ROOT/skills/task-documents/SKILL.md"
  sec="$(section "$doc" 'Validation.md')"
  grep -qF '`| Repository | Module | Test | Outcome | Entry | Why outside | Runs |`' <<<"$sec" \
    || { echo "no ## Outside the task header"; return 1; }
  for t in '`## Outside the task`' '`carried <sha> (phase <N>)`' '`carried <sha> (validation)`' '`reach`' '`PASSED_WITH_FLAKES`'; do
    grep -qF -- "$t" <<<"$sec" || { echo "Validation.md section lost: $t"; return 1; }
  done
}
