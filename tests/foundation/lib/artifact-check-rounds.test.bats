#!/usr/bin/env bats
# changed: sweep skills workflows
# The fresh-reader check of Plan.md (plan_check) and Done.md (done_check): one read by a new agent of the
# writer's role, then at most one revision, never a second read. Driven through the scripts with
# stubbed agents, so a loop that drifts from artifact-reader's ## Check fails here. The shared block
# is pinned byte-equal across the seven scripts that write either file, so a hand edit to one copy
# goes red.

load "$(dirname "$BATS_TEST_FILENAME")/../helpers/run-profile-read"

# The read replies are built once per file: each is one node start, and the tests ask for the same
# few sizes in every loop.
setup_file() {
  local n
  for n in 0 1 2 3 6; do
    export "READ_$n=$(node -e 'const n = +process.argv[1]; const kinds = ["reread", "undefined term", "identifier subject", "no reason", "no proof"]
      console.log(JSON.stringify({ retelling: ["r"], unclear: Array.from({ length: n }, (_, i) => ({ quote: "q" + i, missing: "m" + i, kind: kinds[i % 5] })) }))' "$n")"
  done
}

setup() {
  ROOT="$(cd -- "$(dirname -- "$BATS_TEST_FILENAME")/../../.." && pwd)"
  SEVEN="feature bug refactor test quick epic research"
  PLANNERS="feature bug refactor test"
  AGENTS='{"architect":"a","developer":"d","tester":"t","reviewer":"r","refactorer":"f","validator":"v","security":"—","diagnostics":"g","init":"—"}'
  REVISED='"artifact:revise": {"artifact_path": "x", "changed": true}'
  DECOMPOSED='"plan": {"ok": true, "artifact_path": "p", "summary": "s", "branch": "decomposition", "steps": []}'
  LINT='Last, run scripts/lint-artifact-readability.sh on the file once, with `--words-per-sentence` taken from the contract'"'"'s `budgets`; fix each finding once and name what is left in the stage summary.'
  ORDER_JS='o.calls.filter((c) => ["plan", "done"].includes(c.label) || c.label.startsWith("artifact")).map((c) => c.label.startsWith("artifact") ? c.label + "/" + c.phase : c.label).join(" ")'
  METHOD_B="dispatch a fresh agent of the writer's role to read the file only, per \`artifact-reader\` → \`## Check\`, then revise once"
}

# The shared block of one script, between its two markers.
block() {
  awk '/^\/\/ ── artifact check ─/ { f = 1 } f { print } /^\/\/ ── end artifact check ─/ { exit }' "$1"
}

# $1 profile, $2 start stage, $3 plan_check and done_check alike ("" leaves both out), $4 extra
# contract members.
contract() {
  local check=''
  [ -n "$3" ] && check=", \"plan_check\": \"$3\", \"done_check\": \"$3\""
  printf '{"task_id": "001", "task_dir": "/p/Tasks/ACTIVE/001-x", "plugin_root": "/core", "lang": "en", "agents": %s, "start_stage": "%s", "end_stage": "%s", "stage_scope": "forward", "walkthrough": "off"%s%s}' \
    "$AGENTS" "$2" "$2" "$check" "${4:-}"
}

# $1 profile, $2 stage (Plan or Done), $3 both checks, $4 replies members, $5 extra contract members,
# then JS expressions over o, which land in V[4], V[5], ... What most tests read from a run is set in
# F_ORDER (the stage's own dispatch and every artifact dispatch, each artifact one with its phase),
# F_STAGE, F_STATUS and F_NOTES.
stage() {
  local replies="$4"
  [ "$1" = epic ] && [ "$2" = Plan ] && replies="$DECOMPOSED${replies:+, $replies}"
  rp "$1" "$(contract "$1" "$2" "$3" "${5:-}")" "{$replies}" \
    "$ORDER_JS" \
    'o.result.last_completed_stage' 'o.result.status' 'o.result.notes' "${@:6}"
  F_ORDER="${V[0]}"; F_STAGE="${V[1]}"; F_STATUS="${V[2]}"; F_NOTES="${V[3]}"
}

# A read reply with $1 quoted places, from the ones setup_file built.
read_with() { local v="READ_$1"; printf '%s' "${!v}"; }

# The stages of one profile that write a checked file.
stages_of() { case " $PLANNERS epic " in *" $1 "*) echo 'Plan Done' ;; *) echo Done ;; esac; }

@test "the artifact check block is byte-identical in the seven scripts and absent from REVIEW" {
  ref="$(block "$ROOT/workflows/profile-feature.js")"
  [ "$(wc -l <<<"$ref")" -gt 40 ] || { echo "the block was not found in profile-feature.js"; return 1; }
  n=0
  for p in $SEVEN; do
    n=$((n + 1))
    [ "$(block "$ROOT/workflows/profile-$p.js")" = "$ref" ] \
      || { echo "profile-$p.js: the artifact check block drifted"; diff <(block "$ROOT/workflows/profile-$p.js") <(printf '%s\n' "$ref") | head -20; return 1; }
  done
  [ "$n" -eq 7 ]
  [ -z "$(block "$ROOT/workflows/profile-review.js")" ] || { echo "profile-review.js carries the block, but writes neither file"; return 1; }
  ! grep -qF 'checkArtifact' "$ROOT/workflows/profile-review.js" || { echo "profile-review.js calls checkArtifact"; return 1; }
}

@test "every script guards PLAN_CHECK and DONE_CHECK to on or off, and no ARTIFACT_CHECK is left" {
  for p in $SEVEN review; do
    grep -qxF "const PLAN_CHECK = A.plan_check === 'on' ? 'on' : 'off'" "$ROOT/workflows/profile-$p.js" \
      || { echo "profile-$p.js: plan_check is not guarded"; return 1; }
    grep -qxF "const DONE_CHECK = A.done_check === 'on' ? 'on' : 'off'" "$ROOT/workflows/profile-$p.js" \
      || { echo "profile-$p.js: done_check is not guarded"; return 1; }
    ! grep -q 'ARTIFACT_CHECK\|artifact_check' "$ROOT/workflows/profile-$p.js" || { echo "profile-$p.js still names artifact_check"; return 1; }
  done
}

@test "every Plan call is guarded by PLAN_CHECK, every Done call by DONE_CHECK, Plan in the four planners, Done in all seven" {
  for p in $SEVEN; do
    f="$ROOT/workflows/profile-$p.js"
    calls="$(grep -F 'await checkArtifact(' "$f")"
    ! grep -F "checkArtifact('Plan'" <<<"$calls" | grep -vF "PLAN_CHECK === 'on'" | grep -q . || { echo "profile-$p.js: a Plan call not guarded by PLAN_CHECK: $calls"; return 1; }
    ! grep -F "checkArtifact('Done'" <<<"$calls" | grep -vF "DONE_CHECK === 'on'" | grep -q . || { echo "profile-$p.js: a Done call not guarded by DONE_CHECK: $calls"; return 1; }
    [ "$(grep -cF "\`\${DIR}/Done.md\`)" <<<"$calls")" -eq 1 ] || { echo "profile-$p.js: Done.md is not checked exactly once"; return 1; }
    want=0
    [ "$(stages_of "$p")" = 'Plan Done' ] && want=1
    [ "$(grep -cF "\`\${DIR}/Plan.md\`)" <<<"$calls")" -eq "$want" ] || { echo "profile-$p.js: Plan.md checked other than $want time(s)"; return 1; }
  done
}

@test "off, or no field at all, makes no extra dispatch" {
  for p in $SEVEN; do
    for s in $(stages_of "$p"); do
      for c in off ''; do
        stage "$p" "$s" "$c" "\"artifact:check\": $(read_with 3)"
        ! grep -qF 'artifact:' <<<"$F_ORDER" || { echo "profile-$p $s (checks='$c'): $F_ORDER"; return 1; }
      done
    done
  done
}

@test "on with nothing unclear: one read after Plan and one after Done, no revision" {
  for p in $SEVEN; do
    for s in $(stages_of "$p"); do
      stage "$p" "$s" on "\"artifact:check\": $(read_with 0)"
      want="$(tr 'A-Z' 'a-z' <<<"$s") artifact:check/$s"
      [ "$F_ORDER" = "$want" ] || { echo "profile-$p $s: dispatched $F_ORDER"; return 1; }
      grep -qF "$s.md check: nothing unclear." <<<"$F_NOTES" || { echo "profile-$p $s: no note"; return 1; }
    done
  done
}

@test "one, three and six unclear places get exactly one revision and no second read" {
  for n in 1 3 6; do
    for p in $SEVEN; do
      for s in $(stages_of "$p"); do
        stage "$p" "$s" on "\"artifact:check\": $(read_with "$n"), $REVISED"
        want="$(tr 'A-Z' 'a-z' <<<"$s") artifact:check/$s artifact:revise/$s"
        [ "$F_ORDER" = "$want" ] || { echo "profile-$p $s, $n place(s): dispatched $F_ORDER"; return 1; }
        grep -qF "$s.md check: $n place(s), revised." <<<"$F_NOTES" || { echo "profile-$p $s: no note: $F_NOTES"; return 1; }
      done
    done
  done
}

@test "a read that returns nothing, throws, or returns no unclear list ends the check quietly and the run goes on" {
  for p in $SEVEN; do
    for s in $(stages_of "$p"); do
      for reply in null '{"__throw": "dispatch failed"}' '{"retelling": ["r"], "unclear": "none"}' '{"retelling": ["r"]}'; do
        stage "$p" "$s" on "\"artifact:check\": $reply"
        [ "$F_ORDER" = "$(tr 'A-Z' 'a-z' <<<"$s") artifact:check/$s" ] || { echo "profile-$p $s: dispatched $F_ORDER"; return 1; }
        grep -qF "$s.md check: the reader returned nothing, so the file went unchecked." <<<"$F_NOTES" \
          || { echo "profile-$p $s: no note: $F_NOTES"; return 1; }
        [ "$F_STAGE" = "$s" ] || { echo "profile-$p $s: the run stopped: $F_ORDER $F_NOTES"; return 1; }
        [ "$F_STATUS" != error ] || { echo "profile-$p $s: the run errored: $F_ORDER $F_NOTES"; return 1; }
      done
    done
  done
}

@test "an unclear entry without a quote is skipped, and all of them quote-less is nothing to revise" {
  bare='{"retelling": ["r"], "unclear": [{"missing": "m-none", "kind": "reread"}, {"quote": "  ", "missing": "m-blank", "kind": "no proof"}]}'
  mixed='{"retelling": ["r"], "unclear": [{"quote": "q-one", "missing": "m-one", "kind": "no reason"}, {"missing": "m-none", "kind": "reread"}, {"quote": "q-two", "missing": "m-two", "kind": "undefined term"}]}'
  for p in $SEVEN; do
    for s in $(stages_of "$p"); do
      stage "$p" "$s" on "\"artifact:check\": $bare, $REVISED"
      [ "$F_ORDER" = "$(tr 'A-Z' 'a-z' <<<"$s") artifact:check/$s" ] || { echo "profile-$p $s: dispatched $F_ORDER"; return 1; }
      grep -qF "$s.md check: nothing unclear." <<<"$F_NOTES" || { echo "profile-$p $s: $F_NOTES"; return 1; }
      grep -qF "$s.md check: 2 entry(ies) quoted no place, so they were skipped." <<<"$F_NOTES" || { echo "profile-$p $s: $F_NOTES"; return 1; }

      stage "$p" "$s" on "\"artifact:check\": $mixed, $REVISED" '' "o.calls.find((c) => c.label === 'artifact:revise').prompt"
      [ "$F_ORDER" = "$(tr 'A-Z' 'a-z' <<<"$s") artifact:check/$s artifact:revise/$s" ] || { echo "profile-$p $s: dispatched $F_ORDER"; return 1; }
      grep -qF "$s.md check: 2 place(s), revised." <<<"$F_NOTES" || { echo "profile-$p $s: $F_NOTES"; return 1; }
      fix="${V[4]}"
      grep -qF '"q-two" — m-two' <<<"$fix" || { echo "profile-$p $s: the revision does not carry a quoted place"; return 1; }
      ! grep -qF 'm-none' <<<"$fix" || { echo "profile-$p $s: the revision carries the quote-less entry"; return 1; }
    done
  done
}

@test "a revision that returns nothing or changes nothing is noted, never read again" {
  for p in $SEVEN; do
    s=Done
    stage "$p" "$s" on "\"artifact:check\": $(read_with 2), \"artifact:revise\": null"
    [ "$F_ORDER" = "done artifact:check/Done artifact:revise/Done" ] || { echo "profile-$p: dispatched $F_ORDER"; return 1; }
    grep -qF 'Done.md check: 2 place(s); the revision returned nothing, so the file stands as written.' <<<"$F_NOTES" \
      || { echo "profile-$p: $F_NOTES"; return 1; }
    stage "$p" "$s" on "\"artifact:check\": $(read_with 2), \"artifact:revise\": {\"artifact_path\": \"x\", \"changed\": false}"
    [ "$F_ORDER" = "done artifact:check/Done artifact:revise/Done" ] || { echo "profile-$p: dispatched $F_ORDER"; return 1; }
    grep -qF 'Done.md check: 2 place(s); the revision found nothing to change.' <<<"$F_NOTES" \
      || { echo "profile-$p: $F_NOTES"; return 1; }
  done
}

@test "the read prompt names the file, the owner who did not follow the task, and the five kinds" {
  for s in Plan Done; do
    stage feature "$s" on "\"artifact:check\": $(read_with 0)" '' "o.calls.find((c) => c.label === 'artifact:check').prompt"
    c="${V[4]}"
    for token in "/p/Tasks/ACTIVE/001-x/$s.md and nothing else" 'owner who did not follow the task' \
                 'spine-toolkit:artifact-reader' '## Check' 'no git command' \
                 'reread' 'undefined term' 'identifier subject' 'no reason' 'no proof' 'Change nothing on disk.'; do
      grep -qF "$token" <<<"$c" || { echo "the $s read prompt does not name: $token"; return 1; }
    done
  done
}

@test "the read schema carries the five kinds of artifact-reader's ## Check, in order" {
  check="$(awk '/^## Check$/{f=1;next} f&&/^## /{exit} f' "$ROOT/skills/artifact-reader/SKILL.md")"
  kinds="$(grep -oE '^  - `[a-z ]+`:' <<<"$check" | sed -E 's/^  - `([a-z ]+)`:$/\1/' | paste -sd, -)"
  [ "$kinds" = 'reread,undefined term,identifier subject,no reason,no proof' ] || { echo "the skill lists: $kinds"; return 1; }
  grep -qxF "const ARTIFACT_KINDS = ['reread', 'undefined term', 'identifier subject', 'no reason', 'no proof']" "$ROOT/workflows/profile-feature.js" \
    || { echo "the script's kinds differ from the skill's"; return 1; }
  stage feature Done on "\"artifact:check\": $(read_with 0)" '' \
    "o.calls.find((c) => c.label === 'artifact:check').schema.properties.unclear.items.properties.kind.enum.join()" \
    "o.calls.find((c) => c.label === 'artifact:check').schema.properties.unclear.items.required.join()"
  [ "${V[4]}" = 'reread,undefined term,identifier subject,no reason,no proof' ]
  [ "${V[5]}" = 'quote,missing,kind' ]
}

@test "the read is tuned light on the writer's role; the revision takes the writing stage's tuning" {
  models=', "models": {"light": "haiku", "done": "sonnet", "architect": "opus", "developer": "opus", "tester": "opus", "refactorer": "opus"}, "effort": {"done": "max", "architect": "high", "developer": "high", "tester": "high", "refactorer": "high"}'
  for p in $SEVEN; do
    for s in $(stages_of "$p"); do
      w="$(tr 'A-Z' 'a-z' <<<"$s")"
      stage "$p" "$s" on "\"artifact:check\": $(read_with 1), $REVISED" "$models" \
        "const t = (l) => { const c = o.calls.find((x) => x.label === l); return JSON.stringify([c.model, c.effort]) }; [t('artifact:check'), t('$w'), t('artifact:revise')].join('\\n')"
      { read -r rd; read -r writer; read -r revise; } <<<"${V[4]}"
      [ "$rd" = '["haiku","high"]' ] || { echo "profile-$p $s: the read is tuned $rd, not light at the role's effort"; return 1; }
      [ "$revise" = "$writer" ] || { echo "profile-$p $s: the revision is tuned $revise, the writer $writer"; return 1; }
    done
  done
}

@test "QUICK and RESEARCH check only Done.md" {
  for p in quick research; do
    stage "$p" Done on "\"artifact:check\": $(read_with 0)"
    [ "$F_ORDER" = 'done artifact:check/Done' ] || { echo "profile-$p: dispatched $F_ORDER"; return 1; }
    ! grep -qF 'Plan.md' <<<"$(grep -F 'await checkArtifact(' "$ROOT/workflows/profile-$p.js")" || { echo "profile-$p.js checks Plan.md"; return 1; }
  done
}

@test "plan_check on and done_check off read Plan.md and leave Done.md, and the reverse reads only Done.md" {
  for p in $PLANNERS epic; do
    stage "$p" Plan '' "\"artifact:check\": $(read_with 0)" ', "plan_check": "on", "done_check": "off"'
    [ "$F_ORDER" = 'plan artifact:check/Plan' ] || { echo "profile-$p Plan, plan on: dispatched $F_ORDER"; return 1; }
    stage "$p" Done '' "\"artifact:check\": $(read_with 0)" ', "plan_check": "on", "done_check": "off"'
    [ "$F_ORDER" = 'done' ] || { echo "profile-$p Done, done off: dispatched $F_ORDER"; return 1; }
    stage "$p" Plan '' "\"artifact:check\": $(read_with 0)" ', "plan_check": "off", "done_check": "on"'
    [ "$F_ORDER" = 'plan' ] || { echo "profile-$p Plan, plan off: dispatched $F_ORDER"; return 1; }
    stage "$p" Done '' "\"artifact:check\": $(read_with 0)" ', "plan_check": "off", "done_check": "on"'
    [ "$F_ORDER" = 'done artifact:check/Done' ] || { echo "profile-$p Done, done on: dispatched $F_ORDER"; return 1; }
  done
}

@test "QUICK and RESEARCH read nothing under plan_check on and done_check off" {
  for p in quick research; do
    stage "$p" Done '' "\"artifact:check\": $(read_with 0)" ', "plan_check": "on", "done_check": "off"'
    [ "$F_ORDER" = 'done' ] || { echo "profile-$p: dispatched $F_ORDER"; return 1; }
  done
}

@test "EPIC asks each step for its plan_check and done_check and hands them on, the epic's own where the step has none" {
  steps='"execute:read-steps": {"branch": "decomposition", "steps": [{"step_id": "1-a.step", "task_id": "001.1", "task_type": "FEATURE", "status": "PENDING", "plan_check": "on", "done_check": "off"}, {"step_id": "2-b.step", "task_id": "001.2", "task_type": "BUG", "status": "PENDING"}]}'
  done_reply='{"status": "ok", "last_completed_stage": "Done", "stages": []}'
  rp epic "$(contract epic Execute '' ', "mode": "auto", "plan_check": "off", "done_check": "on"')" \
    "{$steps, \"workflow:spine-toolkit:profile-feature\": $done_reply, \"workflow:spine-toolkit:profile-bug\": $done_reply}" \
    "const s = o.calls.find((c) => c.label === 'execute:read-steps').schema.properties.steps.items.properties; [s.plan_check.enum.join(), s.done_check.enum.join(), 'artifact_check' in s].join(' ')" \
    "o.calls.find((c) => c.label === 'execute:read-steps').prompt" \
    "const a = o.calls.find((c) => c.label === 'workflow:spine-toolkit:profile-feature').args; [a.plan_check, a.done_check, 'artifact_check' in a].join(' ')" \
    "const a = o.calls.find((c) => c.label === 'workflow:spine-toolkit:profile-bug').args; [a.plan_check, a.done_check].join(' ')"
  [ "${V[0]}" = 'on,off on,off false' ] || { echo "the step record: ${V[0]}"; return 1; }
  grep -qF 'walkthrough_when, plan_check, done_check, report' <<<"${V[1]}" || { echo "read-steps does not ask for both checks"; return 1; }
  [ "${V[2]}" = 'on off false' ] || { echo "the first step got: ${V[2]}"; return 1; }
  [ "${V[3]}" = 'off on' ] || { echo "the second step got: ${V[3]}"; return 1; }
}

@test "EPIC checks Plan.md only on the decomposition branch, and Done.md on both" {
  E="$ROOT/workflows/profile-epic.js"
  rp epic "$(contract epic Plan on)" "{\"plan\": {\"ok\": true, \"artifact_path\": \"p\", \"summary\": \"s\", \"branch\": \"pure_research\", \"steps\": []}, \"artifact:check\": $(read_with 0)}" \
    "$ORDER_JS"
  F_ORDER="${V[0]}"
  [ "$F_ORDER" = 'plan' ] || { echo "pure research: dispatched $F_ORDER"; return 1; }
  stage epic Plan on "\"artifact:check\": $(read_with 0)"
  [ "$F_ORDER" = 'plan artifact:check/Plan' ] || { echo "decomposition: dispatched $F_ORDER"; return 1; }
  for b in decomposition pure_research; do
    stage epic Done on "\"done:read-branch\": {\"branch\": \"$b\"}, \"artifact:check\": $(read_with 0)"
    [ "$F_ORDER" = 'done artifact:check/Done' ] || { echo "$b Done: dispatched $F_ORDER"; return 1; }
  done
}

@test "the seven workflow skills carry the Method B check paragraph" {
  for s in bug feature refactor test quick epic research; do
    S="$ROOT/skills/workflow-$s/SKILL.md"
    para="$(grep -F '`done_check`' "$S" | grep -F "$METHOD_B")"
    [ -n "$para" ] || { echo "workflow-$s: no Method B paragraph"; return 1; }
    for token in 'is `on`' 'never a second round' '`light`'; do
      grep -qF "$token" <<<"$para" || { echo "workflow-$s: the paragraph does not say $token"; return 1; }
    done
    if [ "$s" = quick ] || [ "$s" = research ]; then
      grep -qF '`Done.md`' <<<"$para" || { echo "workflow-$s: the paragraph does not name Done.md"; return 1; }
    else
      grep -qF '`plan_check` is `on`, the main context checks `Plan.md` after Plan' <<<"$para" \
        && grep -qF '`done_check` is `on`, `Done.md` after Done' <<<"$para" \
        || { echo "workflow-$s: the paragraph does not name both files"; return 1; }
    fi
  done
  grep -qF '`Plan.md` after Plan on the decomposition branch' <<<"$(grep -F "$METHOD_B" "$ROOT/skills/workflow-epic/SKILL.md")" \
    || { echo "workflow-epic: the paragraph does not limit the Plan check to the decomposition branch"; return 1; }
}

@test "each Plan bullet of a skill with the check paragraph points at it" {
  POINTER='When the contract'"'"'s `plan_check` is `on`, a fresh reader checks `Plan.md` after this stage; the Done bullet says how.'
  for s in bug feature refactor test epic; do
    body="$(awk '/^## 2\. Stages/{z=1;next} z&&/^## /{exit} z&&/^- \*\*/{f=index($0, "- **Plan**")==1} z&&f' "$ROOT/skills/workflow-$s/SKILL.md")"
    [ "$(grep -cF "$POINTER" <<<"$body")" -eq 1 ] || { echo "workflow-$s: the Plan bullet has no pointer at the check paragraph"; return 1; }
  done
}

@test "the epic's research says the short answer opens it on either branch, once" {
  body="$(awk '/^## 2\. Stages/{z=1;next} z&&/^## /{exit} z&&/^- \*\*/{f=index($0, "- **Research**")==1} z&&f' "$ROOT/skills/workflow-epic/SKILL.md")"
  grep -qF 'On either branch `Research.md` opens with `## Short answer`.' <<<"$body" || { echo "workflow-epic: the short answer is not said for either branch"; return 1; }
}

@test "every workflow skill runs the readability lint where its script does" {
  # One bullet per stage that writes a linted file, as the scripts' briefs do; the epic's Plan
  # lints the decomposition plan and the pure-research roadmap.
  for entry in 'feature:Research Plan Review Done' 'bug:Diagnose Plan Review Done' 'refactor:Analyze Plan Review Done' \
               'test:Analyze Plan Review Done' 'quick:Review Done' 'epic:Research Plan Plan Done' 'research:Research Review Done' 'review:Review'; do
    s="${entry%%:*}"
    S="$ROOT/skills/workflow-$s/SKILL.md"
    [ "$(grep -cF "$LINT" "$S")" -eq "$(wc -w <<<"${entry#*:}")" ] || { echo "workflow-$s: the lint sentence appears $(grep -cF "$LINT" "$S") time(s)"; return 1; }
    for st in ${entry#*:}; do
      body="$(awk -v st="$st" '/^## 2\. Stages/{z=1;next} z&&/^## /{exit} z&&/^- \*\*/{f=index($0, "- **" st "**")==1} z&&f' "$S")"
      grep -qF "$LINT" <<<"$body" || { echo "workflow-$s: stage $st does not run the lint"; return 1; }
    done
  done
}

@test "the lint sentence in the skills says what the scripts' briefs say" {
  for p in $SEVEN review; do
    grep -qF 'lint-artifact-readability.sh' "$ROOT/workflows/profile-$p.js" || { echo "profile-$p.js no longer runs the lint"; return 1; }
    grep -qF 'once. Fix each finding once; do not run it again; name what is left in your summary.' "$ROOT/workflows/profile-$p.js" \
      || { echo "profile-$p.js: the lint brief changed"; return 1; }
  done
}

@test "the configuration reference says which file, one read and one revision, no second round" {
  for entry in 'PLAN_CHECK:`Plan.md` after Plan:decomposition' 'DONE_CHECK:`Done.md` after Done:either branch'; do
    F="${entry%%:*}"; rest="${entry#*:}"
    ck="$(awk -v h="### [$F]" '$0 == h {f=1;next} /^### /{f=0} f' "$ROOT/docs/configuration.md")"
    for token in "${rest%%:*}" "${rest#*:}" 'one read and at most one revision' 'no second round'; do
      grep -qF "$token" <<<"$ck" || { echo "configuration.md [$F] does not say: $token"; return 1; }
    done
  done
}

@test "the settings convention says a raise to full mid-run checks from the next run" {
  grep -qF 'a task raised to `full` mid-run is checked from the next run on' "$ROOT/conventions/task-settings.md" \
    || { echo "task-settings.md still says a mid-run raise turns the check on at once"; return 1; }
  ! grep -qF 'turns the check on with it' "$ROOT/conventions/task-settings.md" || { echo "the old claim is still there"; return 1; }
}

@test "the block says why the artifact check is quiet and the walkthrough check is not" {
  grep -qF '// quietly, unlike checkWalkthrough:' <<<"$(block "$ROOT/workflows/profile-feature.js")" \
    || { echo "the block does not say why it swallows a failed dispatch"; return 1; }
}
