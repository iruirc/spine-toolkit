#!/usr/bin/env bats
# ManualChecks.md is a hand-run script for a tester who knows the product but not the code. A case
# that leaned on code, on another case's end state or on a step holding two actions passed the
# cold reader often enough that the format needed a measurement. This lint is that measurement:
# its eight checks are the executable definition of the case format the manual-checks skill
# describes, and its fixtures are cases that format accepts.

setup() {
  ROOT="$(cd -- "$(dirname -- "$BATS_TEST_FILENAME")/../../.." && pwd)"
  LINT="$ROOT/scripts/lint-manual-checks.sh"
  FIX="$ROOT/tests/fixtures/manual-checks"
  F="$BATS_TEST_TMPDIR/ManualChecks.md"
  # The parts of a case a test may replace; everything else is a case the format accepts.
  WHAT='one tap on plus adds one item to the cart.'
  PRE='- The cart holds one Green tea at 4.50.'
  ACTION='Tap the plus button on the Green tea row'
  EXPECTED='The quantity reads 2'
  CODE='(cart/quantity_stepper.src:41)'
}

# A Russian word the lint must match, written as \uXXXX escapes: no Cyrillic outside *.ru.md.
ru() { python3 -c 'import sys; sys.stdout.write(sys.argv[1].encode().decode("unicode_escape"))' "$1"; }

case_md() { # $1 id; the replaceable parts come from the variables set in setup
  cat <<EOF
### MC-$1. The plus button raises the quantity

**Priority:** P1 — the main scenario

**Traces to:** Plan.md, Manual acceptance, item 1

**What it checks:** $WHAT

**Preconditions:**

$PRE

**Test data:** Green tea, price 4.50.

**Steps:**

| # | Action | Data | Expected | Actual |
|---|---|---|---|---|
| 1 | Open the cart from the cart icon, top right | — | One row, Green tea, quantity 1 | |
| 2 | $ACTION | — | $EXPECTED | |

**Expected result:** the cart holds two Green tea.

**Failure looks like:** the quantity stays at 1.

**Cleanup:** tap the minus button until the row disappears.

**Code:** $CODE

**Status:** ☐ PASS ☐ FAIL ☐ BLOCKED — reason: ______

**Notes / attachments:** ______

EOF
}

write() { # $@ cases, each a whole case text; none given means one case built by case_md
  [ "$#" -gt 0 ] || set -- "$(case_md 1)"
  { printf '# Manual Checks — Cart\n\n[COVERS] = a1b2c3d\n\n## Run record\n\n| Field | Value |\n|---|---|\n| Build | ______ |\n\n'
    printf '## Scope\n\nThe cart lets a shopper change a quantity.\n\n## Preparation\n\nSign in with the test account.\n\n## Cases\n\n'
    for c in "$@"; do printf '%s\n\n' "$c"; done
    printf '## On failure — bug report\n\n**Title:** MC-N: what broke\n\n## Not covered\n\nnone\n'; } >"$F"
}

drop() { # $1 a fixed string; removes every line of $F holding it
  grep -vF -- "$1" "$F" >"$F.tmp" || true
  mv "$F.tmp" "$F"
}

expect() { # $1 the exact expected output; the lint must exit 1
  run "$LINT" "$F"
  [ "$status" -eq 1 ] || { echo "status $status: $output"; return 1; }
  [ "$output" = "$1" ] || { printf 'expected: %s\n     got: %s\n' "$1" "$output"; return 1; }
}

clean() { # $1 a path; the lint must exit 0 with no output
  run "$LINT" "$1"
  [ "$status" -eq 0 ] || { echo "status $status: $output"; return 1; }
  [ -z "$output" ] || { echo "$output"; return 1; }
}

@test "the English and the Russian fixtures, and the case the helper builds, pass" {
  clean "$FIX/good.en.md"
  clean "$FIX/good.ru.md"
  write
  clean "$F"
}

@test "case: a missing label is named, once per label" {
  write
  drop '**Cleanup:**'
  drop '**Traces to:**'
  expect "$(printf '%s\n%s' 'ManualChecks.md: case: missing **Traces to:** (### MC-1.)' 'ManualChecks.md: case: missing **Cleanup:** (### MC-1.)')"
}

@test "case: a repeated id and a heading under ## Cases that is not MC-<n> are named" {
  write "$(case_md 1)" "$(case_md 1)" '### 3. The minus button lowers the quantity'
  expect "$(printf '%s\n%s' 'ManualChecks.md: case: heading is not ### MC-<n>. <observable behaviour> (### 3.)' 'ManualChecks.md: case: id MC-1 is used twice (### MC-1.)')"
}

@test "case: a heading with no behaviour after the id is named" {
  write "$(case_md 1 | sed '1s/.*/### MC-1./')"
  expect 'ManualChecks.md: case: no observable behaviour after the id (### MC-1.)'
}

@test "case: an old-format file is named as the old format, not passed" {
  run "$LINT" "$FIX/old-format.en.md"
  [ "$status" -eq 1 ] || { echo "status $status: $output"; return 1; }
  grep -qF 'ManualChecks.md: case: old format, ### <n>. headings instead of ### MC-<n>. (### 1.)' <<<"$output" \
    || { echo "$output"; return 1; }
  [ "$(grep -c 'old format' <<<"$output")" -eq 1 ] || { echo "$output"; return 1; }
}

@test "steps: a table without the Actual column is named" {
  write "$(case_md 1 | sed -e 's/^| # | Action | Data | Expected | Actual |$/| # | Action | Data | Expected |/')"
  expect 'ManualChecks.md: steps: header is not | # | Action | Data | Expected | Actual | (### MC-1.)'
}

@test "steps: an empty Action or Expected is named, a dash is not empty" {
  ACTION=' ' EXPECTED='—'
  write
  expect 'ManualChecks.md: steps: step 2 has an empty Action (### MC-1.)'
  ACTION='—' EXPECTED=' '
  write
  expect 'ManualChecks.md: steps: step 2 has an empty Expected (### MC-1.)'
}

@test "steps: a case with no steps table is named" {
  write "$(case_md 1 | grep -v '^|')"
  expect 'ManualChecks.md: steps: no steps table (### MC-1.)'
}

@test "compound: then, a semicolon and repeat steps in Action are named" {
  ACTION='Tap plus, then tap minus'
  write
  expect 'ManualChecks.md: compound: "then" in the Action of step 2 (### MC-1.)'
  ACTION='Tap plus; tap minus'
  write
  expect 'ManualChecks.md: compound: ";" in the Action of step 2 (### MC-1.)'
  ACTION='Repeat steps 1-2 twice'
  write
  expect 'ManualChecks.md: compound: "Repeat steps" in the Action of step 2 (### MC-1.)'
  # A semicolon in Expected is two checkable facts, not two actions.
  ACTION='Tap plus' EXPECTED='Quantity 2; total 9.00'
  write
  clean "$F"
}

@test "compound: the Russian words for then, afterwards, at once and repeat steps are named" {
  local w
  for w in '\u0437\u0430\u0442\u0435\u043c' '\u041f\u043e\u0442\u043e\u043c' '\u0438 \u0441\u0440\u0430\u0437\u0443' \
           '\u043f\u043e\u0432\u0442\u043e\u0440\u0438\u0442\u044c \u0448\u0430\u0433\u0438'; do
    ACTION="Tap plus $(ru "$w") minus"
    write
    run "$LINT" "$F"
    [ "$status" -eq 1 ] || { echo "status $status for $w: $output"; return 1; }
    grep -qF "compound: \"$(ru "$w")\" in the Action of step 2 (### MC-1.)" <<<"$output" || { echo "$output"; return 1; }
  done
  # "because" starts with the letters of "afterwards" and is one action.
  ACTION="Tap plus $(ru '\u043f\u043e\u0442\u043e\u043c\u0443') it is there"
  write
  clean "$F"
}

@test "code: CamelCase, a source file, a dotted name and a gloss outside **Code:** are named" {
  EXPECTED='CartBadgeView shows 2'
  write
  expect 'ManualChecks.md: code: "CartBadgeView" in the Expected of step 2 (### MC-1.)'
  EXPECTED='The quantity reads 2'
  ACTION='Open CartScreen.kt'
  write
  expect "$(printf '%s\n%s' 'ManualChecks.md: code: "CartScreen" in the Action of step 2 (### MC-1.)' 'ManualChecks.md: code: "CartScreen.kt" in the Action of step 2 (### MC-1.)')"
  ACTION='Tap plus'
  PRE='- The flag cart.stepper.enabled is on.'
  write
  expect 'ManualChecks.md: code: "cart.stepper.enabled" in **Preconditions:** (### MC-1.)'
  PRE='- The cart holds one Green tea.'
  WHAT='the stepper adds one item (quantity_stepper.src:41).'
  write
  expect 'ManualChecks.md: code: "(quantity_stepper.src:41)" in **What it checks:** (### MC-1.)'
}

@test "code: versions, decimals and plain words are not code" {
  EXPECTED='The footer reads version 2.1.0; the plus fades within 0.8 s'
  ACTION='Tap the iPhone share button, e.g. the one at the top'
  PRE='- Build 3.14.2 is installed; the total reads 4.50.'
  write
  clean "$F"
}

@test "codeslot: a **Code:** field with no file:line is named" {
  CODE='the stepper'
  write
  expect 'ManualChecks.md: codeslot: no file:line in **Code:** (### MC-1.)'
}

@test "chain: after case N, state right after and Changes in this revision are named" {
  PRE='- The state right after the previous case.'
  write
  expect 'ManualChecks.md: chain: "state right after" (### MC-1.)'
  PRE='- The cart as it is after case 1.'
  write
  expect 'ManualChecks.md: chain: "after case 1" (### MC-1.)'
  PRE='- The cart holds one Green tea.'
  write
  printf '## Changes in this revision\n\n- MC-1 added.\n' >>"$F"
  expect 'ManualChecks.md: chain: "Changes in this revision" (## Changes in this revision)'
}

@test "chain: the Russian forms are named" {
  local w
  for w in '\u043f\u043e\u0441\u043b\u0435 \u043a\u0435\u0439\u0441\u0430 1' \
           '\u0441\u043e\u0441\u0442\u043e\u044f\u043d\u0438\u0435 \u0441\u0440\u0430\u0437\u0443 \u043f\u043e\u0441\u043b\u0435' \
           '\u0418\u0437\u043c\u0435\u043d\u0435\u043d\u0438\u044f \u044d\u0442\u043e\u0439 \u0440\u0435\u0434\u0430\u043a\u0446\u0438\u0438'; do
    PRE="- $(ru "$w")"
    write
    expect "ManualChecks.md: chain: \"$(ru "$w")\" (### MC-1.)"
  done
}

@test "budget: a case over 40 lines, ## Scope over 8 and ## Preparation over 60 are named" {
  # The helper's case is 32 lines, heading to the last field: eight more steps make 40, nine make 41.
  long() { local rows='' i
    for i in $(seq 3 $((2 + $1))); do rows="$rows| $i | Tap plus | — | Quantity $i | |\\n"; done
    write "$(case_md 1 | awk -v rows="$rows" '{ print } /^\| 2 \|/ { printf "%s", rows }')"; }
  long 8
  clean "$F"
  long 9
  expect 'ManualChecks.md: budget: case of 41 lines, more than 40 (### MC-1.)'
  write
  python3 - "$F" <<'PY'
import sys
p = sys.argv[1]
t = open(p, encoding='utf-8').read()
t = t.replace('The cart lets a shopper change a quantity.\n', ''.join('Scope line %d.\n' % i for i in range(9)))
t = t.replace('Sign in with the test account.\n', ''.join('Preparation line %d.\n' % i for i in range(61)))
open(p, 'w', encoding='utf-8').write(t)
PY
  expect "$(printf '%s\n%s' 'ManualChecks.md: budget: ## Scope of 9 lines, more than 8 (## Scope)' 'ManualChecks.md: budget: ## Preparation of 61 lines, more than 60 (## Preparation)')"
}

@test "file: a missing ## Run record, ## On failure and [COVERS] are named" {
  write
  drop '## Run record'
  drop '## On failure'
  drop '[COVERS]'
  expect "$(printf '%s\n%s\n%s' 'ManualChecks.md: file: missing [COVERS] (file)' 'ManualChecks.md: file: missing ## Run record (file)' 'ManualChecks.md: file: missing ## On failure (file)')"
}

@test "a folder is checked through its ManualChecks.md; a folder without one is nothing to measure" {
  CODE='the stepper'
  write
  run "$LINT" "$BATS_TEST_TMPDIR"
  [ "$status" -eq 1 ] || { echo "status $status: $output"; return 1; }
  [ "$output" = 'ManualChecks.md: codeslot: no file:line in **Code:** (### MC-1.)' ] || { echo "$output"; return 1; }
  mkdir "$BATS_TEST_TMPDIR/empty"
  clean "$BATS_TEST_TMPDIR/empty"
}

@test "a missing file is nothing to measure" {
  clean "$BATS_TEST_TMPDIR/absent.md"
}

@test "no argument, or two, is a usage error" {
  run "$LINT"
  [ "$status" -eq 2 ] || { echo "status $status"; return 1; }
  run "$LINT" "$F" "$F"
  [ "$status" -eq 2 ] || { echo "status $status"; return 1; }
}
