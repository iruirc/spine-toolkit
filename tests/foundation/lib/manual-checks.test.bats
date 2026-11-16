#!/usr/bin/env bats
# ManualChecks.md is the one artifact of a task a person executes rather than reads.
# A vague sentence in a walkthrough costs a re-read; a vague step here cannot be run at
# all. This suite holds the parts of that spec a reviewer cannot see: that both halves
# of the two-stage contract reached both execution forms of all five profiles.

setup() {
  ROOT="$(cd -- "$(dirname -- "$BATS_TEST_FILENAME")/../../.." && pwd)"
  SKILL="$ROOT/skills/manual-checks/SKILL.md"
  PROFILES="feature bug refactor test quick"
}

@test "the skill exists and resolves under its own name" {
  [ -f "$SKILL" ] || { echo "no skills/manual-checks/SKILL.md"; return 1; }
  grep -q '^name: manual-checks$' "$SKILL" || { echo "frontmatter name is not manual-checks"; return 1; }
}

@test "the skill carries every required field of a case" {
  for field in '**Priority:**' '**Traces to:**' '**What it checks:**' '**Preconditions:**' '**Test data:**' '**Steps:**' \
               '**Expected result:**' '**Failure looks like:**' '**Cleanup:**' '**Status:**' '**Notes / attachments:**'; do
    grep -qF "$field" "$SKILL" || { echo "the skill never names the field $field"; return 1; }
  done
  # Code references left the case for one section at the end of the file.
  grep -qF '## Code references' "$SKILL" || { echo "the skill never names ## Code references"; return 1; }
  grep -qF '### MC-<n>.' "$SKILL" || { echo "the case heading is not ### MC-<n>."; return 1; }
  grep -qxF '| # | Action | Data | Expected | Actual |' "$SKILL" || { echo "the skill has no steps header"; return 1; }
  # The instrument left the file a person walks: it is no field of a case, and no section of the file.
  case_tpl="$(awk '/^### MC-1\. /{f=1} f&&/^```$/{exit} f' "$SKILL")"
  [ -n "$case_tpl" ] || { echo "no case template in the skill"; return 1; }
  ! grep -qF 'By instrument' <<<"$case_tpl" || { echo "the case template still carries the instrument field"; return 1; }
}

@test "the instrument is not part of the file: a measurement goes to Validation.md or to ## Not covered" {
  s="$(skill_section '## No instrument in the file')"
  [ -n "$s" ] || { echo "no ## No instrument in the file"; return 1; }
  for token in '`Validation.md`' '`## Not covered`' 'no instrument'; do
    grep -qF -- "$token" <<<"$s" || { echo "## No instrument in the file does not name $token"; return 1; }
  done
  ! grep -q '^## The instrument rule$' "$SKILL" || { echo "the instrument rule is still there"; return 1; }
  ! grep -qF 'Reading the verdict' "$SKILL" || { echo "the skill still names ## Reading the verdict"; return 1; }
  ! grep -qF '**By instrument:**' "$SKILL" || { echo "the skill still names **By instrument:**"; return 1; }
  grep -qF 'no field, section or step of a case asks the person to record the screen' <<<"$s" \
    || { echo "## No instrument in the file lets a case ask for a recording"; return 1; }
}

@test "no case asks the tester for a screen recording; a screenshot of a failure is all that is attached" {
  # Only the rule that forbids a recording may name one: the lint row and ## No instrument in the file.
  hits="$(grep -iE 'record the screen|a recording|screen recording|start recording' "$SKILL" | grep -vF -e '`instrument` |' -e 'asks the person to record the screen' || true)"
  [ -z "$hits" ] || { echo "the skill still has the tester record the screen: $hits"; return 1; }
  ! grep -qF 'a developer checks it' "$SKILL" || { echo "a value that needs a tool still goes to the tester's attachments"; return 1; }
  grep -qF 'a screenshot of what failed' "$SKILL" || { echo "**Notes / attachments:** is not a screenshot of what failed"; return 1; }
  r="$(skill_section '## The reader')"
  ! grep -qiE 'record' <<<"$r" || { echo "## The reader still has the tester record the screen"; return 1; }
  for f in "$ROOT"/skills/manual-checks/examples/manual-checks.*.md "$ROOT"/tests/fixtures/manual-checks/good.*.md; do
    ! grep -qiE 'screen recording' "$f" || { echo "$f asks for a screen recording"; return 1; }
    ! grep -qF "$(ru '\u0437\u0430\u043f\u0438\u0441\u044c \u044d\u043a\u0440\u0430\u043d\u0430')" "$f" || { echo "$f asks for a screen recording"; return 1; }
  done
}

@test "the reader is a tester who knows the product but not the code" {
  r="$(skill_section '## The reader')"
  [ -n "$r" ] || { echo "no ## The reader"; return 1; }
  for token in 'a tester who knows the product but not the code' 'only words from the screen' '`## Code references`' '`artifact-reader`'; do
    grep -qF -- "$token" <<<"$r" || { echo "## The reader does not name $token"; return 1; }
  done
  ! grep -qiE 'month later|codebase' <<<"$r" || { echo "## The reader is still the author a month later"; return 1; }
  ! grep -qF 'its author, a month later' "$SKILL" || { echo "the old reader is back"; return 1; }
}

@test "the old case format is gone from the skill" {
  for old in '**Scene:**' '**By eye:**' '**Wrap-up:**' '| # | Action | Data | You see |' '`You see`' '### N.'; do
    ! grep -qF -- "$old" "$SKILL" || { echo "the skill still names $old"; return 1; }
  done
}

@test "a step holds one action, starts from no other case, and copies the app's text" {
  r="$(skill_section '## Step rules')"
  [ -n "$r" ] || { echo "no ## Step rules"; return 1; }
  for token in '**One row, one action.**' '**No "repeat steps".**' '**Cases are independent.**' 'state after case N' \
               '**Visible text is copied from the app verbatim.**' 'One language per file'; do
    grep -qF -- "$token" <<<"$r" || { echo "## Step rules does not name $token"; return 1; }
  done
}

@test "the skill says how its lint counts and where it is wrong" {
  l="$(skill_section '## The lint')"
  [ -n "$l" ] || { echo "no ## The lint"; return 1; }
  for id in case steps compound code codeslot chain file; do
    grep -qF -- "| \`$id\` |" <<<"$l" || { echo "## The lint does not list the check $id"; return 1; }
  done
  for token in '`scripts/lint-manual-checks.sh`' '`YouTube`' '`shop.example.com`' 'no allow-list' 'runs it again'; do
    grep -qF -- "$token" <<<"$l" || { echo "## The lint does not say $token"; return 1; }
  done
  # No line budget, in either style: the lint counts no lines, and the skill says how none.
  for token in '| `budget` |' 'How the budget counts' 'blank lines inside it count' 'about 30 lines' 'about twelve steps'; do
    ! grep -qF -- "$token" <<<"$l" || { echo "## The lint still says $token"; return 1; }
  done
}

@test "the scale convention gives ManualChecks.md no numeric limit, in either style" {
  C="$ROOT/conventions/task-scale.md"
  ! grep -qF '40 lines' "$C" || { echo "the convention still holds a case to 40 lines"; return 1; }
  ! grep -qF '`scripts/lint-manual-checks.sh` holds' "$C" || { echo "the convention still says the lint counts a case"; return 1; }
  tr '\n' ' ' <"$C" | grep -qF '`ManualChecks.md` carries no numeric limit at all, in either style' \
    || { echo "the convention does not say ManualChecks.md has no numeric limit"; return 1; }
  tr '\n' ' ' <"$C" | grep -qF "like the Walkthrough's section per commit at \`deep\`" \
    || { echo "the convention does not compare it with the Walkthrough's section at deep"; return 1; }
  ! grep -qF 'A per-unit budget is not something a line count can decide' "$C" \
    || { echo "the convention still says no count can decide a case's size"; return 1; }
}

@test "a Preparation sub-heading is structure: Screen map and Latin scene ids in every language" {
  grep -qF '`### Screen map` and the scene ids `P0`…`Pn` are written in Latin letters in every language' "$SKILL" \
    || { echo "the Language paragraph does not keep the Preparation sub-headings English"; return 1; }
  for f in "$ROOT/skills/manual-checks/examples/manual-checks.ru.md" "$ROOT/tests/fixtures/manual-checks/good.ru.md"; do
    grep -qx '### Screen map' "$f" || { echo "$f: the screen map heading is translated"; return 1; }
    # A Cyrillic letter Pe before a scene number looks like the Latin P and is not it.
    ! grep -q "$(printf '\xd0\x9f')[0-9]" "$f" || { echo "$f: a scene id written with a Cyrillic letter"; return 1; }
    grep -q '^### P0\. ' "$f" || { echo "$f: no Latin scene P0"; return 1; }
  done
}

@test "the skill carries the symbol rule that decides whether a case is executable" {
  grep -q '^## The symbol rule$' "$SKILL" || { echo "no symbol rule"; return 1; }
}

@test "the skill states both halves of the two-stage contract" {
  grep -q '## Manual acceptance' "$SKILL" || { echo "the skill never names the plan-side section"; return 1; }
  grep -q 'ManualChecks.md' "$SKILL" || { echo "the skill never names the artifact"; return 1; }
}

@test "the skill names the shared sections that keep a case from repeating its neighbours" {
  for section in '## Preparation' '## Troubleshooting'; do
    grep -qF "$section" "$SKILL" || { echo "the skill never names $section"; return 1; }
  done
  grep -qi 'conditional' "$SKILL" \
    || { echo "the shared sections are not marked conditional, so a two-case task gets both"; return 1; }
}

@test "the skill states the floor that survives lite" {
  grep -q '^## Depth by task scale$' "$SKILL" || { echo "the skill says nothing about scale"; return 1; }
  grep -qi 'cuts no required field' "$SKILL" || { echo "lite is not held off the required fields"; return 1; }
}

@test "the skill ships no locales, like the other agent-facing skills" {
  # ops-checklist and task-walkthrough have none either: nothing here is user-facing,
  # and a locales/ directory would put this skill under lint-locales parity for no reader.
  [ ! -d "$ROOT/skills/manual-checks/locales" ] || { echo "manual-checks must not carry locales/"; return 1; }
}

# A Russian string as \uXXXX escapes: no Cyrillic outside *.ru.md.
ru() { python3 -c 'import sys; sys.stdout.write(sys.argv[1].encode().decode("unicode_escape"))' "$1"; }

# The Plan brief of a profile script runs from its own banner to the next stage's.
# Grepping the whole file would pass on a mention in the Validation brief, which is
# the one place this clause must NOT be, since by then the plan is already written.
# QUICK has no Plan stage: its Edit brief writes the plan.
plan_brief() {
  awk '/^\/\/ ── (Plan|Edit) ─/{p=1;next} p&&/^\/\/ ── /{exit} p' "$1"
}
plan_stage() { [ "$1" = quick ] && echo Edit || echo Plan; }

# A stage's own bullet in a Method B skill, from its "- **Stage**" line to the next
# bullet. Whole-file greps do not work here: by Task 3 the Validation bullet quotes the
# plan-side section name, and every one of these tests would pass before its own edit.
bullet() { # $1 = SKILL.md, $2 = stage name
  awk -v s="- **$2**" 'index($0,s)==1{p=1;print;next} p&&/^- \*\*/{exit} p' "$1"
}

@test "every profile asks its Plan stage for the manual-acceptance list" {
  for p in $PROFILES; do
    plan_brief "$ROOT/workflows/profile-$p.js" | grep -q '## Manual acceptance' \
      || { echo "profile-$p.js: the Plan brief never asks for ## Manual acceptance"; return 1; }
  done
}

@test "the Plan brief offers the escape line for a fully automatable task" {
  for p in $PROFILES; do
    plan_brief "$ROOT/workflows/profile-$p.js" | grep -q 'Fully automatable' \
      || { echo "profile-$p.js: no escape line, so an empty list has no legal form"; return 1; }
  done
}

@test "the same requirement reached the Method B skill of every profile" {
  for p in $PROFILES; do
    bullet "$ROOT/skills/workflow-$p/SKILL.md" "$(plan_stage "$p")" | grep -q '## Manual acceptance' \
      || { echo "workflow-$p/SKILL.md: the Plan stage says nothing about ## Manual acceptance"; return 1; }
  done
}

@test "BUG says where the replay comes from instead of listing it twice" {
  # Both greps target the inserted sentence itself. A bare 'Reproduce.md' matches
  # two lines the bug Plan brief already carried, and a bare 'replay' matches three
  # in workflow-bug/SKILL.md — either one passes before the edit it exists to check.
  plan_brief "$ROOT/workflows/profile-bug.js" | grep -q 'reproduction replay is not' \
    || { echo "profile-bug.js: the Plan brief does not exempt the replay"; return 1; }
  bullet "$ROOT/skills/workflow-bug/SKILL.md" Plan | grep -q 'reproduction replay is not' \
    || { echo "workflow-bug/SKILL.md: the replay exemption did not reach the Plan bullet"; return 1; }
}

@test "exactly the five profiles with a Validation stage carry the clause" {
  # Vacuity guard: without it the loops above iterate over a list someone shortened. It counts the
  # Plan clause itself: EPIC's Done brief names a ## Manual acceptance section of Done.md too.
  n="$(grep -l 'add a ## Manual acceptance section' "$ROOT"/workflows/profile-*.js | wc -l | tr -d ' ')"
  [ "$n" -eq 5 ] || { echo "$n profile script(s) carry the clause, expected 5"; return 1; }
}

# The Validation stage's brief TEXT only — from its banner to the agent() options
# object that follows it. Stopping at the next stage banner would also capture the
# post-agent code, and every profile's `result.notes.push(...)` there carries the
# literal ManualChecks.md — which makes any grep for the artifact name inside this
# range incapable of failing. The stop pattern spells the quotes as `.` so the awk
# program can stay single-quoted.
validation_brief() {
  awk -v stop="label: .validation." '/^\/\/ ── Validation ─/{p=1;next} p&&$0~stop{exit} p' "$1"
}

@test "every Validation brief points at the skill instead of describing the file" {
  for p in $PROFILES; do
    validation_brief "$ROOT/workflows/profile-$p.js" | grep -q 'manual-checks skill' \
      || { echo "profile-$p.js: the Validation brief never names the manual-checks skill"; return 1; }
  done
}

@test "the Validation brief still names the artifact it produces" {
  # A preservation guard, not a gate on this task: every Validation brief already
  # named the artifact before this plan touched it, so this passes at RED by design.
  # What it buys is that a later rewording of the brief cannot drop the name silently.
  for p in $PROFILES; do
    validation_brief "$ROOT/workflows/profile-$p.js" | grep -q 'ManualChecks.md' \
      || { echo "profile-$p.js: the artifact fell out of the Validation brief"; return 1; }
  done
}

@test "the pointer reached the Method B skill of every profile" {
  for p in $PROFILES; do
    bullet "$ROOT/skills/workflow-$p/SKILL.md" Validation | grep -q 'manual-checks' \
      || { echo "workflow-$p/SKILL.md: the Validation stage has no pointer at the skill"; return 1; }
  done
}

@test "the platform how-to says the artifact's form belongs to core" {
  grep -q 'manual-checks' "$ROOT/docs/building-a-platform.md" \
    || { echo "a platform author is never told the form is not theirs to invent"; return 1; }
}

@test "the configuration page points at the skill for what goes inside" {
  # The guidance left the template when the settings became one-line fields; the reference page is
  # where it lands, and this assertion goes live with it.
  doc="$ROOT/docs/configuration.md"
  grep -q 'manual-checks' "$doc" \
    || { echo "the manual_checks field documents when, and nothing documents what"; return 1; }
}

# The Review stage's brief TEXT only, stopping at the agent() options object the
# same way validation_brief() does. Nothing in the post-agent code names the
# artifact today, so a banner-to-banner range would pass — but by accident, and
# the accident ends the day Review starts reporting manual checks.
review_brief() {
  awk -v stop="label: .review." '/^\/\/ ── Review ─/{p=1;next} p&&$0~stop{exit} p' "$1"
}

@test "every Review brief reads the hand-run script when there is one" {
  for p in $PROFILES; do
    review_brief "$ROOT/workflows/profile-$p.js" | grep -q 'ManualChecks.md' \
      || { echo "profile-$p.js: Review never opens ManualChecks.md"; return 1; }
  done
}

@test "Review is told what makes a case a finding, not just to look at it" {
  for p in $PROFILES; do
    review_brief "$ROOT/workflows/profile-$p.js" | grep -q 'manual-checks' \
      || { echo "profile-$p.js: Review has no rule to judge a case by"; return 1; }
  done
}

@test "the Review requirement reached Method B" {
  for p in $PROFILES; do
    bullet "$ROOT/skills/workflow-$p/SKILL.md" Review | grep -q 'ManualChecks.md' \
      || { echo "workflow-$p/SKILL.md: the Review stage says nothing about the artifact"; return 1; }
  done
}

@test "the Validation and Review clauses reached every profile with a Validation stage" {
  # The Plan clause has a count guard; without the same for these two, shortening
  # PROFILES and stripping one profile's Validation pointer and Review clause
  # leaves the whole suite green.
  # The shared prelude names the skill in every script, so only the Validation brief counts.
  v=0
  for f in "$ROOT"/workflows/profile-*.js; do
    if validation_brief "$f" | grep -q 'manual-checks skill'; then v=$((v + 1)); fi
  done
  [ "$v" -eq 5 ] || { echo "$v profile script(s) point Validation at the skill, expected 5"; return 1; }
  r="$(grep -l 'ManualChecks.md exists, read it too' "$ROOT"/workflows/profile-*.js | wc -l | tr -d ' ')"
  [ "$r" -eq 5 ] || { echo "$r profile script(s) carry the Review clause, expected 5"; return 1; }
}

@test "Review checks the plan's half of the contract, not only the artifact" {
  # The artifact clause fires only when the artifact exists, and manual_checks: auto
  # may never write one — so without this, a plan that quietly skipped the section
  # is caught by nobody.
  for p in $PROFILES; do
    review_brief "$ROOT/workflows/profile-$p.js" | grep -q '## Manual acceptance' \
      || { echo "profile-$p.js: Review never looks for the plan's ## Manual acceptance"; return 1; }
    bullet "$ROOT/skills/workflow-$p/SKILL.md" Review | grep -q '## Manual acceptance' \
      || { echo "workflow-$p/SKILL.md: the plan-side check did not reach Method B"; return 1; }
  done
}

# One section of the skill, heading excluded, up to the next H2.
skill_section() { awk -v h="$1" '$0==h{f=1;next} f&&/^## /{exit} f' "$SKILL"; }

@test "no line budget in the skill: no Budget column, no 40 lines, and lite still keeps the case whole" {
  grep -qxF '| Section | Content |' "$SKILL" || { echo "the ## Structure table is not headed | Section | Content |"; return 1; }
  for token in '| Budget |' '40 lines' '≤ 8 lines' '≤ 60 lines' 'How the budget counts'; do
    ! grep -qF -- "$token" "$SKILL" || { echo "the skill still says $token"; return 1; }
  done
  skill_section '## Depth by task scale' | grep -qF 'cuts no required field of a case' \
    || { echo "lite is not held off the required fields of a case"; return 1; }
}

@test "Preparation maps the screen and its words, marks dev-only steps, and the file has its frame" {
  for token in 'screen map' '| Word in the cases | What it is on the screen |' '**dev-only:**' 'BLOCKED' '| `## Charter` |' \
               '## Run record' '## On failure — bug report' '[COVERS]'; do
    grep -qF -- "$token" "$SKILL" || { echo "the skill never names $token"; return 1; }
  done
}

# The worked examples: whole files the lint accepts, written for the neutral shopping cart.
@test "two worked examples pass the lint and show every device of the format" {
  grep -qF 'examples/manual-checks.en.md' "$SKILL" && grep -qF 'examples/manual-checks.ru.md' "$SKILL" \
    || { echo "the skill does not point the writer at its examples"; return 1; }
  for lang in en ru; do
    ex="$ROOT/skills/manual-checks/examples/manual-checks.$lang.md"
    [ -f "$ex" ] || { echo "no example $ex"; return 1; }
    run "$ROOT/scripts/lint-manual-checks.sh" "$ex"
    [ "$status" -eq 0 ] || { echo "manual-checks.$lang.md fails the lint:"; echo "$output"; return 1; }
    prep="$(awk '$0=="## Preparation"{f=1;next} f&&/^## /{exit} f' "$ex")"
    [ "$(grep -c '^```' <<<"$prep")" -ge 2 ] || { echo "manual-checks.$lang.md: ## Preparation has no screen-map sketch"; return 1; }
    [ "$(grep -c '^### MC-[0-9]*\. ' "$ex")" -ge 3 ] || { echo "manual-checks.$lang.md: fewer than three cases"; return 1; }
    grep -qF '**dev-only:**' <<<"$prep" || { echo "manual-checks.$lang.md: no dev-only preparation step"; return 1; }
    ! grep -qF '**By instrument:**' "$ex" || { echo "manual-checks.$lang.md: a case still carries the instrument field"; return 1; }
    ! grep -qF '## Reading the verdict' "$ex" || { echo "manual-checks.$lang.md: the file still carries ## Reading the verdict"; return 1; }
    grep -qxF '## Code references' "$ex" || { echo "manual-checks.$lang.md: no ## Code references"; return 1; }
    ! grep -qF '**Code:**' "$ex" || { echo "manual-checks.$lang.md: a **Code:** field is still inside a case"; return 1; }
    fail="$(awk '/^## On failure/{f=1;next} f&&/^## /{exit} f' "$ex")"
    for label in '**Title:**' '**Build / device:**' '**Steps to reproduce:**' '**Actual:**' '**Expected:**' '**Attachments:**'; do
      grep -qF -- "$label" <<<"$fail" || { echo "manual-checks.$lang.md: the bug-report template has no $label"; return 1; }
    done
    ! grep -qiE '\b(swift|kotlin|java|android|ios|iphone|xcode|gradle)\b' "$ex" \
      || { echo "manual-checks.$lang.md names an ecosystem"; return 1; }
  done
  grep -qxF '| Word in the cases | What it is on the screen |' "$ROOT/skills/manual-checks/examples/manual-checks.en.md" \
    || { echo "manual-checks.en.md: no word table"; return 1; }
  # The same header in Russian, as escapes: no Cyrillic in a test file.
  grep -qxF "$(ru '| \u0421\u043b\u043e\u0432\u043e \u0432 \u043a\u0435\u0439\u0441\u0430\u0445 | \u0427\u0442\u043e \u044d\u0442\u043e \u043d\u0430 \u044d\u043a\u0440\u0430\u043d\u0435 |')" \
    "$ROOT/skills/manual-checks/examples/manual-checks.ru.md" || { echo "manual-checks.ru.md: no word table"; return 1; }
  run python3 - "$ROOT/skills/manual-checks/examples" <<'PY'
import re, sys
cyr = re.compile('[\u0400-\u04ff]')
en = open(sys.argv[1] + '/manual-checks.en.md', encoding='utf-8').read()
ru = open(sys.argv[1] + '/manual-checks.ru.md', encoding='utf-8').read()
assert not cyr.search(en), 'manual-checks.en.md holds Cyrillic'
assert len(cyr.findall(ru)) > 1500, 'manual-checks.ru.md is not written in Russian'
PY
  [ "$status" -eq 0 ] || { echo "$output"; return 1; }
}

@test "a case proves the change: before and after, the diff, the eye, no developer lines" {
  s="$(skill_section '## What a case must prove')"
  [ -n "$s" ] || { echo "no ## What a case must prove"; return 1; }
  for token in 'before the change' 'nothing broke' 'not a check of the fix' 'the diff' '`OpsChecklist.md`' \
               'at normal speed' 'never reads frames, traces or logs' '`Validation.md`' '`Walkthrough.md`' \
               'Outside `**dev-only:**` steps and `## Code references`, no line is for a developer'; do
    grep -qF -- "$token" <<<"$s" || { echo "## What a case must prove does not name $token"; return 1; }
  done
}

@test "a refresh moves an old file's code fields into the references section" {
  r="$(skill_section '## Refreshing')"
  grep -qF '`**Code:**`' <<<"$r" && grep -qF '`## Code references`' <<<"$r" || { echo "no migration on refresh"; return 1; }
}

@test "a plan line carries its intent" {
  skill_section '## Two stages, two halves' | grep -qF 'what must be true — what changed' \
    || { echo "## Manual acceptance lines carry no intent"; return 1; }
}

@test "claims are grounded in the code, and an empty case is deleted" {
  g="$(skill_section '## Grounding')"
  [ -n "$g" ] || { echo "no ## Grounding"; return 1; }
  for token in 'checked against the code' '`Review.md`' '`[COVERS]`' '**The empty case.**' '`## Not covered`' '`## Code references`'; do
    grep -qF -- "$token" <<<"$g" || { echo "## Grounding does not name $token"; return 1; }
  done
  [ "$(grep -c . <<<"$g")" -le 10 ] || { echo "## Grounding outgrew ten lines"; return 1; }
}

@test "a refresh re-checks only the cases whose code moved" {
  r="$(skill_section '## Refreshing')"
  [ -n "$r" ] || { echo "no ## Refreshing"; return 1; }
  for token in 'git diff --name-only <COVERS>..HEAD' 'the others are left alone' 'and so is a case with no code reference' '`[COVERS]` becomes HEAD'; do
    grep -qF -- "$token" <<<"$r" || { echo "## Refreshing does not name $token"; return 1; }
  done
  [ "$(grep -c . <<<"$r")" -le 7 ] || { echo "## Refreshing outgrew seven lines"; return 1; }
}

@test "the check walks the file cold and names each smell by kind" {
  c="$(skill_section '## Check')"
  [ -n "$c" ] || { echo "no ## Check"; return 1; }
  for token in '`[MANUAL_CHECKS_CHECK]`' '`manual_checks_check`' '`PASSED`' "validator's role" '`light`' 'nothing else' \
               '`walk`' '`smells`' '`ambiguous`' '`unverified`' '`precondition`' '`tacit`' '`oracle`' 'one pass' \
               '`access`' '`twofold`' '`chained`' 'a tester with no access to the code' \
               '`redundant`' 'deletes' '`ManualChecks.md check: N place(s), revised, A → B lines.`' \
               'The revision lengthened the file.' '`ManualChecks.md check: nothing unclear.`' \
               'moving `[COVERS]` alone is no change' 'except its `## Code references`' \
               'neither is ever a `redundant` place'; do
    grep -qF -- "$token" <<<"$c" || { echo "## Check does not name $token"; return 1; }
  done
  ! grep -qiE 'second round|two rounds' <<<"$c" || { echo "## Check grew a second round"; return 1; }
}

@test "Review judges a case by the case and its grounding" {
  r="$(skill_section '## Review')"
  grep -qF '`## The case` and `## Grounding`' <<<"$r" || { echo "## Review does not name its rules"; return 1; }
  grep -qF 'an empty case' <<<"$r" || { echo "## Review does not name the empty case"; return 1; }
}

# ── Method A: the cold walk after Validation, driven with stubbed agents ──
AGENTS='{"architect":"a","developer":"d","tester":"t","reviewer":"r","refactorer":"f","validator":"v","security":"—","diagnostics":"g","init":"—"}'

walk_run() { # $1 profile, $2 extra contract members (leading comma), $3 validation reply members (leading comma), $4 check reply
  node "$ROOT/tests/foundation/helpers/run-profile.js" "$ROOT/workflows/profile-$1.js" \
    "{\"task_id\": \"001\", \"task_dir\": \"/p/Tasks/ACTIVE/001-x\", \"plugin_root\": \"/core\", \"lang\": \"en\", \"agents\": $AGENTS, \"start_stage\": \"Validation\", \"end_stage\": \"Validation\", \"stage_scope\": \"forward\"$2}" \
    "{\"validation\": {\"validation_status\": \"PASSED\", \"reproduction_status\": \"fixed\", \"artifact_path\": \"v\", \"summary\": \"s\", \"manual_checks\": [\"the icon is new\"], \"manual_checks_path\": \"/p/Tasks/ACTIVE/001-x/ManualChecks.md\"$3}, \"manual-checks:check\": ${4:-$CLEAN}, \"manual-checks:revise\": {\"changed\": true, \"artifact_path\": \"/p/Tasks/ACTIVE/001-x/ManualChecks.md\"}}"
}

CLEAN='{"walk": ["I open the header"], "smells": []}'

pick() { node -e 'const o = JSON.parse(require("fs").readFileSync(0, "utf8")); const v = eval(process.argv[1]); console.log(typeof v === "string" ? v : JSON.stringify(v))' "$1"; }

labels() { pick 'o.calls.map((c) => c.label).join(" ")'; }

SMELL='{"walk": ["I look for the start"], "smells": [{"case": "1", "step": "2", "kind": "ambiguous", "quote": "find the start of the cell", "missing": "which cell, where"}]}'

@test "a passed Validation that wrote cases has the file walked cold by the validator's role" {
  for p in $PROFILES; do
    out="$(walk_run "$p" ', "manual_checks_style": "full"')"
    [ "$(labels <<<"$out")" = "validation manual-checks:check" ] || { echo "profile-$p: $(labels <<<"$out")"; return 1; }
    pr="$(pick 'o.calls[1].prompt' <<<"$out")"
    for f in 'spine-toolkit:manual-checks skill, its ## Check section' 'a tester with no access to the code' '/p/Tasks/ACTIVE/001-x/ManualChecks.md, except its ## Code references section, and nothing else' 'run no git command'; do
      grep -qF -- "$f" <<<"$pr" || { echo "profile-$p: the reader brief lost: $f"; return 1; }
    done
    grep -qF 'ManualChecks.md check: nothing unclear.' <<<"$(pick 'o.result.notes' <<<"$out")" || { echo "profile-$p: no note"; return 1; }
  done
}

@test "what the reader could not execute goes back to the validator for one revision" {
  for p in $PROFILES; do
    out="$(walk_run "$p" '' '' "$SMELL")"
    [ "$(labels <<<"$out")" = "validation manual-checks:check manual-checks:revise" ] || { echo "profile-$p: $(labels <<<"$out")"; return 1; }
    pr="$(pick 'o.calls[2].prompt' <<<"$out")"
    for f in 'find the start of the cell' 'which cell, where' 'ambiguous' 'I look for the start' '## Grounding'; do
      grep -qF -- "$f" <<<"$pr" || { echo "profile-$p: the revision brief lost: $f"; return 1; }
    done
    grep -qF 'ManualChecks.md check: 1 place(s), revised.' <<<"$(pick 'o.result.notes' <<<"$out")" || { echo "profile-$p: no note"; return 1; }
  done
}

@test "the revision reports the file's length before and after, and a longer file is flagged" {
  for p in $PROFILES; do
    out="$(node "$ROOT/tests/foundation/helpers/run-profile.js" "$ROOT/workflows/profile-$p.js" \
      "{\"task_id\": \"001\", \"task_dir\": \"/p/Tasks/ACTIVE/001-x\", \"plugin_root\": \"/core\", \"lang\": \"en\", \"agents\": $AGENTS, \"start_stage\": \"Validation\", \"end_stage\": \"Validation\", \"stage_scope\": \"forward\"}" \
      "{\"validation\": {\"validation_status\": \"PASSED\", \"reproduction_status\": \"fixed\", \"artifact_path\": \"v\", \"summary\": \"s\", \"manual_checks\": [\"a\"], \"manual_checks_path\": \"/p/Tasks/ACTIVE/001-x/ManualChecks.md\"}, \"manual-checks:check\": $SMELL, \"manual-checks:revise\": {\"changed\": true, \"artifact_path\": \"m\", \"lines_before\": 120, \"lines_after\": 98}}")"
    grep -qF 'ManualChecks.md check: 1 place(s), revised, 120 → 98 lines.' <<<"$(pick 'o.result.notes' <<<"$out")" || { echo "profile-$p: $(pick 'o.result.notes' <<<"$out")"; return 1; }
    ! grep -qF 'lengthened' <<<"$(pick 'o.result.notes' <<<"$out")" || { echo "profile-$p: flagged a shorter file"; return 1; }
    pr="$(pick 'o.calls[2].prompt' <<<"$out")"
    for f in 'redundant' 'lines_before' 'lines_after' 'wc -l'; do
      grep -qF -- "$f" <<<"$pr" || { echo "profile-$p: the revision brief lost: $f"; return 1; }
    done
    out="$(node "$ROOT/tests/foundation/helpers/run-profile.js" "$ROOT/workflows/profile-$p.js" \
      "{\"task_id\": \"001\", \"task_dir\": \"/p/Tasks/ACTIVE/001-x\", \"plugin_root\": \"/core\", \"lang\": \"en\", \"agents\": $AGENTS, \"start_stage\": \"Validation\", \"end_stage\": \"Validation\", \"stage_scope\": \"forward\"}" \
      "{\"validation\": {\"validation_status\": \"PASSED\", \"reproduction_status\": \"fixed\", \"artifact_path\": \"v\", \"summary\": \"s\", \"manual_checks\": [\"a\"], \"manual_checks_path\": \"/p/Tasks/ACTIVE/001-x/ManualChecks.md\"}, \"manual-checks:check\": $SMELL, \"manual-checks:revise\": {\"changed\": true, \"artifact_path\": \"m\", \"lines_before\": 98, \"lines_after\": 120}}")"
    grep -qF 'ManualChecks.md check: 1 place(s), revised, 98 → 120 lines. The revision lengthened the file.' <<<"$(pick 'o.result.notes' <<<"$out")" || { echo "profile-$p: $(pick 'o.result.notes' <<<"$out")"; return 1; }
  done
}

@test "the schema lets the revision omit its line counts" {
  for f in "$ROOT"/workflows/profile-*.js; do
    for line in "lines_before: { type: 'integer'" "lines_after: { type: 'integer'"; do
      grep -qF -- "$line" "$f" || { echo "$(basename "$f"): missing '$line'"; return 1; }
    done
    ! grep -qF "required: ['changed', 'artifact_path', 'lines_before'" "$f" || { echo "$(basename "$f"): the counts became required"; return 1; }
  done
}

@test "no profile calls the case fields twelve, and five name the eleven" {
  for f in "$ROOT"/workflows/profile-*.js; do
    ! grep -qF 'twelve fields' "$f" || { echo "$(basename "$f"): still says twelve fields"; return 1; }
  done
  for p in $PROFILES; do
    grep -qF 'the eleven fields that skill names' "$ROOT/workflows/profile-$p.js" || { echo "profile-$p.js: does not say the eleven fields that skill names"; return 1; }
  done
}

@test "no walk when the switch is off, the verdict is not PASSED, or the file was left as it was" {
  for p in $PROFILES; do
    [ "$(walk_run "$p" ', "manual_checks_check": "off"' | labels)" = validation ] || { echo "profile-$p: walked with the switch off"; return 1; }
    [ "$(walk_run "$p" '' ', "manual_checks_changed": false' | labels)" = validation ] || { echo "profile-$p: walked an unchanged file"; return 1; }
    out="$(node "$ROOT/tests/foundation/helpers/run-profile.js" "$ROOT/workflows/profile-$p.js" \
      "{\"task_id\": \"001\", \"task_dir\": \"/p/t\", \"plugin_root\": \"/core\", \"agents\": $AGENTS, \"start_stage\": \"Validation\", \"end_stage\": \"Validation\"}" \
      '{"validation": {"validation_status": "FAILED", "artifact_path": "v", "summary": "s", "manual_checks": ["a"]}}')"
    [ "$(labels <<<"$out")" = validation ] || { echo "profile-$p: walked after FAILED"; return 1; }
    out="$(node "$ROOT/tests/foundation/helpers/run-profile.js" "$ROOT/workflows/profile-$p.js" \
      "{\"task_id\": \"001\", \"task_dir\": \"/p/t\", \"plugin_root\": \"/core\", \"agents\": $AGENTS, \"start_stage\": \"Validation\", \"end_stage\": \"Validation\"}" \
      '{"validation": {"validation_status": "PASSED", "reproduction_status": "fixed", "artifact_path": "v", "summary": "s"}}')"
    [ "$(labels <<<"$out")" = validation ] || { echo "profile-$p: walked a run with no cases"; return 1; }
  done
}

@test "the walk is one prelude text, tuned light, and the validator says whether it touched the file" {
  n=0
  for f in "$ROOT"/workflows/profile-*.js; do
    n=$((n + 1))
    for line in '// A reader with none of the task'"'"'s context, then one revision: manual-checks → ## Check.' \
                "schema: MANUAL_CHECKS_READ, ...tuning(role, 'light')" \
                "kind: { type: 'string', enum: ['ambiguous', 'unverified', 'precondition', 'tacit', 'oracle', 'access', 'twofold', 'chained', 'redundant'] }" \
                "manual_checks_changed: { type: 'boolean', description: 'false when no case was added, removed or rewritten; moving [COVERS] alone is no change' }"; do
      grep -qF -- "$line" "$f" || { echo "$(basename "$f"): missing '$line'"; return 1; }
    done
  done
  [ "$n" -eq 8 ] || { echo "scanned $n script(s), expected 8"; return 1; }
  grep -qxF "    (r'manual-checks:check', 'light')," "$ROOT/scripts/lint-workflows.sh" || { echo "the lint does not hold the walk at light"; return 1; }
  grep -qF '`manual-checks:check`' "$ROOT/conventions/stage-dispatch.md" || { echo "the dispatch rule does not list the walk"; return 1; }
}

@test "the Plan brief asks each line for its intent" {
  for p in $PROFILES; do
    plan_brief "$ROOT/workflows/profile-$p.js" | grep -qF 'what must be true and what changed to make it so' \
      || { echo "profile-$p.js: the plan line carries no intent"; return 1; }
  done
}

@test "Review judges the hand-run script by the case and its grounding" {
  for p in $PROFILES; do
    rb="$(review_brief "$ROOT/workflows/profile-$p.js")"
    grep -qF 'a case a tester cannot execute as written' <<<"$rb" \
      || { echo "profile-$p.js: Review does not judge a case as its tester would"; return 1; }
    grep -qF "the rules of the manual-checks skill's ## The case and ## Grounding" <<<"$rb" \
      || { echo "profile-$p.js: Review does not name the sections it judges by"; return 1; }
    grep -qF 'an empty case' <<<"$rb" || { echo "profile-$p.js: Review does not name the empty case"; return 1; }
    ! grep -qF 'two rules the manual-checks skill states' <<<"$rb" || { echo "profile-$p.js: the two-rule clause is back"; return 1; }
  done
}

@test "Method B carries the plan-line intent, the cold walk and the Review rules" {
  for p in $PROFILES; do
    S="$ROOT/skills/workflow-$p/SKILL.md"
    bullet "$S" "$(plan_stage "$p")" | grep -qF 'what must be true and what changed to make it so' \
      || { echo "workflow-$p: the plan line carries no intent"; return 1; }
    v="$(bullet "$S" Validation)"
    for f in '`manual_checks_check` is `on`' '`manual-checks` → `## Check`' 'main context' 'moving `[COVERS]` alone is no change'; do
      grep -qF -- "$f" <<<"$v" || { echo "workflow-$p: the Validation stage lost: $f"; return 1; }
    done
    r="$(bullet "$S" Review)"
    grep -qF '`## The case` and `## Grounding`' <<<"$r" || { echo "workflow-$p: Review does not name its rules"; return 1; }
    grep -qF 'a case a tester cannot execute as written' <<<"$r" \
      || { echo "workflow-$p: Review does not judge a case as its tester would"; return 1; }
    ! grep -qF 'two rules in the `manual-checks` skill' <<<"$r" || { echo "workflow-$p: the two-rule clause is back"; return 1; }
  done
}

@test "the Validation brief refreshes an existing file and says when it left it alone" {
  for p in feature bug refactor test quick; do
    f="$ROOT/workflows/profile-$p.js"
    grep -qF "refresh it by that skill's ## Refreshing section" "$f" \
      || { echo "profile-$p.js: Validation never refreshes a file behind HEAD"; return 1; }
    grep -qF 'return manual_checks_changed false when no case was added, removed or rewritten — moving [COVERS] alone is no change' "$f" \
      || { echo "profile-$p.js: Validation never reports an untouched file, so the walk reruns"; return 1; }
  done
}

@test "a BUG that passed but still reproduces, or was not replayed, is not walked" {
  for status in still-reproduces not-replayed; do
    out="$(node "$ROOT/tests/foundation/helpers/run-profile.js" "$ROOT/workflows/profile-bug.js" \
      "{\"task_id\": \"001\", \"task_dir\": \"/p/t\", \"plugin_root\": \"/core\", \"agents\": $AGENTS, \"start_stage\": \"Validation\", \"end_stage\": \"Validation\"}" \
      "{\"validation\": {\"validation_status\": \"PASSED\", \"reproduction_status\": \"$status\", \"artifact_path\": \"v\", \"summary\": \"s\", \"manual_checks\": [\"a\"]}}")"
    [ "$(labels <<<"$out")" = validation ] || { echo "profile-bug: walked a run whose reproduction is $status"; return 1; }
  done
}

@test "the symbol rule covers the steps table, and lite halves nothing by a count" {
  grep -qF 'Neither `**Preconditions:**`, a cell of `**Steps:**`, nor `**Expected result:**`' "$SKILL" \
    || { echo "the symbol rule does not reach the steps table"; return 1; }
  ! grep -qF 'halves `## Preparation`' "$SKILL" || { echo "lite still halves ## Preparation by a count"; return 1; }
  ! grep -qF 'keep theirs' "$SKILL" || { echo "lite still speaks of ceilings a section keeps"; return 1; }
}

@test "Method B refreshes a file behind HEAD, and the orchestrator names the case it gates on" {
  for p in $PROFILES; do
    bullet "$ROOT/skills/workflow-$p/SKILL.md" Validation | grep -qF 'refreshing one behind HEAD by `## Refreshing`' \
      || { echo "workflow-$p: Method B never refreshes"; return 1; }
  done
  grep -qF 'a Validation that passed and wrote or changed one holding a case' "$ROOT/skills/orchestrator/SKILL.md" \
    || { echo "the orchestrator paragraph omits the case"; return 1; }
}

@test "the configuration entry says what the switch does and leaves the protocol to the skill" {
  s="$(awk '/^### \[MANUAL_CHECKS_CHECK\]/{f=1;next} f&&/^### /{exit} f' "$ROOT/docs/configuration.md")"
  [ "$(grep -c . <<<"$s")" -le 6 ] || { echo "the entry retells ## Check"; return 1; }
  for t in 'no `auto`' '`light`' 'holding a case'; do
    grep -qF -- "$t" <<<"$s" || { echo "the entry lost: $t"; return 1; }
  done
}

@test "the grounding lint runs after Validation writes the file and after the revision" {
  grep -qF '`scripts/lint-manual-checks.sh`' <<<"$(skill_section '## Grounding')" \
    || { echo "## Grounding does not name its lint"; return 1; }
  for p in feature bug refactor test quick; do
    grep -qF "Then run \"\${core('scripts/lint-manual-checks.sh')}\" on the file, repair every finding it prints, and run it again" "$ROOT/workflows/profile-$p.js" \
      || { echo "profile-$p.js: Validation never runs the lint and repairs what it finds"; return 1; }
    validation_brief "$ROOT/workflows/profile-$p.js" | grep -qF 'QA test cases for a tester who knows the product but not the code' \
      || { echo "profile-$p.js: the Validation brief does not name the case format and its reader"; return 1; }
    v="$(bullet "$ROOT/skills/workflow-$p/SKILL.md" Validation)"
    grep -qF '`scripts/lint-manual-checks.sh`' <<<"$v" || { echo "workflow-$p: Method B never runs the grounding lint"; return 1; }
    grep -qF 'repairs what it names and runs it again' <<<"$v" || { echo "workflow-$p: Method B does not repair the lint findings"; return 1; }
  done
  for f in "$ROOT"/workflows/profile-*.js; do
    grep -qF "read each case's \${startLabel} against its first step and its steps against each other" "$f" \
      || { echo "$(basename "$f"): the revision never checks the preconditions against the steps"; return 1; }
    for old in '**Scene:**' 'By eye' 'Wrap-up' 'You see' 'a person about to execute the file'; do
      ! grep -qF -- "$old" "$f" || { echo "$(basename "$f"): still names the old format: $old"; return 1; }
    done
  done
}

@test "the refresh names its diff command verbatim, so no validator reads one commit only" {
  for p in feature bug refactor test quick; do
    grep -qF 'the changed files are what git diff --name-only <the file'"'"'s [COVERS]>..HEAD prints, never one commit'"'"'s' "$ROOT/workflows/profile-$p.js" \
      || { echo "profile-$p.js: the refresh leaves the diff command to the validator"; return 1; }
    bullet "$ROOT/skills/workflow-$p/SKILL.md" Validation | grep -qF '`git diff --name-only <COVERS>..HEAD`' \
      || { echo "workflow-$p: Method B leaves the diff command to the validator"; return 1; }
  done
}

# ── A case only for a check that needs a person ─────────────────────────────

@test "the skill decides whether a check needs a person before it becomes a case" {
  s="$(skill_section '## Does this check need a person?')"
  [ -n "$s" ] || { echo "no ## Does this check need a person?"; return 1; }
  for t in 'device action' 'visual judgment' 'external service' '`automate`' '`covered`' '`drop`' '**dev-only:**'; do
    grep -qF -- "$t" <<<"$s" || { echo "the criterion does not name $t"; return 1; }
  done
  awk '/^## Does this check need a person\?$/{a=NR} /^## Structure$/{b=NR} END{exit !(a && b && a<b)}' "$SKILL" \
    || { echo "the criterion does not come before ## Structure"; return 1; }
}

@test "a plan line names what the person is needed for, and the rest has a home" {
  s="$(skill_section '## Two stages, two halves')"
  for t in 'needs: device action | visual judgment | external service' '## Not automated' 'Fully automatable.'; do
    grep -qF -- "$t" <<<"$s" || { echo "## Two stages does not carry $t"; return 1; }
  done
}

@test "no case left means no file under auto, and always still writes it" {
  s="$(skill_section '## Two stages, two halves')"
  for t in 'manual checks: none —' 'N/A' '`always`'; do
    grep -qF -- "$t" <<<"$s" || { echo "## Two stages does not say $t"; return 1; }
  done
}

@test "a refresh routes a new plan line through the criterion" {
  skill_section '## Refreshing' | grep -qF 'Does this check need a person?' \
    || { echo "## Refreshing step 3 makes a case directly"; return 1; }
}

@test "Review names a case nobody needs and a plan line without needs:" {
  s="$(skill_section '## Review')"
  grep -qF 'needs:' <<<"$s" || { echo "## Review does not name a plan line without needs:"; return 1; }
  grep -qF 'Does this check need a person?' <<<"$s" || { echo "## Review does not name a case nobody needs"; return 1; }
}

@test "the Plan template lists the section for checks nobody automates" {
  p="$(awk '/^## Plan\.md$/{f=1;next} f&&/^## /{exit} f' "$ROOT/skills/task-documents/SKILL.md")"
  grep -qF '## Not automated' <<<"$p" || { echo "task-documents: ## Plan.md lacks ## Not automated"; return 1; }
  grep -qF 'needs:' <<<"$p" || { echo "task-documents: ## Plan.md has no needs: tag"; return 1; }
}

@test "the manual test pass is N/A when no case needs a person" {
  grep -qiF 'no case that needs a person' "$ROOT/skills/ops-checklist/SKILL.md" \
    || { echo "ops-checklist: no N/A rule for the manual test pass"; return 1; }
}

@test "auto writes the file only when a case needs a person" {
  awk '/^### \[MANUAL_CHECKS\]$/{f=1;next} f&&/^### /{exit} f' "$ROOT/docs/configuration.md" | grep -qF 'needs a person' \
    || { echo "configuration.md: auto still means every deferred check"; return 1; }
}

@test "every Plan brief asks each line for what the person is needed for" {
  for p in $PROFILES; do
    b="$(plan_brief "$ROOT/workflows/profile-$p.js")"
    grep -qF 'needs:' <<<"$b" || { echo "profile-$p.js: no needs: in the Plan brief"; return 1; }
    grep -qF '## Not automated' <<<"$b" || { echo "profile-$p.js: no ## Not automated in the Plan brief"; return 1; }
    m="$(bullet "$ROOT/skills/workflow-$p/SKILL.md" "$(plan_stage "$p")")"
    grep -qF 'needs:' <<<"$m" || { echo "workflow-$p/SKILL.md: the Plan bullet has no needs:"; return 1; }
    grep -qF '## Not automated' <<<"$m" || { echo "workflow-$p/SKILL.md: the Plan bullet has no ## Not automated"; return 1; }
  done
}

@test "Validation makes a case only of a check that needs a person, and writes no file without one" {
  for p in $PROFILES; do
    b="$(validation_brief "$ROOT/workflows/profile-$p.js")"
    for t in 'Does this check need a person?' 'manual checks: none —' 'always writes the file regardless'; do
      grep -qF -- "$t" <<<"$b" || { echo "profile-$p.js: the Validation brief lacks $t"; return 1; }
    done
    m="$(bullet "$ROOT/skills/workflow-$p/SKILL.md" Validation)"
    for t in 'Does this check need a person?' 'manual checks: none —'; do
      grep -qF -- "$t" <<<"$m" || { echo "workflow-$p/SKILL.md: the Validation bullet lacks $t"; return 1; }
    done
  done
}

@test "Review names a case nobody needs and a plan line without needs:, not blocking" {
  for p in $PROFILES; do
    b="$(review_brief "$ROOT/workflows/profile-$p.js")"
    grep -qF 'with no needs:' <<<"$b" && grep -qF 'Does this check need a person?' <<<"$b" \
      || { echo "profile-$p.js: Review lacks the needs: and criterion findings"; return 1; }
    m="$(bullet "$ROOT/skills/workflow-$p/SKILL.md" Review)"
    grep -qF 'with no `needs:`' <<<"$m" && grep -qF 'Does this check need a person?' <<<"$m" \
      || { echo "workflow-$p/SKILL.md: Review lacks the needs: and criterion findings"; return 1; }
  done
}

@test "a check deferred because nothing could drive the app needs a person, the BUG replay included" {
  s="$(skill_section '## Does this check need a person?')"
  grep -qF 'nothing could drive the app' <<<"$s" || { echo "the criterion does not settle a deferred drive step"; return 1; }
  grep -qF 'replay' <<<"$s" || { echo "the criterion does not settle the BUG replay"; return 1; }
}

@test "always with no case left writes the file with ## Cases reading none" {
  skill_section '## Two stages, two halves' | grep -qF '`## Cases` reads `none — <why>`' \
    || { echo "the zero-case always file is not defined"; return 1; }
}

@test "the none line names what was covered and each automatable gap" {
  skill_section '## Two stages, two halves' | grep -qF 'each automatable gap' || { echo "skill: gaps are lost with no file"; return 1; }
  for p in $PROFILES; do
    validation_brief "$ROOT/workflows/profile-$p.js" | grep -qF 'each automatable gap' \
      || { echo "profile-$p.js: the none line does not carry the gaps"; return 1; }
    bullet "$ROOT/skills/workflow-$p/SKILL.md" Validation | grep -qF 'each automatable gap' \
      || { echo "workflow-$p/SKILL.md: the none line does not carry the gaps"; return 1; }
  done
}

@test "a scriptable finding is repaired by routing the case, never by rewording it" {
  skill_section '## The lint' | grep -qF 'rewording the steps is not a repair' \
    || { echo "## The lint gives scriptable no repair rule"; return 1; }
}

@test "an ops item is judged against the task's diff, and an untouched one is N/A, not a case" {
  O="$ROOT/skills/ops-checklist/SKILL.md"
  for token in "judged against this task's diff" '`not changed by this task: the diff touches <X>`' \
               'the conservative default applies to behaviour the diff touches'; do
    grep -qF -- "$token" "$O" || { echo "ops-checklist does not say: $token"; return 1; }
  done
}

@test "Review judges each case by what it must prove, and each N/A reason against the diff" {
  for p in $PROFILES; do
    b="$(review_brief "$ROOT/workflows/profile-$p.js")"
    grep -qF "the manual-checks skill's ## What a case must prove" <<<"$b" \
      || { echo "profile-$p.js: Review does not judge a case by ## What a case must prove"; return 1; }
    grep -qF 'each N/A reason of OpsChecklist.md that cites the diff' <<<"$b" \
      || { echo "profile-$p.js: Review does not check N/A reasons against the diff"; return 1; }
    m="$(bullet "$ROOT/skills/workflow-$p/SKILL.md" Review)"
    grep -qF '`## What a case must prove`' <<<"$m" \
      || { echo "workflow-$p/SKILL.md: Review does not judge a case by ## What a case must prove"; return 1; }
    grep -qF 'each N/A reason of `OpsChecklist.md` that cites the diff' <<<"$m" \
      || { echo "workflow-$p/SKILL.md: Review does not check N/A reasons against the diff"; return 1; }
  done
  grep -qF 'cross-checks Applicable items and N/A reasons against the actual diff' "$ROOT/skills/ops-checklist/SKILL.md" \
    || { echo "ops-checklist: the reviewer does not check N/A reasons"; return 1; }
}

@test "the diff rule holds for a task's checklist, and touches reaches the behaviour's path" {
  O="$ROOT/skills/ops-checklist/SKILL.md"
  for token in "When the checklist is written for a task, an item is judged against this task's diff" \
               'directly or through code on its path' 'When in doubt, it touches.' \
               'have no task diff and judge the product' 'for the categories the diff touches'; do
    grep -qF -- "$token" "$O" || { echo "ops-checklist does not say: $token"; return 1; }
  done
  skill_section '## What a case must prove' | grep -qF 'only when the diff touches that behaviour, as the `ops-checklist` skill defines touches' \
    || { echo "## What a case must prove uses another verb than ops-checklist"; return 1; }
}

@test "a task that changes no product behaviour still has cases worth a tester's time" {
  s="$(skill_section '## What a case must prove')"
  for token in 'On a task whose diff changes no product behaviour' 'the first rule does not apply' \
               'the behaviour the task targets that automation could not reach'; do
    grep -qF -- "$token" <<<"$s" || { echo "## What a case must prove does not say: $token"; return 1; }
  done
  validation_brief "$ROOT/workflows/profile-test.js" | grep -qF "## What a case must prove says for a task whose diff changes no product behaviour" \
    || { echo "profile-test.js: always does not point at the rule for such a task"; return 1; }
  bullet "$ROOT/skills/workflow-test/SKILL.md" Validation | grep -qF '`## What a case must prove` says for a task whose diff changes no product behaviour' \
    || { echo "workflow-test/SKILL.md: always does not point at the rule for such a task"; return 1; }
}

@test "the nothing-broke case is grounded in the code of what it guards" {
  skill_section '## What a case must prove' | grep -qF 'Its row in `## Code references` names the code of the behaviour it guards.' \
    || { echo "the nothing-broke case has no rule for its references row"; return 1; }
}

@test "the examples' Scope does not claim automation covered what a case checks by hand" {
  for lang in en ru; do
    ex="$ROOT/skills/manual-checks/examples/manual-checks.$lang.md"
    awk '/^## Scope$/{f=1;next} f&&/^## /{exit} f' "$ex" | grep -qE "limit of 10|$(ru '\u043f\u0440\u0435\u0434\u0435\u043b \u0432 10')" \
      && { echo "manual-checks.$lang.md: Scope says automation covered the limit MC-2 checks"; return 1; }
  done
  return 0
}

@test "the first question is whether the diff changes the behaviour, and an unchanged one gets neither a case nor a Pending" {
  s="$(skill_section '## Does this check need a person?')"
  [ -n "$s" ] || { echo "no ## Does this check need a person?"; return 1; }
  first="$(grep -m1 . <<<"$s")"
  grep -qF 'Does the diff change this behaviour?' <<<"$first" \
    || { echo "the section does not open with the question about the diff"; return 1; }
  for token in 'Does the diff change this behaviour?' 'neither a case nor a Pending' 'Fully automatable' \
               '`## Not covered`' 'as the `ops-checklist` skill defines touches' 'because a driver could not reach it' 'that alone is a reason the run could not do it, never a reason a person must'; do
    grep -qF -- "$token" <<<"$s" || { echo "## Does this check need a person? does not say: $token"; return 1; }
  done
  grep -qF 'names the change of the diff it checks' <<<"$s" \
    || { echo "a case written under Fully automatable does not name the change it checks"; return 1; }
}

@test "one check is one case: conditions are a table in Test data, walked once per row" {
  s="$(skill_section '## What a case must prove')"
  for token in 'one check, one case' 'a table of conditions in **Test data:**' 'once per row' \
               'does not walk again what ## Scope calls covered'; do
    grep -qF -- "$token" <<<"$s" || { echo "## What a case must prove does not say: $token"; return 1; }
  done
}

@test "a case that repeats another under other conditions is a redundant place" {
  skill_section '## Check' | grep -qF 'a case that repeats another under other conditions' \
    || { echo "## Check: redundant does not name a case repeated under other conditions"; return 1; }
}

@test "the diff-first question has two exceptions: a task with no product change, and the nothing-broke case" {
  s="$(skill_section '## Does this check need a person?')"
  grep -qF 'On a task whose diff changes no product behaviour, the question reads: does automation leave the behaviour the task targets unchecked?' <<<"$s" \
    || { echo "the opening question has no reading for a task with no product change"; return 1; }
  grep -qF 'The one nothing-broke case is the exception: it guards a regression on a path the diff touches, so it is not behaviour the diff does not change.' <<<"$s" \
    || { echo "the opening question does not except the nothing-broke case"; return 1; }
  skill_section '## What a case must prove' | grep -qF 'the first rule does not apply, and the question of `## Does this check need a person?` reads as it says for such a task' \
    || { echo "## What a case must prove does not point at the reading for such a task"; return 1; }
}

@test "the Test data field carries the conditions table, and a visual case starts from its scene" {
  grep -E '^- `\*\*Test data:\*\*`' "$SKILL" | grep -qF 'the table of conditions the steps are walked over' \
    || { echo "the Test data field does not mention the conditions table"; return 1; }
  skill_section '## What a case must prove' | grep -qF 'starts from a scene or its preconditions and does not re-run the covered flow to get there' \
    || { echo "a visual case may re-run the covered flow to reach the screen"; return 1; }
}

# The brief style (decisions 13-16 of iteration 2): a short case for a tester who knows the app.
@test "the skill says the style comes from manual_checks_style and the file names it after [COVERS]" {
  intro="$(awk '/^## The reader$/{exit} {print}' "$SKILL")"
  for token in '`manual_checks_style`' '`[STYLE] = <value>`' 'after `[COVERS]`' '`## Brief`'; do
    grep -qF -- "$token" <<<"$intro" || { echo "the top of the skill does not say $token"; return 1; }
  done
  awk '/^```$/{n++} n==1' <<<"$(skill_section '## Structure')" | grep -qxF '[STYLE] = full' \
    || { echo "the full structure does not show its [STYLE] line"; return 1; }
}

@test "the ## Brief section sets the reader, the file, the case and the rules it keeps" {
  b="$(skill_section '## Brief')"
  [ -n "$b" ] || { echo "no ## Brief section"; return 1; }
  for token in '[STYLE] = brief' '**Start:**' 'S1' '**Result:**' 'knows the app but not the task' \
               '**What it checks:**' '**Failure looks like:**' '**Test data:**' '→' \
               '`## What a case must prove`' '`## Grounding`' '`## Code references`' '`## Step rules`' \
               '### Screen map' '## Run record' '## On failure' '## Troubleshooting' '## Charter' \
               'one mark per case' 'no line limit'; do
    grep -qF -- "$token" <<<"$b" || { echo "## Brief does not say $token"; return 1; }
  done
  grep -qF 'examples/manual-checks.brief.en.md' <<<"$b" && grep -qF 'examples/manual-checks.brief.ru.md' <<<"$b" \
    || { echo "## Brief does not point at its examples"; return 1; }
}

@test "a brief case has no status: the Result line marks each case and names the failing condition" {
  b="$(skill_section '## Brief')"
  grep -qF 'carries one mark per case' <<<"$b" || { echo "## Brief does not say the Result line carries one mark per case"; return 1; }
  grep -qF "a failing condition is named in that mark's reason" <<<"$b" \
    || { echo "## Brief does not say where a failing condition is named"; return 1; }
}

@test "the check's reader in brief knows the app, and tacit reaches only the task's scenes, data and conditions" {
  c="$(skill_section '## Check')"
  for token in 'knows the app but not the task' 'scenes, data and conditions' 'adds no explanation of the product' \
               'a tester with no access to the code'; do
    grep -qF -- "$token" <<<"$c" || { echo "## Check does not say $token"; return 1; }
  done
}

@test "two brief examples pass the lint, hold three cases, and one walks a table of conditions" {
  for lang in en ru; do
    ex="$ROOT/skills/manual-checks/examples/manual-checks.brief.$lang.md"
    [ -f "$ex" ] || { echo "no example $ex"; return 1; }
    run "$ROOT/scripts/lint-manual-checks.sh" "$ex"
    [ "$status" -eq 0 ] || { echo "manual-checks.brief.$lang.md fails the lint:"; echo "$output"; return 1; }
    grep -qxF '[STYLE] = brief' "$ex" || { echo "manual-checks.brief.$lang.md: no [STYLE] = brief line"; return 1; }
    [ "$(grep -c '^### MC-[0-9]*\. ' "$ex")" -ge 3 ] || { echo "manual-checks.brief.$lang.md: fewer than three cases"; return 1; }
    grep -q '^### S1\. ' "$ex" || { echo "manual-checks.brief.$lang.md: no scene S1"; return 1; }
    grep -q '^\*\*Result:\*\* MC-1 ' "$ex" || { echo "manual-checks.brief.$lang.md: no Result line"; return 1; }
    # A table of conditions under **Test data:**, walked once per row.
    awk '/^\*\*Test data:\*\*/{f=1;next} f&&/^\|/{print "table"; exit} f&&/^[0-9]+\. /{exit}' "$ex" | grep -qx table \
      || { echo "manual-checks.brief.$lang.md: no case walks a table of conditions"; return 1; }
    for t in '## Run record' '## On failure' '## Troubleshooting' '## Charter' '### Screen map' '**Priority:**' '**Status:**'; do
      ! grep -qF -- "$t" "$ex" || { echo "manual-checks.brief.$lang.md carries $t"; return 1; }
    done
    ! grep -qiE '\b(swift|kotlin|java|android|ios|iphone|xcode|gradle)\b' "$ex" \
      || { echo "manual-checks.brief.$lang.md names an ecosystem"; return 1; }
  done
  run python3 - "$ROOT/skills/manual-checks/examples" <<'PY'
import re, sys
cyr = re.compile('[\u0400-\u04ff]')
en = open(sys.argv[1] + '/manual-checks.brief.en.md', encoding='utf-8').read()
ru = open(sys.argv[1] + '/manual-checks.brief.ru.md', encoding='utf-8').read()
assert not cyr.search(en), 'manual-checks.brief.en.md holds Cyrillic'
assert len(cyr.findall(ru)) > 400, 'manual-checks.brief.ru.md is not written in Russian'
PY
  [ "$status" -eq 0 ] || { echo "$output"; return 1; }
}

@test "the full examples name their style" {
  for lang in en ru; do
    grep -qxF '[STYLE] = full' "$ROOT/skills/manual-checks/examples/manual-checks.$lang.md" \
      || { echo "manual-checks.$lang.md: no [STYLE] = full line"; return 1; }
  done
}

@test "the reader and the reviser are briefed by the run's manual_checks_style" {
  for p in $PROFILES; do
    out="$(walk_run "$p" '' '' "$SMELL")"
    pr="$(pick 'o.calls[1].prompt' <<<"$out")"
    grep -qF 'knows the app but not the task' <<<"$pr" || { echo "profile-$p: the brief reader is not the one who knows the app"; return 1; }
    ! grep -qF 'a tester with no access to the code' <<<"$pr" || { echo "profile-$p: brief got the full reader"; return 1; }
    grep -qF 'tacit only for a scene, data or a condition of this task' <<<"$pr" || { echo "profile-$p: tacit is not narrowed in brief"; return 1; }
    grep -qF 'Add no explanation of the product' <<<"$(pick 'o.calls[2].prompt' <<<"$out")" \
      || { echo "profile-$p: the brief revision may explain the product"; return 1; }
    out="$(walk_run "$p" ', "manual_checks_style": "full"' '' "$SMELL")"
    pr="$(pick 'o.calls[1].prompt' <<<"$out")"
    grep -qF 'a tester with no access to the code' <<<"$pr" || { echo "profile-$p: full lost its reader"; return 1; }
    ! grep -qF 'knows the app but not the task' <<<"$pr" || { echo "profile-$p: full got the brief reader"; return 1; }
    ! grep -qF 'Add no explanation of the product' <<<"$(pick 'o.calls[2].prompt' <<<"$out")" \
      || { echo "profile-$p: the full revision may not explain the product"; return 1; }
  done
}

@test "the Validation brief writes the file in the run's style, and Method B says the same" {
  for p in $PROFILES; do
    grep -qF "This run's manual_checks_style is \${MANUAL_CHECKS_STYLE}: write the file in that style, its [STYLE] line naming it." "$ROOT/workflows/profile-$p.js" \
      || { echo "profile-$p.js: the Validation brief does not write the file in the run's style"; return 1; }
    grep -qF "in brief, short ### MC-<n>. cases for a tester who knows the app but not the task, with the four fields of its ## Brief section" "$ROOT/workflows/profile-$p.js" \
      || { echo "profile-$p.js: the Validation brief names only the full case"; return 1; }
    v="$(bullet "$ROOT/skills/workflow-$p/SKILL.md" Validation)"
    grep -qF 'in the style the contract'"'"'s `manual_checks_style` names, its `[STYLE]` line saying which' <<<"$v" \
      || { echo "workflow-$p: the Validation stage does not name manual_checks_style"; return 1; }
  done
}

@test "a refresh of a file in another style rewrites it whole in the run's style, ids kept" {
  r="$(skill_section '## Refreshing')"
  for token in "a file whose \`[STYLE]\` differs from this run's \`manual_checks_style\`" 'a file with no `[STYLE]` line reads as `full`' \
               "is rewritten whole in the run's style" 'its case ids are kept' 'a removed id is not reused'; do
    grep -qF -- "$token" <<<"$r" || { echo "## Refreshing does not say: $token"; return 1; }
  done
  for p in $PROFILES; do
    grep -qF "a file in another style is rewritten whole in this run's style, its case ids kept" "$ROOT/workflows/profile-$p.js" \
      || { echo "profile-$p.js: the Validation brief does not rewrite a file in another style"; return 1; }
  done
}

@test "the revision reads Start in brief and Preconditions in full against the first step" {
  for p in $PROFILES; do
    pr="$(walk_run "$p" '' '' "$SMELL" | pick 'o.calls[2].prompt')"
    grep -qF "read each case's **Start:** against its first step" <<<"$pr" || { echo "profile-$p: brief revision does not read Start"; return 1; }
    pr="$(walk_run "$p" ', "manual_checks_style": "full"' '' "$SMELL" | pick 'o.calls[2].prompt')"
    grep -qF "read each case's **Preconditions:** against its first step" <<<"$pr" || { echo "profile-$p: full revision does not read Preconditions"; return 1; }
  done
}

@test "## Brief says how the inherited rules read where they name full-only things" {
  b="$(skill_section '## Brief')"
  for token in 'where a rule names `**Preconditions:**`, read `**Start:**`' \
               "where it names \`**Expected result:**\`, read the last step's expectation" \
               'the interface language is named in `## Scope` or in `S1`' \
               'a step that needs a code change or a terminal goes in a scene marked `**dev-only:**`'; do
    grep -qF -- "$token" <<<"$b" || { echo "## Brief does not say: $token"; return 1; }
  done
}

@test "the brief examples hide no action in Test data, cover what their rows cover, and speak in screen terms" {
  for lang in en ru; do
    ex="$ROOT/skills/manual-checks/examples/manual-checks.brief.$lang.md"
    ! grep '^\*\*Test data:\*\*' "$ex" | grep -qiE "\\btap\\b|$(ru '\u043d\u0430\u0436')" || { echo "$lang: an action in Test data"; return 1; }
    ! grep -qiE "hard to read|every theme|$(ru '\u043f\u043b\u043e\u0445\u043e \u0447\u0438\u0442\u0430')|$(ru '\u043b\u044e\u0431\u043e\u0439 \u0442\u0435\u043c')" "$ex" \
      || { echo "$lang: a subjective or overreaching claim"; return 1; }
    ! awk '/^## Scope$/{f=1;next} f&&/^## /{exit} f' "$ex" | grep -qiE "in the model|$(ru '\u0432 \u043c\u043e\u0434\u0435\u043b\u0438')" \
      || { echo "$lang: Scope uses an internal term"; return 1; }
  done
}

@test "a check the diff does not change, deferred because a driver could not reach it, is never a reason a person must" {
  s="$(skill_section '## Does this check need a person?')"
  grep -qF 'holds for a check the diff does not change that was deferred because a driver could not reach it' <<<"$s" \
    || { echo "the first paragraph does not scope the driver deferral to a check the diff does not change"; return 1; }
  grep -qF 'so it needs a person' <<<"$s" || { echo "the changed, driver-deferred check is no longer a device action"; return 1; }
}

@test "every Review brief judges a brief file by ## Brief in place of ## The case" {
  for p in $PROFILES; do
    rb="$(review_brief "$ROOT/workflows/profile-$p.js")"
    grep -qF 'with ## Brief in place of ## The case for a file whose [STYLE] is brief' <<<"$rb" \
      || { echo "profile-$p.js: Review does not send a brief file to ## Brief"; return 1; }
    r="$(bullet "$ROOT/skills/workflow-$p/SKILL.md" Review)"
    grep -qF 'with `## Brief` in place of `## The case` for a file whose `[STYLE]` is brief' <<<"$r" \
      || { echo "workflow-$p: Review does not send a brief file to ## Brief"; return 1; }
  done
}

@test "## Brief says what the Result line holds when no case is left, and how a preparing step is written" {
  b="$(skill_section '## Brief')"
  for token in 'with no case left, `## Cases` reads `none — <why>` and the `**Result:**` line reads `**Result:** none`' \
               'A preparing step is a numbered step with no `→` line, allowed only when the next step'"'"'s expectation covers it'; do
    grep -qF -- "$token" <<<"$b" || { echo "## Brief does not say: $token"; return 1; }
  done
}

@test "the no-instrument rule reaches the scenes of ## Preparation" {
  grep -qF 'and no scene of `## Preparation` does either' "$SKILL" \
    || { echo "the skill does not say a Preparation scene asks no recording"; return 1; }
}

@test "the skill names the three marks of a collective pass and the contract key that switches them on" {
  for token in '**Runner:** agent' '**Device:**' '**Order:** first' '**Order:** last' '`manual_checks_pass`'; do
    grep -qF -- "$token" "$SKILL" || { echo "the skill never names $token"; return 1; }
  done
  s="$(skill_section '## Marks for a collective pass')"
  [ -n "$s" ] || { echo "no ## Marks for a collective pass"; return 1; }
  for token in '`manual_checks_pass`' '`end`' '`per-step`' '**Runner:** agent' '**Device:**' '**Order:**' \
               'field means a person, any device and any order'; do
    grep -qF -- "$token" <<<"$s" || { echo "## Marks for a collective pass does not say: $token"; return 1; }
  done
  # The section comes after ## What a case must prove, before ## Step rules.
  heads="$(grep '^## ' "$SKILL")"
  [ "$(grep -n -x '## Marks for a collective pass' <<<"$heads" | cut -d: -f1)" -eq "$(( $(grep -n -x '## What a case must prove' <<<"$heads" | cut -d: -f1) + 1 ))" ] \
    || { echo "## Marks for a collective pass does not follow ## What a case must prove"; return 1; }
}

@test "the marks sit after **What it checks:** and are optional in the case and in brief" {
  s="$(skill_section '## Marks for a collective pass')"
  grep -qF 'right after `**What it checks:**`' <<<"$s" || { echo "the marks are not placed after What it checks"; return 1; }
  grep -qF 'optional' <<<"$s" || { echo "the marks are not said to be optional"; return 1; }
  b="$(skill_section '## Brief')"
  for token in '**Runner:**' '**Device:**' '**Order:**' 'optional'; do
    grep -qF -- "$token" <<<"$b" || { echo "## Brief does not carry the mark $token"; return 1; }
  done
}

@test "under per-step no mark is written, and a Runner mark in a per-step run is a Review finding" {
  s="$(skill_section '## Marks for a collective pass')"
  grep -qF 'Under `per-step` none of the three is written' <<<"$s" || { echo "per-step still writes marks"; return 1; }
  r="$(skill_section '## Review')"
  grep -qF '**Runner:** agent' <<<"$r" && grep -qF '`per-step`' <<<"$r" \
    || { echo "Review does not name a Runner mark under per-step"; return 1; }
}

@test "a check deferred because nothing could drive the app is a Runner agent mark under end, a device action otherwise" {
  s="$(skill_section '## Does this check need a person?')"
  para="$(grep -F 'A check deferred because nothing could drive the app' <<<"$s")"
  for token in '`manual_checks_pass`' '`end`' '**Runner:** agent' '`per-step`'; do
    grep -qF -- "$token" <<<"$para" || { echo "the deferred-check paragraph does not say: $token"; return 1; }
  done
  grep -qF 'is a device action' <<<"$para" || { echo "the device action default is gone"; return 1; }
}

@test "the lint table names the field check and the three findings of the marks" {
  s="$(skill_section '## The lint')"
  grep -qF '| `field` |' <<<"$s" || { echo "the lint table has no field row"; return 1; }
  for token in '**Runner:**' '**Device:**' '**Order:**'; do
    grep -F '| `field` |' <<<"$s" | grep -qF -- "$token" || { echo "the field row does not name $token"; return 1; }
  done
}

# The collective pass: one ManualChecks.md at the root of an epic, written by its Acceptance stage.
@test "the skill has ## Collective pass, after ## Marks for a collective pass, and says who writes the file and from what" {
  grep -qx '## Collective pass' "$SKILL" || { echo "no ## Collective pass"; return 1; }
  heads="$(grep '^## ' "$SKILL")"
  [ "$(grep -n -x '## Collective pass' <<<"$heads" | cut -d: -f1)" -eq "$(( $(grep -n -x '## Marks for a collective pass' <<<"$heads" | cut -d: -f1) + 1 ))" ] \
    || { echo "## Collective pass does not follow ## Marks for a collective pass"; return 1; }
  s="$(skill_section '## Collective pass')"
  for token in '`Acceptance`' 'scripts/manual-checks-pass.sh collect' '`[PASS] = <step>, <step>, …`' \
               '`## Agent verdicts`' '`Validation.md`' '`## Scope`' '`## Preparation`' '`## Code references`' \
               '`### Session <n>. <device>`' '`#### <step>/MC-<n>. <behaviour>`' '`**Order:** first`' '`**Order:** last`' \
               '`**Result:**`' '`<id> PASS`' '`<id> FAIL (<why>)`' '`<id> BLOCKED (<why>)`' '`<id> DROPPED (<why>)`' '`<id> __`' \
               'any device' 'one language' 'unbalanced parenthesis' 'examples/manual-checks.pass.en.md' 'examples/manual-checks.pass.ru.md'; do
    grep -qF -- "$token" <<<"$s" || { echo "## Collective pass does not say: $token"; return 1; }
  done
}

@test "the collective pass keeps the agent's part out of the file, merges scenes and hands back what the agent could not reach" {
  s="$(skill_section '## Collective pass')"
  grep -qF 'The agent part is not in the file' <<<"$s" || { echo "the agent part is not kept out of the file"; return 1; }
  grep -qF 'goes to a person with the reason in `## Scope`' <<<"$s" || { echo "a case the agent did not reach has no route"; return 1; }
  grep -qF 'describe one state are merged' <<<"$s" || { echo "the scenes are not merged"; return 1; }
  grep -qF 'every difference' <<<"$s" || { echo "the differences of merged scenes are not recorded"; return 1; }
  grep -qF 'copied whole' <<<"$s" || { echo "a case is not copied whole"; return 1; }
  grep -qF 'time estimate' <<<"$s" || { echo "a session has no time estimate"; return 1; }
}

@test "the lint table names the pass file and its findings" {
  s="$(skill_section '## The lint')"
  grep -qF '| `pass` |' <<<"$s" || { echo "the lint table has no pass row"; return 1; }
  row="$(grep -F '| `pass` |' <<<"$s")"
  for token in '[PASS] = <step>' 'outside a session' '<step>/MC-<n>' 'Order'; do
    grep -qF -- "$token" <<<"$row" || { echo "the pass row does not name $token"; return 1; }
  done
}

@test "two collective pass examples pass the lint and show two sessions, a first-ordered case and a merged scene" {
  for lang in en ru; do
    ex="$ROOT/skills/manual-checks/examples/manual-checks.pass.$lang.md"
    [ -f "$ex" ] || { echo "no example $ex"; return 1; }
    run "$ROOT/scripts/lint-manual-checks.sh" "$ex"
    [ "$status" -eq 0 ] || { echo "manual-checks.pass.$lang.md fails the lint:"; echo "$output"; return 1; }
    grep -qE '^\[PASS\] = ' "$ex" || { echo "manual-checks.pass.$lang.md: no [PASS] line"; return 1; }
    [ "$(grep -c '^### Session [0-9]*\. ' "$ex")" -eq 2 ] || { echo "manual-checks.pass.$lang.md: not two sessions"; return 1; }
    n="$(grep -c '^#### [0-9][0-9]*/MC-[0-9]*\. ' "$ex")"
    { [ "$n" -ge 4 ] && [ "$n" -le 5 ]; } || { echo "manual-checks.pass.$lang.md: $n cases, not four or five"; return 1; }
    grep -qE '^\*\*Order:\*\* first ' "$ex" || { echo "manual-checks.pass.$lang.md: no case with Order first"; return 1; }
    grep -q '^### S1\. ' "$ex" || { echo "manual-checks.pass.$lang.md: no merged scene S1"; return 1; }
    grep -qE '^\*\*Result:\*\* 01/MC-1 ' "$ex" || { echo "manual-checks.pass.$lang.md: no Result line keyed by step"; return 1; }
    sc="$(awk '/^## Scope/{f=1;next} f&&/^## /{exit} f' "$ex")"
    grep -qiE "$(if [ "$lang" = en ]; then echo 'scene'; else ru '\u0441\u0446\u0435\u043d'; fi)" <<<"$sc" \
      || { echo "manual-checks.pass.$lang.md: ## Scope says nothing of the scenes"; return 1; }
    for t in '## Run record' '## On failure' '**Status:**' '**Priority:**'; do
      ! grep -qF -- "$t" "$ex" || { echo "manual-checks.pass.$lang.md carries $t"; return 1; }
    done
    ! grep -qiE '\b(swift|kotlin|java|android|ios|iphone|xcode|gradle)\b' "$ex" \
      || { echo "manual-checks.pass.$lang.md names an ecosystem"; return 1; }
  done
  run python3 - "$ROOT/skills/manual-checks/examples" <<'PY'
import re, sys
cyr = re.compile('[\u0400-\u04ff]')
en = open(sys.argv[1] + '/manual-checks.pass.en.md', encoding='utf-8').read()
ru = open(sys.argv[1] + '/manual-checks.pass.ru.md', encoding='utf-8').read()
assert not cyr.search(en), 'manual-checks.pass.en.md holds Cyrillic'
assert len(cyr.findall(ru)) > 300, 'manual-checks.pass.ru.md is not written in Russian'
PY
  [ "$status" -eq 0 ] || { echo "$output"; return 1; }
}

@test "the pass examples have the same cases in English and in Russian, and the script reads their Result line" {
  for lang in en ru; do
    ex="$ROOT/skills/manual-checks/examples/manual-checks.pass.$lang.md"
    grep -o '^#### [0-9][0-9]*/MC-[0-9]*\.' "$ex" >"$BATS_TEST_TMPDIR/ids.$lang"
    d="$BATS_TEST_TMPDIR/epic.$lang"
    mkdir -p "$d"
    cp "$ex" "$d/ManualChecks.md"
    run "$ROOT/scripts/manual-checks-pass.sh" marks "$d"
    [ "$status" -eq 0 ] || { echo "marks fails on the $lang example: $output"; return 1; }
    [ "$(python3 -c 'import json,sys; print(len(json.load(sys.stdin)["unmarked"]))' <<<"$output")" -eq "$(wc -l <"$BATS_TEST_TMPDIR/ids.$lang" | tr -d ' ')" ] \
      || { echo "the $lang example's Result line is not read case by case: $output"; return 1; }
  done
  diff "$BATS_TEST_TMPDIR/ids.en" "$BATS_TEST_TMPDIR/ids.ru" || { echo "the cases of the two examples differ"; return 1; }
}
