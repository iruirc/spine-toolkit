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
  for field in '**What it checks:**' '**Scene:**' '**Steps:**' '**By eye:**' '**By instrument:**' '**Failure looks like:**'; do
    grep -qF "$field" "$SKILL" || { echo "the skill never names the field $field"; return 1; }
  done
}

@test "the skill carries both rules that decide whether a case is executable" {
  grep -q '^## The instrument rule$' "$SKILL" || { echo "no instrument rule"; return 1; }
  grep -q '^## The symbol rule$' "$SKILL" || { echo "no symbol rule"; return 1; }
}

@test "the skill states both halves of the two-stage contract" {
  grep -q '## Manual acceptance' "$SKILL" || { echo "the skill never names the plan-side section"; return 1; }
  grep -q 'ManualChecks.md' "$SKILL" || { echo "the skill never names the artifact"; return 1; }
}

@test "the skill names the shared sections that keep a case from repeating its neighbours" {
  for section in '## Preparation' '## Reading the verdict' '## Troubleshooting'; do
    grep -qF "$section" "$SKILL" || { echo "the skill never names $section"; return 1; }
  done
  grep -qi 'conditional' "$SKILL" \
    || { echo "the shared sections are not marked conditional, so a two-case task gets all three"; return 1; }
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
  # Vacuity guard: without it the loops above iterate over a list someone shortened.
  n="$(grep -l '## Manual acceptance' "$ROOT"/workflows/profile-*.js | wc -l | tr -d ' ')"
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

@test "a case steps through a table, each row with what the doer sees" {
  grep -qxF '| # | Action | Data | You see |' "$SKILL" || { echo "the case has no steps table"; return 1; }
  grep -qF '**Wrap-up:**' "$SKILL" || { echo "the skill never names **Wrap-up:**"; return 1; }
  grep -qF '| `## Cases` | Numbered, one per check | ≤ 40 lines each |' "$SKILL" || { echo "a case is not budgeted at 40 lines"; return 1; }
  grep -qF 'a case to 20 lines' "$SKILL" || { echo "lite does not say what a case shrinks to"; return 1; }
  grep -qF '**Cases are independent.**' "$SKILL" || { echo "cases may still lean on each other"; return 1; }
}

@test "Preparation is an environment and a dictionary of actions, and Scope says what BLOCKED means" {
  grep -qF 'dictionary of actions' "$SKILL" || { echo "## Preparation has no dictionary of actions"; return 1; }
  grep -qF 'BLOCKED' "$SKILL" || { echo "## Scope never says when a case is BLOCKED"; return 1; }
  grep -qF '| `## Charter` |' "$SKILL" || { echo "the structure has no ## Charter"; return 1; }
}

@test "a plan line carries its intent" {
  skill_section '## Two stages, two halves' | grep -qF 'what must be true — what changed' \
    || { echo "## Manual acceptance lines carry no intent"; return 1; }
}

@test "claims are grounded in the code, and an empty case is deleted" {
  g="$(skill_section '## Grounding')"
  [ -n "$g" ] || { echo "no ## Grounding"; return 1; }
  for token in 'checked against the code' '`Review.md`' '`[COVERS]`' '**The empty case.**' '`## Not covered`'; do
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
  [ "$(grep -c . <<<"$r")" -le 6 ] || { echo "## Refreshing outgrew six lines"; return 1; }
}

@test "the check walks the file cold and names each smell by kind" {
  c="$(skill_section '## Check')"
  [ -n "$c" ] || { echo "no ## Check"; return 1; }
  for token in '`[MANUAL_CHECKS_CHECK]`' '`manual_checks_check`' '`PASSED`' "validator's role" '`light`' 'nothing else' \
               '`walk`' '`smells`' '`ambiguous`' '`unverified`' '`precondition`' '`tacit`' '`oracle`' 'one pass' \
               '`ManualChecks.md check: N place(s), revised.`' '`ManualChecks.md check: nothing unclear.`' \
               'moving `[COVERS]` alone is no change'; do
    grep -qF -- "$token" <<<"$c" || { echo "## Check does not name $token"; return 1; }
  done
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
    out="$(walk_run "$p")"
    [ "$(labels <<<"$out")" = "validation manual-checks:check" ] || { echo "profile-$p: $(labels <<<"$out")"; return 1; }
    pr="$(pick 'o.calls[1].prompt' <<<"$out")"
    for f in 'spine-toolkit:manual-checks skill, its ## Check section' '/p/Tasks/ACTIVE/001-x/ManualChecks.md and nothing else' 'run no git command'; do
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
                "kind: { type: 'string', enum: ['ambiguous', 'unverified', 'precondition', 'tacit', 'oracle'] }" \
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
