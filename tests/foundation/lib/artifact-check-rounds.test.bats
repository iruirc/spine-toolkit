#!/usr/bin/env bats
# The fresh-reader check of Plan.md and Done.md (artifact_check): one read by a new agent of the
# writer's role, then at most one revision, never a second read. Driven through the scripts with
# stubbed agents, so a loop that drifts from artifact-reader's ## Check fails here. The shared block
# is pinned byte-equal across the seven scripts that write either file, so a hand edit to one copy
# goes red.

setup() {
  ROOT="$(cd -- "$(dirname -- "$BATS_TEST_FILENAME")/../../.." && pwd)"
  SEVEN="feature bug refactor test quick epic research"
  PLANNERS="feature bug refactor test"
  AGENTS='{"architect":"a","developer":"d","tester":"t","reviewer":"r","refactorer":"f","validator":"v","security":"—","diagnostics":"g","init":"—"}'
  REVISED='"artifact:revise": {"artifact_path": "x", "changed": true}'
  DECOMPOSED='"plan": {"ok": true, "artifact_path": "p", "summary": "s", "branch": "decomposition", "steps": []}'
  LINT='Last, run scripts/lint-artifact-readability.sh on the file once; fix each finding once and name what is left in the stage summary.'
  METHOD_B="dispatch a fresh agent of the writer's role to read the file only, per \`artifact-reader\` → \`## Check\`, then revise once"
}

# The shared block of one script, between its two markers.
block() {
  awk '/^\/\/ ── artifact check ─/ { f = 1 } f { print } /^\/\/ ── end artifact check ─/ { exit }' "$1"
}

# $1 profile, $2 start stage, $3 artifact_check ("" leaves the field out), $4 extra contract members.
contract() {
  local check=''
  [ -n "$3" ] && check=", \"artifact_check\": \"$3\""
  printf '{"task_id": "001", "task_dir": "/p/Tasks/ACTIVE/001-x", "plugin_root": "/core", "lang": "en", "agents": %s, "start_stage": "%s", "end_stage": "%s", "stage_scope": "forward", "walkthrough": "off"%s%s}' \
    "$AGENTS" "$2" "$2" "$check" "${4:-}"
}

# $1 profile, $2 stage (Plan or Done), $3 artifact_check, $4 replies members, $5 extra contract members.
run_stage() {
  local replies="$4"
  [ "$1" = epic ] && [ "$2" = Plan ] && replies="$DECOMPOSED${replies:+, $replies}"
  node "$ROOT/tests/foundation/helpers/run-profile.js" "$ROOT/workflows/profile-$1.js" "$(contract "$1" "$2" "$3" "${5:-}")" "{$replies}"
}

pick() { node -e 'const o = JSON.parse(require("fs").readFileSync(0, "utf8")); const v = eval(process.argv[1]); console.log(typeof v === "string" ? v : JSON.stringify(v))' "$1"; }

# The stage's own dispatch and every artifact dispatch, each artifact one with its phase.
order() { pick "o.calls.filter((c) => ['plan', 'done'].includes(c.label) || c.label.startsWith('artifact')).map((c) => c.label.startsWith('artifact') ? c.label + '/' + c.phase : c.label).join(' ')"; }

notes() { pick 'o.result.notes'; }

# A read reply with $1 quoted places.
read_with() {
  node -e 'const n = +process.argv[1]; const kinds = ["reread", "undefined term", "identifier subject", "no reason", "no proof"]
    console.log(JSON.stringify({ retelling: ["r"], unclear: Array.from({ length: n }, (_, i) => ({ quote: "q" + i, missing: "m" + i, kind: kinds[i % 5] })) }))' "$1"
}

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

@test "every script still guards ARTIFACT_CHECK to on or off" {
  for p in $SEVEN review; do
    grep -qxF "const ARTIFACT_CHECK = A.artifact_check === 'on' ? 'on' : 'off'" "$ROOT/workflows/profile-$p.js" \
      || { echo "profile-$p.js: artifact_check is not guarded"; return 1; }
  done
}

@test "every call is guarded by ARTIFACT_CHECK, Plan in the four planners, Done in all seven" {
  for p in $SEVEN; do
    f="$ROOT/workflows/profile-$p.js"
    calls="$(grep -F 'await checkArtifact(' "$f")"
    ! grep -vF "ARTIFACT_CHECK === 'on'" <<<"$calls" | grep -q . || { echo "profile-$p.js: an unguarded call: $calls"; return 1; }
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
        out="$(run_stage "$p" "$s" "$c" "\"artifact:check\": $(read_with 3)")"
        ! grep -qF 'artifact:' <<<"$(order <<<"$out")" || { echo "profile-$p $s (artifact_check='$c'): $(order <<<"$out")"; return 1; }
      done
    done
  done
}

@test "on with nothing unclear: one read after Plan and one after Done, no revision" {
  for p in $SEVEN; do
    for s in $(stages_of "$p"); do
      out="$(run_stage "$p" "$s" on "\"artifact:check\": $(read_with 0)")"
      want="$(tr 'A-Z' 'a-z' <<<"$s") artifact:check/$s"
      [ "$(order <<<"$out")" = "$want" ] || { echo "profile-$p $s: dispatched $(order <<<"$out")"; return 1; }
      grep -qF "$s.md check: nothing unclear." <<<"$(notes <<<"$out")" || { echo "profile-$p $s: no note"; return 1; }
    done
  done
}

@test "one, three and six unclear places get exactly one revision and no second read" {
  for n in 1 3 6; do
    for p in $SEVEN; do
      for s in $(stages_of "$p"); do
        out="$(run_stage "$p" "$s" on "\"artifact:check\": $(read_with "$n"), $REVISED")"
        want="$(tr 'A-Z' 'a-z' <<<"$s") artifact:check/$s artifact:revise/$s"
        [ "$(order <<<"$out")" = "$want" ] || { echo "profile-$p $s, $n place(s): dispatched $(order <<<"$out")"; return 1; }
        grep -qF "$s.md check: $n place(s), revised." <<<"$(notes <<<"$out")" || { echo "profile-$p $s: no note: $(notes <<<"$out")"; return 1; }
      done
    done
  done
}

@test "a read that returns nothing, or throws, ends the check quietly and the run goes on" {
  for p in $SEVEN; do
    for s in $(stages_of "$p"); do
      for reply in null '{"__throw": "dispatch failed"}'; do
        out="$(run_stage "$p" "$s" on "\"artifact:check\": $reply")"
        [ "$(order <<<"$out")" = "$(tr 'A-Z' 'a-z' <<<"$s") artifact:check/$s" ] || { echo "profile-$p $s: dispatched $(order <<<"$out")"; return 1; }
        grep -qF "$s.md check: the reader returned nothing, so the file went unchecked." <<<"$(notes <<<"$out")" \
          || { echo "profile-$p $s: no note: $(notes <<<"$out")"; return 1; }
        [ "$(pick 'o.result.last_completed_stage' <<<"$out")" = "$s" ] || { echo "profile-$p $s: the run stopped: $out"; return 1; }
        [ "$(pick 'o.result.status' <<<"$out")" != error ] || { echo "profile-$p $s: the run errored: $out"; return 1; }
      done
    done
  done
}

@test "an unclear entry without a quote is skipped, and all of them quote-less is nothing to revise" {
  bare='{"retelling": ["r"], "unclear": [{"missing": "m-none", "kind": "reread"}, {"quote": "  ", "missing": "m-blank", "kind": "no proof"}]}'
  mixed='{"retelling": ["r"], "unclear": [{"quote": "q-one", "missing": "m-one", "kind": "no reason"}, {"missing": "m-none", "kind": "reread"}, {"quote": "q-two", "missing": "m-two", "kind": "undefined term"}]}'
  for p in $SEVEN; do
    for s in $(stages_of "$p"); do
      out="$(run_stage "$p" "$s" on "\"artifact:check\": $bare, $REVISED")"
      [ "$(order <<<"$out")" = "$(tr 'A-Z' 'a-z' <<<"$s") artifact:check/$s" ] || { echo "profile-$p $s: dispatched $(order <<<"$out")"; return 1; }
      grep -qF "$s.md check: nothing unclear." <<<"$(notes <<<"$out")" || { echo "profile-$p $s: $(notes <<<"$out")"; return 1; }
      grep -qF "$s.md check: 2 entry(ies) quoted no place, so they were skipped." <<<"$(notes <<<"$out")" || { echo "profile-$p $s: $(notes <<<"$out")"; return 1; }

      out="$(run_stage "$p" "$s" on "\"artifact:check\": $mixed, $REVISED")"
      [ "$(order <<<"$out")" = "$(tr 'A-Z' 'a-z' <<<"$s") artifact:check/$s artifact:revise/$s" ] || { echo "profile-$p $s: dispatched $(order <<<"$out")"; return 1; }
      grep -qF "$s.md check: 2 place(s), revised." <<<"$(notes <<<"$out")" || { echo "profile-$p $s: $(notes <<<"$out")"; return 1; }
      fix="$(pick "o.calls.find((c) => c.label === 'artifact:revise').prompt" <<<"$out")"
      grep -qF '"q-two" — m-two' <<<"$fix" || { echo "profile-$p $s: the revision does not carry a quoted place"; return 1; }
      ! grep -qF 'm-none' <<<"$fix" || { echo "profile-$p $s: the revision carries the quote-less entry"; return 1; }
    done
  done
}

@test "a revision that returns nothing or changes nothing is noted, never read again" {
  for p in $SEVEN; do
    s=Done
    out="$(run_stage "$p" "$s" on "\"artifact:check\": $(read_with 2), \"artifact:revise\": null")"
    [ "$(order <<<"$out")" = "done artifact:check/Done artifact:revise/Done" ] || { echo "profile-$p: dispatched $(order <<<"$out")"; return 1; }
    grep -qF 'Done.md check: 2 place(s); the revision returned nothing, so the file stands as written.' <<<"$(notes <<<"$out")" \
      || { echo "profile-$p: $(notes <<<"$out")"; return 1; }
    out="$(run_stage "$p" "$s" on "\"artifact:check\": $(read_with 2), \"artifact:revise\": {\"artifact_path\": \"x\", \"changed\": false}")"
    [ "$(order <<<"$out")" = "done artifact:check/Done artifact:revise/Done" ] || { echo "profile-$p: dispatched $(order <<<"$out")"; return 1; }
    grep -qF 'Done.md check: 2 place(s); the revision found nothing to change.' <<<"$(notes <<<"$out")" \
      || { echo "profile-$p: $(notes <<<"$out")"; return 1; }
  done
}

@test "the read prompt names the file, the owner who did not follow the task, and the five kinds" {
  for s in Plan Done; do
    out="$(run_stage feature "$s" on "\"artifact:check\": $(read_with 0)")"
    c="$(pick "o.calls.find((c) => c.label === 'artifact:check').prompt" <<<"$out")"
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
  out="$(run_stage feature Done on "\"artifact:check\": $(read_with 0)")"
  [ "$(pick "o.calls.find((c) => c.label === 'artifact:check').schema.properties.unclear.items.properties.kind.enum.join()" <<<"$out")" = 'reread,undefined term,identifier subject,no reason,no proof' ]
  [ "$(pick "o.calls.find((c) => c.label === 'artifact:check').schema.properties.unclear.items.required.join()" <<<"$out")" = 'quote,missing,kind' ]
}

@test "the read is tuned light on the writer's role; the revision takes the writing stage's tuning" {
  models=', "models": {"light": "haiku", "done": "sonnet", "architect": "opus", "developer": "opus", "tester": "opus", "refactorer": "opus"}, "effort": {"done": "max", "architect": "high", "developer": "high", "tester": "high", "refactorer": "high"}'
  for p in $SEVEN; do
    for s in $(stages_of "$p"); do
      out="$(run_stage "$p" "$s" on "\"artifact:check\": $(read_with 1), $REVISED" "$models")"
      [ "$(pick "o.calls.find((c) => c.label === 'artifact:check').model" <<<"$out")" = haiku ] || { echo "profile-$p $s: the read is not on the light model"; return 1; }
      [ "$(pick "o.calls.find((c) => c.label === 'artifact:check').effort" <<<"$out")" = high ] || { echo "profile-$p $s: the read is not at the role's effort"; return 1; }
      writer="$(pick "JSON.stringify([o.calls.find((c) => c.label === '$(tr 'A-Z' 'a-z' <<<"$s")').model, o.calls.find((c) => c.label === '$(tr 'A-Z' 'a-z' <<<"$s")').effort])" <<<"$out")"
      revise="$(pick "JSON.stringify([o.calls.find((c) => c.label === 'artifact:revise').model, o.calls.find((c) => c.label === 'artifact:revise').effort])" <<<"$out")"
      [ "$revise" = "$writer" ] || { echo "profile-$p $s: the revision is tuned $revise, the writer $writer"; return 1; }
    done
  done
}

@test "QUICK and RESEARCH check only Done.md" {
  for p in quick research; do
    out="$(run_stage "$p" Done on "\"artifact:check\": $(read_with 0)")"
    [ "$(order <<<"$out")" = 'done artifact:check/Done' ] || { echo "profile-$p: dispatched $(order <<<"$out")"; return 1; }
    ! grep -qF 'Plan.md' <<<"$(grep -F 'await checkArtifact(' "$ROOT/workflows/profile-$p.js")" || { echo "profile-$p.js checks Plan.md"; return 1; }
  done
}

@test "EPIC checks Plan.md only on the decomposition branch, and Done.md on both" {
  E="$ROOT/workflows/profile-epic.js"
  out="$(node "$ROOT/tests/foundation/helpers/run-profile.js" "$E" "$(contract epic Plan on)" "{\"plan\": {\"ok\": true, \"artifact_path\": \"p\", \"summary\": \"s\", \"branch\": \"pure_research\", \"steps\": []}, \"artifact:check\": $(read_with 0)}")"
  [ "$(order <<<"$out")" = 'plan' ] || { echo "pure research: dispatched $(order <<<"$out")"; return 1; }
  out="$(run_stage epic Plan on "\"artifact:check\": $(read_with 0)")"
  [ "$(order <<<"$out")" = 'plan artifact:check/Plan' ] || { echo "decomposition: dispatched $(order <<<"$out")"; return 1; }
  for b in decomposition pure_research; do
    out="$(run_stage epic Done on "\"done:read-branch\": {\"branch\": \"$b\"}, \"artifact:check\": $(read_with 0)")"
    [ "$(order <<<"$out")" = 'done artifact:check/Done' ] || { echo "$b Done: dispatched $(order <<<"$out")"; return 1; }
  done
}

@test "the five workflow skills carry the Method B check paragraph" {
  for s in bug feature refactor test quick; do
    S="$ROOT/skills/workflow-$s/SKILL.md"
    para="$(grep -F '`artifact_check`' "$S" | grep -F "$METHOD_B")"
    [ -n "$para" ] || { echo "workflow-$s: no Method B paragraph"; return 1; }
    for token in 'is `on`' 'never a second round' '`light`'; do
      grep -qF "$token" <<<"$para" || { echo "workflow-$s: the paragraph does not say $token"; return 1; }
    done
    if [ "$s" = quick ]; then
      grep -qF '`Done.md`' <<<"$para" || { echo "workflow-quick: the paragraph does not name Done.md"; return 1; }
    else
      grep -qF '`Plan.md` after Plan' <<<"$para" && grep -qF '`Done.md` after Done' <<<"$para" \
        || { echo "workflow-$s: the paragraph does not name both files"; return 1; }
    fi
  done
}

@test "every workflow skill runs the readability lint where its script does" {
  # One bullet per stage that writes a linted file, as the scripts' briefs do.
  for entry in 'feature:Research Plan Review Done' 'bug:Diagnose Plan Review Done' 'refactor:Analyze Plan Review Done' \
               'test:Analyze Plan Review Done' 'quick:Review Done' 'epic:Research Plan Done' 'research:Research Review Done' 'review:Review'; do
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

@test "the configuration reference says which files, one read and one revision, no second round" {
  ck="$(awk '/^### \[ARTIFACT_CHECK\]$/{f=1;next} /^### /{f=0} f' "$ROOT/docs/configuration.md")"
  for token in '`Plan.md` after Plan' '`Done.md` after Done' 'one read and at most one revision' 'no second round' 'decomposition'; do
    grep -qF "$token" <<<"$ck" || { echo "configuration.md does not say: $token"; return 1; }
  done
}
