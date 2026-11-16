#!/usr/bin/env bats
# Under manual_checks_pass=end an epic walks the cases its steps left in one collective pass: the
# Acceptance stage after the walk of the steps, then a Done that reads the marks back, turns each
# FAIL into a bug step, and only then writes the report. Under per-step none of it exists.

setup() {
  ROOT="$(cd -- "$(dirname -- "$BATS_TEST_FILENAME")/../../.." && pwd)"
  AGENTS='{"architect":"a","developer":"d","tester":"t","reviewer":"r","refactorer":"f","validator":"v","security":"—","diagnostics":"g","init":"—"}'
  DIR='/p/Tasks/ACTIVE/050-e'
  DONE_STEPS='"execute:read-steps": {"ok": true, "branch": "decomposition", "steps": [{"step_id": "01-a.step", "task_id": "050.1", "task_type": "FEATURE", "status": "DONE"}, {"step_id": "02-b.step", "task_id": "050.2", "task_type": "BUG", "status": "DONE"}]}'
  BRANCH='"done:read-branch": {"branch": "decomposition"}'
  PERSON='"acceptance": {"validation_status": "PASSED", "artifact_path": "'"$DIR"'/Validation.md", "manual_checks_path": "'"$DIR"'/ManualChecks.md", "manual_checks": ["01/MC-1", "02/MC-3"], "manual_checks_changed": true, "agent_verdicts": 2, "summary": "s"}'
  NOBODY='"acceptance": {"validation_status": "PASSED", "artifact_path": "'"$DIR"'/Validation.md", "manual_checks": [], "agent_verdicts": 0, "summary": "s"}'
}

# contract <start_stage> <pass>: a forward run of the epic from that stage, under that pass.
contract() {
  local pass=''
  [ -n "$2" ] && pass=', "manual_checks_pass": "'"$2"'"'
  echo '{"task_id": "050", "task_dir": "'"$DIR"'", "plugin_root": "/core", "lang": "en", "mode": "auto", "agents": '"$AGENTS"', "start_stage": "'"$1"'", "stage_scope": "forward"'"$pass"'}'
}

run_epic() { node "$ROOT/tests/foundation/helpers/run-profile.js" "$ROOT/workflows/profile-epic.js" "$(contract "$1" "$2")" "{$3}"; }

# check <output> <js expression over o (the run) and r (its result)>: fails with the run printed.
check() {
  node -e 'const o = JSON.parse(process.argv[1]); const r = o.result; const has = (l) => o.calls.some((c) => c.label === l); const call = (l) => o.calls.find((c) => c.label === l)
    if (!(eval(process.argv[2]))) { console.log(JSON.stringify(o, null, 1)); process.exit(1) }' "$1" "$2"
}

@test "per-step: neither the Acceptance stage nor the marks reader is dispatched" {
  out="$(run_epic Execute '' "$DONE_STEPS, $PERSON")"
  check "$out" '!has("acceptance") && !has("done:acceptance-marks") && !has("done:bug-steps") && has("done")'
}

@test "end on the pure_research branch: no Acceptance" {
  out="$(run_epic Execute end '"execute:read-steps": {"ok": true, "branch": "pure_research", "steps": []}, '"$PERSON")"
  check "$out" '!has("acceptance") && !has("done:acceptance-marks") && has("done")'
}

@test "end with cases for a person: the pass file is checked and the run stops for the person" {
  out="$(run_epic Execute end "$DONE_STEPS, $PERSON")"
  check "$out" 'has("acceptance") && call("manual-checks:check").prompt.includes("'"$DIR"'/ManualChecks.md") && r.next_recommended_action === "ask_user" && r.last_completed_stage === "Acceptance" && !has("done") && !has("done:acceptance-marks") && r.notes.includes("'"$DIR"'/ManualChecks.md") && r.notes.includes("**Result:**") && r.notes.includes("01/MC-1")'
}

@test "end: the Acceptance brief collects, walks through the driver, records verdicts and writes the pass" {
  out="$(run_epic Acceptance end "$PERSON")"
  check "$out" 'o.calls[0].label === "acceptance" && ["manual-checks-pass.sh\" collect '"$DIR"'", "manual checks: none — no step left a case", "[VALIDATION_STATUS] = PASSED", "**Runner:** agent", "## Agent verdicts", "| Case | Mark | Evidence |", "## Collective pass", "lint-manual-checks.sh", "Four things can suspend it"].every((t) => call("acceptance").prompt.includes(t))'
}

@test "the four reasons a driver stops read the same in the Acceptance brief as in Validation" {
  out="$(run_epic Acceptance end "$PERSON")"
  para="$(node -e 'const s = require("fs").readFileSync(process.argv[1], "utf8"); const i = s.indexOf("Four things can suspend it"); const j = s.indexOf("means for the user.", i); process.stdout.write(i < 0 || j < 0 ? "" : s.slice(i, j))' "$ROOT/workflow-src/prelude.js")"
  [ -n "$para" ] || { echo "the paragraph is not in the prelude"; return 1; }
  for p in feature refactor; do
    grep -qF 'Four things can suspend it' "$ROOT/workflows/profile-$p.js" && ! grep -qF '${DRIVER_STOPS}' "$ROOT/workflows/profile-$p.js" \
      && { echo "profile-$p.js keeps its own copy of the paragraph"; return 1; }
    grep -qF '${DRIVER_STOPS}' "$ROOT/workflows/profile-$p.js" || { echo "profile-$p.js lost the paragraph"; return 1; }
  done
  check "$out" 'call("acceptance").prompt.includes("drive_app resolving to off") && call("acceptance").prompt.includes("comes back in driver_status")'
}

@test "end with no case left for a person: the stage goes on into Done" {
  out="$(run_epic Execute end "$DONE_STEPS, $NOBODY, \"done:acceptance-marks\": {\"pass_file\": false, \"unmarked\": [], \"fails\": [], \"counts\": {}}")"
  check "$out" 'has("acceptance") && !has("manual-checks:check") && has("done:acceptance-marks") && has("done") && r.last_completed_stage === "Done"'
}

@test "Done with unmarked cases stops for the person and names them" {
  out="$(run_epic Done end "$BRANCH, \"done:acceptance-marks\": {\"pass_file\": true, \"unmarked\": [\"01/MC-2\", \"02/MC-3\"], \"fails\": [], \"counts\": {}}")"
  check "$out" 'has("done:acceptance-marks") && r.next_recommended_action === "ask_user" && r.notes.includes("01/MC-2, 02/MC-3") && !has("done:bug-steps") && !has("done") && !has("acceptance")'
}

@test "Done stops when the marks could not be written back" {
  out="$(run_epic Done end "$BRANCH, \"done:acceptance-marks\": {\"pass_file\": true, \"unmarked\": [], \"fails\": [], \"counts\": {\"PASS\": 2}, \"writeback\": \"writeback: no place for: 01/MC-9\"}")"
  check "$out" 'r.next_recommended_action === "ask_user" && r.notes.includes("writeback: no place for: 01/MC-9") && !has("done")'
}

@test "Done with a FAIL that has no bug step yet creates one and hands it back as pending" {
  out="$(run_epic Done end "$BRANCH, \"done:acceptance-marks\": {\"pass_file\": true, \"unmarked\": [], \"fails\": [{\"case\": \"02/MC-1\", \"reason\": \"the list stays empty\", \"bug_step\": null}], \"counts\": {\"PASS\": 3, \"FAIL\": 1}, \"writeback\": \"writeback: 4 mark(s) in 2 file(s)\"}, \"done:bug-steps\": {\"ok\": true, \"branch\": \"decomposition\", \"steps\": [{\"step_id\": \"03-fix.step\", \"task_id\": \"050.3\", \"task_type\": \"BUG\", \"status\": \"PENDING\"}]}")"
  check "$out" 'has("done:bug-steps") && ["02/MC-1", "the list stays empty", "[TASK_TYPE] = BUG", "[MANUAL_CHECKS_PASS] = per-step", "Plan.md"].every((t) => call("done:bug-steps").prompt.includes(t)) && r.pending_steps.map((s) => s.step_id).join() === "03-fix.step" && r.pending_steps[0].profile === "BUG" && r.next_recommended_action === "continue" && !has("done")'
}

@test "Done with a FAIL whose bug step exists writes the report with a Manual acceptance section" {
  out="$(run_epic Done end "$BRANCH, \"done:acceptance-marks\": {\"pass_file\": true, \"unmarked\": [], \"fails\": [{\"case\": \"02/MC-1\", \"reason\": \"the list stays empty\", \"bug_step\": \"03-fix.step\"}], \"counts\": {\"PASS\": 3, \"FAIL\": 1, \"BLOCKED\": 0, \"DROPPED\": 1}, \"writeback\": \"writeback: 0 mark(s) in 0 file(s)\"}")"
  check "$out" '!has("done:bug-steps") && has("done") && ["## Manual acceptance", "PASS 3", "FAIL 1", "BLOCKED 0", "DROPPED 1", "03-fix.step", "OS version"].every((t) => call("done").prompt.includes(t)) && r.next_recommended_action === "stop"'
}

@test "Done without a pass file reports as before" {
  out="$(run_epic Done end "$BRANCH, \"done:acceptance-marks\": {\"pass_file\": false, \"unmarked\": [], \"fails\": [], \"counts\": {}}")"
  check "$out" 'has("done") && !call("done").prompt.includes("## Manual acceptance") && !has("done:bug-steps")'
}

@test "Method B and the orchestrator know the Acceptance stage" {
  skill="$ROOT/skills/workflow-epic/SKILL.md"
  grep -qF 'Research → Plan → Execute → Acceptance → Done' "$skill" || { echo "workflow-epic does not order the stages with Acceptance"; return 1; }
  grep -qE '^- \*\*Acceptance\*\* — `\[validator\]`' "$skill" || { echo "workflow-epic has no Acceptance stage owned by the validator"; return 1; }
  grep -qF 'done:bug-steps' "$ROOT/workflows/profile-epic.js"
  orch="$ROOT/skills/orchestrator/SKILL.md"
  grep -qF 'every step is done, `manual_checks_pass` is `end` and the epic folder holds no `Validation.md` → `Acceptance`' "$orch" \
    || { echo "State Detection does not route an epic to Acceptance"; return 1; }
  grep -qF 'Research → Plan → Execute → Acceptance → Done' "$ROOT/README.md" || { echo "README's EPIC row lacks Acceptance"; return 1; }
}
