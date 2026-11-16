#!/usr/bin/env bats
# A collective pass walks the cases of an epic's steps in one file. scripts/manual-checks-pass.sh is
# the part of it a script can do: collect the cases no earlier walk marked, read the marks of the
# pass file and of the agent verdicts, and write each mark back into the file of its step. Its
# fixture is an epic of three steps: 01 is brief, 02 is full, 03 has no ManualChecks.md.

setup() {
  ROOT="$(cd -- "$(dirname -- "$BATS_TEST_FILENAME")/../../.." && pwd)"
  PASS="$ROOT/scripts/manual-checks-pass.sh"
  LINT="$ROOT/scripts/lint-manual-checks.sh"
  EPIC="$BATS_TEST_TMPDIR/epic"
  cp -R "$ROOT/tests/fixtures/manual-checks-pass/epic" "$EPIC"
}

# jq-free reading of the JSON: python evaluates an expression over the parsed output.
js() { PYTHONIOENCODING=utf-8 python3 -c 'import json,sys; d=json.load(sys.stdin); print(json.dumps(eval(sys.argv[1]), sort_keys=True, ensure_ascii=False))' "$1"; }

@test "no arguments is a usage error, exit 2" {
  run "$PASS"
  [ "$status" -eq 2 ]
  [[ "$output" == *usage* ]]
}

@test "an unknown command is a usage error, exit 2" {
  run "$PASS" explode "$EPIC"
  [ "$status" -eq 2 ]
  [[ "$output" == *usage* ]]
}

@test "an epic that is no directory is a usage error, exit 2" {
  run "$PASS" collect "$EPIC/nowhere"
  [ "$status" -eq 2 ]
  [[ "$output" == *"not a directory"* ]]
}

@test "collect lists the open cases in the order of steps and ids" {
  run "$PASS" collect "$EPIC"
  [ "$status" -eq 0 ]
  ids=$(echo "$output" | js '[c["step"] + "/" + c["id"] for c in d["cases"]]')
  [ "$ids" = '["01/MC-1", "01/MC-2", "02/MC-1", "02/MC-2", "02/MC-3"]' ]
}

@test "collect names the step, its folder, the title and the style" {
  run "$PASS" collect "$EPIC"
  [ "$(echo "$output" | js 'd["cases"][0]["dir"]')" = '"01-cart.step"' ]
  [ "$(echo "$output" | js 'd["cases"][0]["style"]')" = '"brief"' ]
  [ "$(echo "$output" | js 'd["cases"][0]["title"]')" = '"The plus button raises the quantity and the total"' ]
  [ "$(echo "$output" | js 'd["cases"][2]["style"]')" = '"full"' ]
  [ "$(echo "$output" | js 'd["cases"][2]["dir"]')" = '"02-badge.step"' ]
}

@test "collect skips a case that already carries a mark, in brief and in full" {
  run "$PASS" collect "$EPIC"
  [ "$(echo "$output" | js '[c["title"] for c in d["cases"] if c["id"] == "MC-3" and c["step"] == "01"]')" = '[]' ]
  [ "$(echo "$output" | js '[c["title"] for c in d["cases"] if c["id"] == "MC-4"]')" = '[]' ]
}

@test "collect reads Runner, Device and Order, and null where a case has none" {
  run "$PASS" collect "$EPIC"
  [ "$(echo "$output" | js '[c["runner"] for c in d["cases"]]')" = '["agent", null, null, null, null]' ]
  [ "$(echo "$output" | js '[c["device"] for c in d["cases"]]')" = '[null, "real", null, "iPhone 12", null]' ]
  [ "$(echo "$output" | js '[c["order"] for c in d["cases"]]')" = '["first — the cart must be untouched since sign-in", null, "last — it signs the test account out at the end", null, null]' ]
}

@test "collect skips a step with no ManualChecks.md" {
  run "$PASS" collect "$EPIC"
  [ "$(echo "$output" | js '[c["step"] for c in d["cases"] if c["step"] == "03"]')" = '[]' ]
}

@test "collect reads a style line in any letter case and no line as full" {
  sed -i.bak 's/^\[STYLE\] = brief/[style] = BRIEF/' "$EPIC/01-cart.step/ManualChecks.md"
  run "$PASS" collect "$EPIC"
  [ "$(echo "$output" | js 'd["cases"][0]["style"]')" = '"brief"' ]
  sed -i.bak '/^\[style\]/d' "$EPIC/01-cart.step/ManualChecks.md"
  run "$PASS" collect "$EPIC"
  [ "$(echo "$output" | js 'd["cases"][0]["style"]')" = '"full"' ]
}

@test "a step folder without a hyphen is a step named by the folder" {
  mkdir "$EPIC/07.step"
  cp "$EPIC/01-cart.step/ManualChecks.md" "$EPIC/07.step/"
  run "$PASS" collect "$EPIC"
  [ "$(echo "$output" | js '[c["step"] for c in d["cases"] if c["dir"] == "07.step"][0]')" = '"07"' ]
}

@test "collect on a fully marked epic lists nothing" {
  "$PASS" writeback "$EPIC"
  run "$PASS" collect "$EPIC"
  [ "$status" -eq 0 ]
  [ "$(echo "$output" | js 'd["cases"]')" = '[]' ]
}

@test "marks reads all four kinds, the reasons and who set each" {
  run "$PASS" marks "$EPIC"
  [ "$status" -eq 0 ]
  [ "$(echo "$output" | js 'd["pass_file"]')" = 'true' ]
  [ "$(echo "$output" | js '[(m["case"], m["mark"], m["reason"], m["by"]) for m in d["marks"]]')" = \
'[["01/MC-1", "PASS", null, "agent"], ["01/MC-2", "FAIL", "the spinner stays on the screen", "person"], ["02/MC-1", "PASS", null, "person"], ["02/MC-2", "BLOCKED", "no real device at hand", "person"], ["02/MC-3", "DROPPED", "the limit was removed from the design", "person"]]' ]
  [ "$(echo "$output" | js 'd["unmarked"]')" = '[]' ]
}

@test "marks takes the reason of an agent verdict from its mark cell, else from its evidence" {
  python3 - "$EPIC/Validation.md" <<'PY'
import sys
p = sys.argv[1]
s = open(p).read().rstrip('\n')
s += '\n| 02/MC-1 | FAIL | The badge read 1 on the screenshot |\n| 02/MC-2 | BLOCKED (the camera is off) | no camera on the simulator |\n'
open(p, 'w').write(s)
PY
  sed -i.bak 's/ · 02\/MC-1 PASS · 02\/MC-2 BLOCKED (no real device at hand)/ · 02\/MC-1 __ · 02\/MC-2 __/' "$EPIC/ManualChecks.md"
  run "$PASS" marks "$EPIC"
  [ "$(echo "$output" | js '[(m["mark"], m["reason"], m["by"]) for m in d["marks"] if m["case"] == "02/MC-1"]')" = '[["FAIL", "The badge read 1 on the screenshot", "agent"]]' ]
  [ "$(echo "$output" | js '[(m["mark"], m["reason"], m["by"]) for m in d["marks"] if m["case"] == "02/MC-2"]')" = '[["BLOCKED", "the camera is off", "agent"]]' ]
}

@test "marks lists a case of the pass with no mark as unmarked" {
  sed -i.bak 's/ · 02\/MC-1 PASS/ · 02\/MC-1 __/' "$EPIC/ManualChecks.md"
  run "$PASS" marks "$EPIC"
  [ "$status" -eq 0 ]
  [ "$(echo "$output" | js 'd["unmarked"]')" = '["02/MC-1"]' ]
  [ "$(echo "$output" | js '[m["case"] for m in d["marks"] if m["case"] == "02/MC-1"]')" = '[]' ]
}

@test "marks lists a case whose __ has no agent verdict as unmarked" {
  sed -i.bak '/^| 01\/MC-1 | PASS/d' "$EPIC/Validation.md"
  run "$PASS" marks "$EPIC"
  [ "$(echo "$output" | js 'd["unmarked"]')" = '["01/MC-1"]' ]
}

@test "a person's mark wins over an agent verdict for the same case" {
  printf '| 02/MC-1 | FAIL | the badge read 1 |\n' >> "$EPIC/Validation.md"
  run "$PASS" marks "$EPIC"
  [ "$(echo "$output" | js '[(m["mark"], m["by"]) for m in d["marks"] if m["case"] == "02/MC-1"]')" = '[["PASS", "person"]]' ]
}

@test "marks without a Validation.md reads the pass file alone" {
  rm "$EPIC/Validation.md"
  run "$PASS" marks "$EPIC"
  [ "$status" -eq 0 ]
  [ "$(echo "$output" | js 'd["unmarked"]')" = '["01/MC-1"]' ]
}

@test "marks with neither a pass file nor agent verdicts is pass_file false and nothing else" {
  rm "$EPIC/ManualChecks.md" "$EPIC/Validation.md"
  run "$PASS" marks "$EPIC"
  [ "$status" -eq 0 ]
  [ "$(echo "$output" | js 'd')" = '{"marks": [], "pass_file": false, "unmarked": []}' ]
}

@test "marks without a pass file still reads the agent verdicts, and none is unmarked" {
  rm "$EPIC/ManualChecks.md"
  printf '%s\n' '| 02/MC-1 | FAIL | the badge read 1 on the screenshot |' >> "$EPIC/Validation.md"
  run "$PASS" marks "$EPIC"
  [ "$status" -eq 0 ]
  [ "$(echo "$output" | js 'd["pass_file"]')" = 'false' ]
  [ "$(echo "$output" | js '[(m["case"], m["mark"], m["reason"], m["by"]) for m in d["marks"]]')" = \
'[["01/MC-1", "PASS", null, "agent"], ["02/MC-1", "FAIL", "the badge read 1 on the screenshot", "agent"]]' ]
  [ "$(echo "$output" | js 'd["unmarked"]')" = '[]' ]
}

@test "writeback without a pass file writes the agent verdicts, once" {
  rm "$EPIC/ManualChecks.md"
  printf '%s\n' '| 02/MC-1 | FAIL | the badge read 1 on the screenshot |' >> "$EPIC/Validation.md"
  run "$PASS" writeback "$EPIC"
  [ "$status" -eq 0 ]
  [ "$output" = "writeback: 2 mark(s) in 2 file(s)" ]
  grep -q '^\*\*Result:\*\* MC-1 PASS · MC-2 __' "$EPIC/01-cart.step/ManualChecks.md"
  grep -q '^\*\*Status:\*\* FAIL — reason: the badge read 1 on the screenshot$' "$EPIC/02-badge.step/ManualChecks.md"
  cp -R "$EPIC" "$BATS_TEST_TMPDIR/after-first"
  run "$PASS" writeback "$EPIC"
  [ "$status" -eq 0 ]
  [ "$output" = "writeback: 0 mark(s) in 0 file(s)" ]
  diff -r "$EPIC" "$BATS_TEST_TMPDIR/after-first"
}

@test "marks reads a reason that holds a parenthesis and a dash" {
  python3 - "$EPIC/ManualChecks.md" <<'PY2'
import sys
p = sys.argv[1]
s = open(p, encoding='utf-8').read()
s = s.replace('FAIL (the spinner stays on the screen)', 'FAIL (the spinner (twice) stays \u2014 on the screen)')
open(p, 'w', encoding='utf-8').write(s)
PY2
  run "$PASS" marks "$EPIC"
  [ "$(echo "$output" | js '[m["reason"] for m in d["marks"] if m["case"] == "01/MC-2"][0]')" = '"the spinner (twice) stays — on the screen"' ]
}

@test "marks takes no mark from the prose after the trailing dash" {
  run "$PASS" marks "$EPIC"
  [ "$(echo "$output" | js 'len(d["marks"])')" = '5' ]
}

@test "writeback puts each mark into the file of its step" {
  run "$PASS" writeback "$EPIC"
  [ "$status" -eq 0 ]
  [ "$output" = "writeback: 5 mark(s) in 2 file(s)" ]
  grep -q '^\*\*Result:\*\* MC-1 PASS · MC-2 FAIL (the spinner stays on the screen) · MC-3 PASS — PASS, FAIL or BLOCKED each; after a FAIL or a BLOCKED, why$' "$EPIC/01-cart.step/ManualChecks.md"
  grep -q '^\*\*Status:\*\* PASS — reason: —$' "$EPIC/02-badge.step/ManualChecks.md"
  grep -q '^\*\*Status:\*\* BLOCKED — reason: no real device at hand$' "$EPIC/02-badge.step/ManualChecks.md"
  grep -q '^\*\*Status:\*\* DROPPED — reason: the limit was removed from the design$' "$EPIC/02-badge.step/ManualChecks.md"
}

@test "writeback fills the status of the case named, not of its neighbours" {
  "$PASS" writeback "$EPIC"
  python3 - "$EPIC/02-badge.step/ManualChecks.md" <<'PY2'
import re, sys
text = open(sys.argv[1], encoding='utf-8').read()
cases = re.split(r'^### MC-', text, flags=re.M)[1:]
status = {c.split('.', 1)[0]: re.search(r'^\*\*Status:\*\*.*$', c, re.M).group() for c in cases}
assert status['1'] == '**Status:** PASS \u2014 reason: \u2014', status
assert status['2'] == '**Status:** BLOCKED \u2014 reason: no real device at hand', status
assert status['3'] == '**Status:** DROPPED \u2014 reason: the limit was removed from the design', status
assert status['4'] == '**Status:** FAIL \u2014 reason: the badge was gone', status
PY2
}

@test "the pass file of the fixture is a pass file the lint accepts" {
  grep -qxF '[PASS] = 01, 02' "$EPIC/ManualChecks.md"
  run "$LINT" "$EPIC/ManualChecks.md"
  [ "$status" -eq 0 ] || { echo "$output"; return 1; }
}

@test "both step files still pass lint-manual-checks after writeback" {
  "$LINT" "$EPIC/01-cart.step/ManualChecks.md"
  "$LINT" "$EPIC/02-badge.step/ManualChecks.md"
  "$PASS" writeback "$EPIC"
  run "$LINT" "$EPIC/01-cart.step/ManualChecks.md"
  [ "$status" -eq 0 ]
  run "$LINT" "$EPIC/02-badge.step/ManualChecks.md"
  [ "$status" -eq 0 ]
}

@test "a second writeback changes nothing and says 0 mark(s)" {
  "$PASS" writeback "$EPIC"
  cp -R "$EPIC" "$BATS_TEST_TMPDIR/after-first"
  run "$PASS" writeback "$EPIC"
  [ "$status" -eq 0 ]
  [ "$output" = "writeback: 0 mark(s) in 0 file(s)" ]
  diff -r "$EPIC" "$BATS_TEST_TMPDIR/after-first"
}

@test "writeback with an unmarked case exits 1 and leaves every step file as it was" {
  sed -i.bak 's/ · 02\/MC-1 PASS/ · 02\/MC-1 __/' "$EPIC/ManualChecks.md"
  cp -R "$EPIC" "$BATS_TEST_TMPDIR/before"
  run "$PASS" writeback "$EPIC"
  [ "$status" -eq 1 ]
  [[ "$output" == *"writeback: unmarked: 02/MC-1"* ]]
  diff -r "$EPIC" "$BATS_TEST_TMPDIR/before"
}

@test "writeback names every unmarked case, comma separated" {
  sed -i.bak -e 's/ · 02\/MC-1 PASS/ · 02\/MC-1 __/' -e 's/ · 02\/MC-3 DROPPED ([^)]*)/ · 02\/MC-3 __/' "$EPIC/ManualChecks.md"
  run "$PASS" writeback "$EPIC"
  [ "$status" -eq 1 ]
  [[ "$output" == *"writeback: unmarked: 02/MC-1, 02/MC-3"* ]]
}

@test "writeback keeps the lines of a step file that carry no mark" {
  cp "$EPIC/01-cart.step/ManualChecks.md" "$BATS_TEST_TMPDIR/01.before"
  "$PASS" writeback "$EPIC"
  run diff "$BATS_TEST_TMPDIR/01.before" "$EPIC/01-cart.step/ManualChecks.md"
  [ "$status" -eq 1 ]
  [ "$(echo "$output" | grep -c '^[<>]')" -eq 2 ]
}

@test "writeback with neither a pass file nor agent verdicts writes nothing and exits 0" {
  rm "$EPIC/ManualChecks.md" "$EPIC/Validation.md"
  run "$PASS" writeback "$EPIC"
  [ "$status" -eq 0 ]
  [ "$output" = "writeback: 0 mark(s) in 0 file(s)" ]
}

@test "writeback of a mark whose case is in no step file exits 1 and writes nothing" {
  sed -i.bak 's/ · 02\/MC-3 DROPPED/ · 09\/MC-1 PASS · 02\/MC-3 DROPPED/' "$EPIC/ManualChecks.md"
  cp -R "$EPIC" "$BATS_TEST_TMPDIR/before"
  run "$PASS" writeback "$EPIC"
  [ "$status" -eq 1 ]
  [[ "$output" == *"writeback: no place for: 09/MC-1"* ]]
  diff -r "$EPIC" "$BATS_TEST_TMPDIR/before"
}

# The cases below hand the pass a verdict of the agent for a case the Result line leaves at "__".
agent_verdict() { # $1 case, $2 mark cell, $3 evidence
  sed -i.bak "s# · $1 FAIL ([^)]*)# · $1 __#" "$EPIC/ManualChecks.md"
  printf '| %s | %s | %s |\n' "$1" "$2" "$3" >> "$EPIC/Validation.md"
}

@test "a reason with an unbalanced parenthesis is written with square brackets and reads back whole" {
  agent_verdict 01/MC-2 FAIL 'step 1) did not finish'
  run "$PASS" writeback "$EPIC"
  [ "$status" -eq 0 ]
  grep -q '^\*\*Result:\*\* MC-1 PASS · MC-2 FAIL (step 1\] did not finish) · MC-3 PASS — ' "$EPIC/01-cart.step/ManualChecks.md"
  run "$PASS" collect "$EPIC"
  [ "$(echo "$output" | js '[c["step"] + "/" + c["id"] for c in d["cases"]]')" = '[]' ]
  cp -R "$EPIC" "$BATS_TEST_TMPDIR/after-first"
  run "$PASS" writeback "$EPIC"
  [ "$output" = "writeback: 0 mark(s) in 0 file(s)" ]
  diff -r "$EPIC" "$BATS_TEST_TMPDIR/after-first"
}

@test "an opening parenthesis in a reason is normalised too, and the full status carries the same text" {
  agent_verdict 01/MC-2 FAIL '(step 1 did not finish'
  python3 - "$EPIC/ManualChecks.md" <<'PY2'
import sys
p = sys.argv[1]
s = open(p, encoding='utf-8').read().replace('02/MC-2 BLOCKED (no real device at hand)', '02/MC-2 BLOCKED (no real device (an iPhone) at hand)')
open(p, 'w', encoding='utf-8').write(s)
PY2
  run "$PASS" writeback "$EPIC"
  [ "$status" -eq 0 ]
  grep -q 'MC-2 FAIL (\[step 1 did not finish) · MC-3 PASS' "$EPIC/01-cart.step/ManualChecks.md"
  grep -q '^\*\*Status:\*\* BLOCKED — reason: no real device \[an iPhone\] at hand$' "$EPIC/02-badge.step/ManualChecks.md"
}

@test "an agent FAIL, BLOCKED and DROPPED are written back with their Evidence as the reason" {
  python3 - "$EPIC/ManualChecks.md" <<'PY2'
import sys
p = sys.argv[1]
s = open(p, encoding='utf-8').read()
s = s.replace('01/MC-2 FAIL (the spinner stays on the screen)', '01/MC-2 __')
s = s.replace('02/MC-2 BLOCKED (no real device at hand)', '02/MC-2 __')
s = s.replace('02/MC-3 DROPPED (the limit was removed from the design)', '02/MC-3 __')
open(p, 'w', encoding='utf-8').write(s)
PY2
  printf '%s\n' '| 01/MC-2 | FAIL | the spinner stayed on the screen |' \
    '| 02/MC-2 | BLOCKED | no camera on the simulator |' \
    '| 02/MC-3 | DROPPED | the limit is gone from the design |' >> "$EPIC/Validation.md"
  run "$PASS" writeback "$EPIC"
  [ "$status" -eq 0 ]
  [ "$output" = "writeback: 5 mark(s) in 2 file(s)" ]
  grep -q 'MC-2 FAIL (the spinner stayed on the screen) · MC-3 PASS' "$EPIC/01-cart.step/ManualChecks.md"
  grep -q '^\*\*Status:\*\* BLOCKED — reason: no camera on the simulator$' "$EPIC/02-badge.step/ManualChecks.md"
  grep -q '^\*\*Status:\*\* DROPPED — reason: the limit is gone from the design$' "$EPIC/02-badge.step/ManualChecks.md"
  run "$PASS" marks "$EPIC"
  [ "$(echo "$output" | js '[(m["case"], m["mark"], m["by"]) for m in d["marks"] if m["by"] == "agent"]')" = \
'[["01/MC-1", "PASS", "agent"], ["01/MC-2", "FAIL", "agent"], ["02/MC-2", "BLOCKED", "agent"], ["02/MC-3", "DROPPED", "agent"]]' ]
  run "$PASS" writeback "$EPIC"
  [ "$output" = "writeback: 0 mark(s) in 0 file(s)" ]
}

@test "a FAIL with no reason round-trips in a brief step and in a full step" {
  python3 - "$EPIC/ManualChecks.md" <<'PY2'
import sys
p = sys.argv[1]
s = open(p, encoding='utf-8').read()
s = s.replace('01/MC-2 FAIL (the spinner stays on the screen)', '01/MC-2 FAIL')
s = s.replace('02/MC-2 BLOCKED (no real device at hand)', '02/MC-2 FAIL')
open(p, 'w', encoding='utf-8').write(s)
PY2
  run "$PASS" marks "$EPIC"
  [ "$(echo "$output" | js '[m["reason"] for m in d["marks"] if m["mark"] == "FAIL"]')" = '[null, null]' ]
  run "$PASS" writeback "$EPIC"
  [ "$status" -eq 0 ]
  grep -q '^\*\*Result:\*\* MC-1 PASS · MC-2 FAIL · MC-3 PASS — ' "$EPIC/01-cart.step/ManualChecks.md"
  grep -q '^\*\*Status:\*\* FAIL — reason: —$' "$EPIC/02-badge.step/ManualChecks.md"
  run "$PASS" collect "$EPIC"
  [ "$(echo "$output" | js 'd["cases"]')" = '[]' ]
  run "$PASS" marks "$EPIC"
  [ "$(echo "$output" | js '[m["reason"] for m in d["marks"] if m["mark"] == "FAIL"]')" = '[null, null]' ]
  run "$PASS" writeback "$EPIC"
  [ "$output" = "writeback: 0 mark(s) in 0 file(s)" ]
}

# Two step folders that share a prefix: address-form.step and address-list.step are both "address".
colliding_epic() {
  CE="$BATS_TEST_TMPDIR/colliding"
  mkdir -p "$CE/address-form.step" "$CE/address-list.step" "$CE/03-plain.step"
  local d
  for d in address-form address-list 03-plain; do
    printf '# Manual Checks\n\n[STYLE] = brief\n\n## Cases\n\n### MC-1. A case of %s\n\n**What it checks:** x\n\n**Start:** S1.\n\n1. Tap\n   → Shows\n\n**Failure looks like:** y\n\n**Result:** MC-1 __\n' "$d" > "$CE/$d.step/ManualChecks.md"
  done
  printf '# Manual Checks\n\n[STYLE] = brief\n\n[PASS] = address-form, address-list, 03\n\n## Cases\n\n### Session 1. Simulator\n\n#### address-form/MC-1. A\n\n#### address-list/MC-1. B\n\n#### 03/MC-1. C\n\n**Result:** address-form/MC-1 PASS · address-list/MC-1 FAIL (broken) · 03/MC-1 PASS\n' > "$CE/ManualChecks.md"
}

@test "step folders that share a prefix take their full stem as the id, the others keep the prefix" {
  colliding_epic
  run "$PASS" collect "$CE"
  [ "$status" -eq 0 ]
  [ "$(echo "$output" | js '[c["step"] + "/" + c["id"] for c in d["cases"]]')" = '["03/MC-1", "address-form/MC-1", "address-list/MC-1"]' ]
}

@test "writeback of colliding step ids writes each mark into its own folder, and a second run writes nothing" {
  colliding_epic
  run "$PASS" writeback "$CE"
  [ "$status" -eq 0 ]
  [ "$output" = "writeback: 3 mark(s) in 3 file(s)" ]
  grep -q 'MC-1 PASS' "$CE/address-form.step/ManualChecks.md"
  grep -q 'MC-1 FAIL (broken)' "$CE/address-list.step/ManualChecks.md"
  grep -q 'MC-1 PASS' "$CE/03-plain.step/ManualChecks.md"
  run "$PASS" writeback "$CE"
  [ "$output" = "writeback: 0 mark(s) in 0 file(s)" ]
}

@test "marks reads the full-stem ids of colliding steps" {
  colliding_epic
  run "$PASS" marks "$CE"
  [ "$(echo "$output" | js '[m["case"] for m in d["marks"]]')" = '["03/MC-1", "address-form/MC-1", "address-list/MC-1"]' ]
  [ "$(echo "$output" | js 'd["unmarked"]')" = '[]' ]
}
