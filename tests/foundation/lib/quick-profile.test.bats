#!/usr/bin/env bats
# The QUICK profile driven through its script with stubbed agents: one Edit behind an entry check,
# then Validation, Review and Done, and nothing at all when the check fails.

setup() {
  ROOT="$(cd -- "$(dirname -- "$BATS_TEST_FILENAME")/../../.." && pwd)"
  AGENTS='{"architect":"a","developer":"d","tester":"t","reviewer":"r","refactorer":"f","validator":"v","security":"—","diagnostics":"g","init":"—"}'
  RANGES='{"since": "base", "repos": {".": {"range": "c3..HEAD", "commits": 1, "state": "ok"}}}'
  EDITED='"edit": {"ok": true, "phase_id": "1", "committed": true, "summary": "s"}'
  PASSED='"validation": {"validation_status": "PASSED", "artifact_path": "v", "summary": "s", "driver_status": "ok"}'
  APPROVED='"review": {"review_status": "APPROVED", "artifact_path": "r", "summary": "s"}'
  DONE='"done": {"ok": true, "artifact_path": "d", "summary": "s", "closed_findings": []}'
}

contract() { # $1 extra JSON members (leading comma)
  printf '{"task_id": "001", "task_dir": "/p/Tasks/ACTIVE/001-x", "plugin_root": "/core", "lang": "en", "agents": %s, "start_stage": "Edit", "stage_scope": "forward", "scale": "lite", "walkthrough": "off", "need_test": false, "review_ranges": %s%s}' "$AGENTS" "$RANGES" "$1"
}

run_quick() { node "$ROOT/tests/foundation/helpers/run-profile.js" "$ROOT/workflows/profile-quick.js" "$1" "$2"; }

pick() { node -e 'const o = JSON.parse(require("fs").readFileSync(0, "utf8")); const v = eval(process.argv[1]); console.log(typeof v === "string" ? v : JSON.stringify(v))' "$1"; }

labels() { pick 'o.calls.map((c) => c.label).join(" ")'; }

prompt_of() { pick "(o.calls.find((c) => c.label === '$1') || {}).prompt || ''"; }

@test "a QUICK run is one Edit, then Validation, Review and Done" {
  out="$(run_quick "$(contract '')" "{$EDITED, $PASSED, $APPROVED, $DONE}")"
  [ "$(labels <<<"$out")" = 'edit validation review done' ] || { labels <<<"$out"; return 1; }
  [ "$(pick 'o.result.next_recommended_action' <<<"$out")" = stop ] || { pick 'o.result' <<<"$out"; return 1; }
}

@test "the Edit brief carries the entry check, the one-phase plan and the commit" {
  e="$(run_quick "$(contract '')" "{$EDITED, $PASSED, $APPROVED, $DONE}" | prompt_of edit)"
  for f in 'at most two production files' 'no public API other code depends on' 'the security perimeter' 'nothing to investigate' \
           'return quick_escalation' 'Never shrink the change to make it fit' 'with a single phase' '**Verification:** line' \
           'phase-verification skill' '## Manual acceptance' 'Fully automatable.' 'commit once' 'Keep Plan.md to 200 lines' \
           'an earlier run made this check and wrote the phase'; do
    grep -qF -- "$f" <<<"$e" || { echo "the Edit brief lost: $f"; return 1; }
  done
}

@test "a failed entry check changes nothing and runs no later stage" {
  out="$(run_quick "$(contract '')" '{"edit": {"ok": false, "phase_id": "1", "committed": false, "summary": "s", "quick_escalation": {"reason": "three files"}}}')"
  [ "$(labels <<<"$out")" = edit ] || { labels <<<"$out"; return 1; }
  [ "$(pick 'o.result.next_recommended_action' <<<"$out")" = ask_user ] || { pick 'o.result' <<<"$out"; return 1; }
  [ "$(pick 'o.result.quick_escalation.reason' <<<"$out")" = 'three files' ] || { pick 'o.result' <<<"$out"; return 1; }
  [ "$(pick 'o.result.last_completed_stage' <<<"$out")" = null ] || { pick 'o.result' <<<"$out"; return 1; }
  pick 'o.result.notes' <<<"$out" | grep -qF 'Set [TASK_TYPE] in Task.md to BUG, FEATURE or REFACTOR' || { pick 'o.result' <<<"$out"; return 1; }
}

@test "an Edit that does not commit stops before Validation" {
  out="$(run_quick "$(contract '')" '{"edit": {"ok": false, "phase_id": "1", "committed": false, "summary": "the build is red"}}')"
  [ "$(labels <<<"$out")" = edit ] || { labels <<<"$out"; return 1; }
  [ "$(pick 'o.result.status' <<<"$out")" = interrupted ] || { pick 'o.result' <<<"$out"; return 1; }
}

@test "need_review=false runs no Review" {
  out="$(run_quick "$(contract ', "need_review": false')" "{$EDITED, $PASSED, $DONE}")"
  [ "$(labels <<<"$out")" = 'edit validation done' ] || { labels <<<"$out"; return 1; }
}

@test "need_test=true asks Edit for the test in the same commit" {
  e="$(run_quick "$(contract ', "need_test": true')" "{$EDITED, $PASSED, $APPROVED, $DONE}" | prompt_of edit)"
  grep -qF 'write it in the same phase by applying the spine-toolkit:test-authoring skill' <<<"$e" || { echo "$e"; return 1; }
  e="$(run_quick "$(contract '')" "{$EDITED, $PASSED, $APPROVED, $DONE}" | prompt_of edit)"
  if grep -qF 'write it in the same phase' <<<"$e"; then echo "need_test=false still asked for a test"; return 1; fi
}

@test "Validation has no replay to ask for, and a failed one stops the run" {
  v="$(run_quick "$(contract '')" "{$EDITED, $PASSED, $APPROVED, $DONE}" | prompt_of validation)"
  grep -qF 'There is no reproduction scenario to replay' <<<"$v" || { echo "$v"; return 1; }
  out="$(run_quick "$(contract '')" "{$EDITED, \"validation\": {\"validation_status\": \"FAILED\", \"artifact_path\": \"v\", \"summary\": \"s\"}}")"
  [ "$(labels <<<"$out")" = 'edit validation' ] || { labels <<<"$out"; return 1; }
}

@test "Review holds the change to the QUICK bar and the perimeter" {
  r="$(run_quick "$(contract '')" "{$EDITED, $PASSED, $APPROVED, $DONE}" | prompt_of review)"
  for f in 'is it still a QUICK change' 'a diff that touches the perimeter anyway is a blocking finding' 'c3..HEAD' '--kind reviewed' '## For Done'; do
    grep -qF -- "$f" <<<"$r" || { echo "the Review brief lost: $f"; return 1; }
  done
}

@test "fix-review runs one fix phase in Edit, never the entry check" {
  out="$(run_quick "$(contract ', "action": "fix-review", "fix_findings": ["a typo in the key"], "fix_round": 1')" "{\"edit:R1\": {\"ok\": true, \"phase_id\": \"R1\", \"committed\": true, \"summary\": \"s\"}, $PASSED, $APPROVED, $DONE}")"
  [ "$(labels <<<"$out")" = 'edit:R1 validation review done' ] || { labels <<<"$out"; return 1; }
  prompt_of edit:R1 <<<"$out" | grep -qF 'a typo in the key' || { echo "the fix phase lost its finding"; return 1; }
}

@test "catch-up validates, reviews and closes only the delta" {
  out="$(run_quick "$(contract ', "action": "catch-up", "start_stage": "Validation"' | sed 's/"start_stage": "Edit", //')" "{$PASSED, $APPROVED, $DONE}")"
  [ "$(labels <<<"$out")" = 'validation review done' ] || { labels <<<"$out"; return 1; }
  prompt_of done <<<"$out" | grep -qF 'Catch-up: commits after Done' || { echo "Done lost the catch-up phase"; return 1; }
}

@test "Method B carries the same entry check and the same way out" {
  s="$ROOT/skills/workflow-quick/SKILL.md"
  for f in 'the change touches at most two production files' 'it changes no public API other code depends on' 'the security perimeter' \
           'returns `quick_escalation: {reason}`' 'Under `fix-review` it runs the single "Review fixes <n>" phase built from `fix_findings` instead' \
           'Does NOT change `[TASK_TYPE]` when the entry check fails'; do
    grep -qF -- "$f" "$s" || { echo "workflow-quick lost: $f"; return 1; }
  done
}
