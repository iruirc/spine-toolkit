#!/usr/bin/env bats
# ManualChecks.md is a hand-run script for a tester who knows the product but not the code. A case
# that leaned on code, on another case's end state or on a step holding two actions passed the
# cold reader often enough that the format needed a measurement. This lint is that measurement:
# its nine checks are the executable definition of the case format the manual-checks skill
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

**Status:** ☐ PASS ☐ FAIL ☐ BLOCKED — reason: ______

**Notes / attachments:** ______

EOF
}

write() { # $@ cases, each a whole case text; none given means one case built by case_md
  [ "$#" -gt 0 ] || set -- "$(case_md 1)"
  local c id
  { printf '# Manual Checks — Cart\n\n[COVERS] = a1b2c3d\n\n## Run record\n\n| Field | Value |\n|---|---|\n| Build | ______ |\n\n'
    printf '## Scope\n\nThe cart lets a shopper change a quantity.\n\n## Preparation\n\nSign in with the test account.\n\n## Cases\n\n'
    for c in "$@"; do printf '%s\n\n' "$c"; done
    printf '## On failure — bug report\n\n**Title:** MC-N: what broke\n\n## Not covered\n\nnone\n\n'
    printf '## Code references\n\n| Case | Code |\n|---|---|\n'
    for c in "$@"; do
      id="$(printf '%s\n' "$c" | sed -n 's/^### MC-\([0-9][0-9]*\)\..*/\1/p' | head -n 1)"
      [ -z "$id" ] || printf '| MC-%s | %s |\n' "$id" "$CODE"
    done; } >"$F"
}

# $F without its ## Code references section, which is the last one the helper writes. A plain
# grep -v on the table separator would take the steps table's too.
cut_refs() {
  python3 - "$F" <<'PY'
import re, sys
p = sys.argv[1]
t = open(p, encoding='utf-8').read()
open(p, 'w', encoding='utf-8').write(re.sub(r'\n*## Code references.*', '\n', t, flags=re.S))
PY
}

# A case in the old format: its **Code:** field sits inside it, above **Status:**.
old_case() { # $1 id
  case_md "$1" | awk -v id="$1" '/^\*\*Status:\*\*/ { print "**Code:** (a.src:" id ")"; print "" } { print }'
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

@test "case: a ## Cases with no case under it is named" {
  write '**Steps:** none yet.'
  expect 'ManualChecks.md: case: no case under ## Cases (## Cases)'
}

@test "case: cases at the wrong heading level are not cases, and ## Cases is named as empty" {
  write "$(case_md 1 | sed '1s/^###/####/')"
  expect 'ManualChecks.md: case: no case under ## Cases (## Cases)'
  write "$(case_md 1 | sed '1s/^###/##/')"
  expect 'ManualChecks.md: case: no case under ## Cases (## Cases)'
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

@test "compound: afterwards in Action is named, in any case, as a whole word only" {
  ACTION='Tap plus, afterwards tap minus'
  write
  expect 'ManualChecks.md: compound: "afterwards" in the Action of step 2 (### MC-1.)'
  ACTION='Tap plus. Afterwards tap minus'
  write
  expect 'ManualChecks.md: compound: "Afterwards" in the Action of step 2 (### MC-1.)'
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

@test "codeslot: a case with no row, a row with no file:line, and a row for no case are named" {
  write; drop '| MC-1 |'
  expect 'ManualChecks.md: codeslot: no row in ## Code references (### MC-1.)'
  CODE='the stepper'; write
  expect 'ManualChecks.md: codeslot: no file:line in ## Code references (### MC-1.)'
  CODE='(cart/quantity_stepper.src:41)'; write
  printf '| MC-9 | (cart/x.src:1) |\n' >>"$F"
  expect 'ManualChecks.md: codeslot: row for a case not in ## Cases (MC-9)'
}

@test "file: cases with no ## Code references are named once" {
  write "$(case_md 1)" "$(case_md 2)"
  cut_refs
  expect 'ManualChecks.md: file: missing ## Code references (file)'
}

@test "case: **Code:** inside a case is named once as the old format" {
  write "$(old_case 1)" "$(old_case 2)"
  cut_refs
  expect 'ManualChecks.md: case: old format, **Code:** inside a case instead of ## Code references (### MC-1.)'
  # The section may be there too: the old format is still named once, and no codeslot is added.
  write "$(old_case 1)" "$(old_case 2)"
  expect 'ManualChecks.md: case: old format, **Code:** inside a case instead of ## Code references (### MC-1.)'
}

@test "a file whose ## Cases reads none needs no ## Code references" {
  write
  python3 - "$F" <<'PY'
import sys, re
p = sys.argv[1]; t = open(p, encoding='utf-8').read()
t = re.sub(r'## Cases\n.*?## On failure', '## Cases\n\nnone — nothing needs a person.\n\n## On failure', t, flags=re.S)
t = re.sub(r'## Code references.*', '', t, flags=re.S)
open(p, 'w', encoding='utf-8').write(t)
PY
  clean "$F"
}

@test "a file:line in ## Code references is not code leaking out" {
  CODE='(cart/QuantityStepper.src:41), cart.view.model.update'
  write
  clean "$F"
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
  # The helper's case is 30 lines, heading to the last field: ten more steps make 40, eleven make 41.
  long() { local rows='' i
    for i in $(seq 3 $((2 + $1))); do rows="$rows| $i | Tap plus | — | Quantity $i | |\\n"; done
    write "$(case_md 1 | awk -v rows="$rows" '{ print } /^\| 2 \|/ { printf "%s", rows }')"; }
  long 10
  clean "$F"
  long 11
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
  [ "$output" = 'ManualChecks.md: codeslot: no file:line in ## Code references (### MC-1.)' ] || { echo "$output"; return 1; }
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

@test "a file ending in a closing block passes" {
  write
  printf '\n**Run:** drive_app=off; directive: «leave the cart package alone»\n**Device:** Phone B, set by this run\n' >>"$F"
  clean "$F"
}

# A case with its two step rows replaced: $1 and $2 are whole table rows.
steps_case() {
  case_md 1 | python3 -c 'import sys
r1, r2 = sys.argv[1], sys.argv[2]
for line in sys.stdin.read().split("\n")[:-1]:
    print(r1 if line.startswith("| 1 |") else r2 if line.startswith("| 2 |") else line)' "$1" "$2"
}

@test "scriptable: a case whose every step is a command in backticks is named" {
  write "$(steps_case '| 1 | Run `git status --short` | — | Prints nothing | |' \
                      '| 2 | Execute `git log -1 --format=%h` | — | Prints the sha from Run record | |')"
  expect 'ManualChecks.md: scriptable: no step needs a person, run it as a script (### MC-1.)'
}

@test "scriptable: the Russian forms of run the command are named" {
  # "Run the command of step 1" and "Launch `git status --short`", in the imperative.
  write "$(steps_case "| 1 | $(ru '\u0412\u044b\u043f\u043e\u043b\u043d\u0438\u0442\u0435 \u043a\u043e\u043c\u0430\u043d\u0434\u0443 \u0448\u0430\u0433\u0430 1') | — | Prints nothing | |" \
                      "| 2 | $(ru '\u0417\u0430\u043f\u0443\u0441\u0442\u0438\u0442\u0435') \`git status --short\` | — | Prints nothing | |")"
  expect 'ManualChecks.md: scriptable: no step needs a person, run it as a script (### MC-1.)'
}

@test "scriptable: a mixed case, a device step and a command, is not named" {
  write "$(steps_case '| 1 | Turn on airplane mode in Control Center | — | The plane icon shows in the status bar | |' \
                      '| 2 | Run `git status --short` | — | Prints nothing | |')"
  clean "$F"
}

@test "scriptable: a case with no steps table gives no scriptable finding" {
  write "$(case_md 1 | grep -v '^|')"
  expect 'ManualChecks.md: steps: no steps table (### MC-1.)'
}

# The file a person walks holds no instrument: a verdict read from a trace, a log or a recording is not
# the tester's, so it lives in Validation.md or in ## Not covered.
@test "instrument: a **By instrument:** field in a case is named" {
  write "$(case_md 1 | awk '/^\*\*Failure looks like:\*\*/ { print "**By instrument:** the log shows the update"; print "" } { print }')"
  expect 'ManualChecks.md: instrument: **By instrument:** in a case (### MC-1.)'
}

@test "instrument: a ## Reading the verdict section in the file is named" {
  write
  awk '/^## Cases$/ { print "## Reading the verdict"; print ""; print "Read the field item_count of the output."; print "" } { print }' "$F" >"$F.tmp"
  mv "$F.tmp" "$F"
  expect 'ManualChecks.md: instrument: ## Reading the verdict in the file (## Reading the verdict)'
}

@test "instrument: a screen recording in a step is named, in English and in Russian" {
  local action
  for action in 'Record the screen while you tap the plus button' 'Start recording and tap the plus button' \
                'Stop the screen recording' \
                "$(ru '\u0417\u0430\u043f\u0438\u0448\u0438\u0442\u0435 \u044d\u043a\u0440\u0430\u043d, \u043f\u043e\u043a\u0430 \u043d\u0430\u0436\u0438\u043c\u0430\u0435\u0442\u0435 \u043f\u043b\u044e\u0441')" \
                "$(ru '\u0412\u043a\u043b\u044e\u0447\u0438\u0442\u044c \u0437\u0430\u043f\u0438\u0441\u044c \u0438 \u043d\u0430\u0436\u0430\u0442\u044c \u043f\u043b\u044e\u0441')" \
                "$(ru '\u0421\u0434\u0435\u043b\u0430\u0442\u044c \u0437\u0430\u043f\u0438\u0441\u044c \u044d\u043a\u0440\u0430\u043d\u0430')"; do
    ACTION="$action"
    write
    run "$LINT" "$F"
    [ "$status" -eq 1 ] || { echo "not named: $action"; return 1; }
    [ "$output" = 'ManualChecks.md: instrument: a screen recording in a step (### MC-1., step 2)' ] \
      || { printf 'action: %s\n got: %s\n' "$action" "$output"; return 1; }
  done
}

# A case whose field $1 reads $2 instead of what case_md writes.
field_case() {
  case_md 1 | LABEL="$1" TEXT="$2" python3 -c 'import os, sys
tag = "**%s:**" % os.environ["LABEL"]
for line in sys.stdin.read().split("\n")[:-1]:
    print(tag + " " + os.environ["TEXT"] if line.startswith(tag) else line)'
}

@test "instrument: a screen recording in any field of a case is named, in English and in Russian" {
  local label text
  for label in 'What it checks' 'Preconditions' 'Test data' 'Expected result' 'Failure looks like' 'Cleanup' 'Notes / attachments'; do
    for text in 'screen recording, always' 'Record the screen while you tap the plus button' \
                "$(ru '\u0437\u0430\u043f\u0438\u0441\u044c \u044d\u043a\u0440\u0430\u043d\u0430, \u0432\u0441\u0435\u0433\u0434\u0430')"; do
      write "$(field_case "$label" "$text")"
      run "$LINT" "$F"
      [ "$status" -eq 1 ] || { echo "not named: $label: $text"; return 1; }
      [ "$output" = "ManualChecks.md: instrument: a screen recording in **$label:** (### MC-1.)" ] \
        || { printf 'label: %s\n got: %s\n' "$label" "$output"; return 1; }
    done
  done
}

@test "instrument: the Expected cell of a step is read for a recording too" {
  EXPECTED='The screen recording shows the quantity 2'
  write
  run "$LINT" "$F"
  [ "$status" -eq 1 ] || { echo "not named"; return 1; }
  [ "$output" = 'ManualChecks.md: instrument: a screen recording in a step (### MC-1., step 2)' ] || { echo "$output"; return 1; }
}

@test "instrument: a file with none of them is clean, and a screenshot of the failure is allowed" {
  write
  clean "$F"
  write "$(field_case 'Notes / attachments' 'a screenshot of the failure')"
  clean "$F"
  write "$(field_case 'Notes / attachments' "$(ru '\u0441\u043a\u0440\u0438\u043d\u0448\u043e\u0442 \u0441\u0431\u043e\u044f')")"
  clean "$F"
}

@test "scriptable: MC-2 of the field sample is named, next to its budget and its instrument section" {
  # The sample's thirteen command steps also overrun the case budget, as the original did, and it
  # keeps its commands in a ## Reading the verdict section, which the file a person walks no longer has.
  run "$LINT" "$FIX/scriptable.ru.md"
  [ "$status" -eq 1 ] || { echo "status $status: $output"; return 1; }
  [ "$output" = "$(printf '%s\n%s\n%s' \
    'ManualChecks.md: instrument: ## Reading the verdict in the file (## Reading the verdict)' \
    'ManualChecks.md: scriptable: no step needs a person, run it as a script (### MC-2.)' \
    'ManualChecks.md: budget: case of 41 lines, more than 40 (### MC-2.)')" ] || { echo "$output"; return 1; }
}

@test "scriptable: a menu command and a team are not shell commands" {
  # "Launch the app under the team captain's account", in Russian: the word for team is the word for command.
  write "$(steps_case '| 1 | Execute the Undo command from the Edit menu | — | The last item comes back | |' \
                      "| 2 | $(ru '\u0417\u0430\u043f\u0443\u0441\u0442\u0438\u0442\u0435 \u043f\u0440\u0438\u043b\u043e\u0436\u0435\u043d\u0438\u0435 \u043f\u043e\u0434 \u0443\u0447\u0451\u0442\u043d\u043e\u0439 \u0437\u0430\u043f\u0438\u0441\u044c\u044e \u043a\u0430\u043f\u0438\u0442\u0430\u043d\u0430 \u043a\u043e\u043c\u0430\u043d\u0434\u044b') | — | The cart shows the captain's name | |")"
  clean "$F"
}

@test "scriptable: a backticked screen label is not a command" {
  write "$(steps_case '| 1 | Execute `Settings` | — | The settings screen opens | |' \
                      '| 2 | Run `Checkout` | — | The payment screen opens | |')"
  clean "$F"
}

@test "scriptable: rewording a command step does not hide it" {
  write "$(steps_case '| 1 | Run `git status --short` and read the output | — | Prints nothing | |' \
                      '| 2 | Run the script `./check-tables.sh` | — | Prints PASS | |')"
  expect 'ManualChecks.md: scriptable: no step needs a person, run it as a script (### MC-1.)'
}

@test "case: under always, a ## Cases that says none with its reason is not an empty section" {
  write
  python3 - "$F" <<'PY'
import re, sys
p = sys.argv[1]; s = open(p).read()
s = re.sub(r'## Cases\n\n.*?(?=## On failure)', '## Cases\n\nnone — every check was covered by the automated pass.\n\n', s, flags=re.S)
open(p, 'w').write(s)
PY
  cut_refs
  clean "$F"
}
