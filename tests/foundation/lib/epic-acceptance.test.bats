#!/usr/bin/env bats
# changed: sweep
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

@test "end: the Acceptance brief says every collected case is copied whole as its own case and never merged" {
  out="$(run_epic Acceptance end "$PERSON")"
  check "$out" '["ase collect lists is copied whole as its own #### <step>/MC-<n>. with its own **Result:** token", "two cases are never merged into one, not even when they differ only in conditions or device", "a case for another device goes into that device\u0027s session"].every((t) => call("acceptance").prompt.includes(t))'
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

@test "the Done stop on unmarked cases says a case may be missing from the pass file and how to mark it" {
  out="$(run_epic Done end "$BRANCH, \"done:acceptance-marks\": {\"pass_file\": true, \"unmarked\": [\"02/MC-3\"], \"fails\": [], \"counts\": {}}")"
  check "$out" 'r.next_recommended_action === "ask_user" && r.notes.includes("02/MC-3") && r.notes.includes("may be missing from the pass file") && r.notes.includes("<step>/MC-<n> <MARK>") && r.notes.includes("'"$DIR"'/ManualChecks.md") && r.notes.includes("**Result:**") && r.notes.includes("its own file")'
}

@test "Done with no pass file blames no pass file: the cases were never walked, run Acceptance or mark them in their step files" {
  out="$(run_epic Done end "$BRANCH, \"done:acceptance-marks\": {\"pass_file\": false, \"marks\": [], \"unmarked\": [\"01/MC-1\", \"02/MC-3\"], \"fails\": [], \"counts\": {}}")"
  check "$out" 'r.next_recommended_action === "ask_user" && r.notes.includes("01/MC-1, 02/MC-3") && r.notes.includes("never walked") && r.notes.includes("un the Acceptance stage, or mark them in their step files") && !r.notes.includes("pass file '"$DIR"'/ManualChecks.md") && !r.notes.includes("**Result:**")'
}

@test "the marks reader brief returns pass_file, marks and unmarked as printed, with a pass file or without" {
  out="$(run_epic Done end "$BRANCH, \"done:acceptance-marks\": {\"pass_file\": false, \"marks\": [], \"unmarked\": [\"01/MC-1\"], \"fails\": [], \"counts\": {}}")"
  check "$out" 'has("done:acceptance-marks") && !call("done:acceptance-marks").prompt.includes("everything else empty") && !call("done:acceptance-marks").prompt.includes("marks is empty and unmarked is empty") && call("done:acceptance-marks").prompt.includes("pass_file, marks and unmarked exactly as it printed them") && call("done:acceptance-marks").prompt.includes("with no pass file") && call("done:acceptance-marks").prompt.includes("the collected cases that have no verdict")'
}

@test "Done with no pass file and no agent mark but a collected case left unmarked stops, too" {
  out="$(run_epic Done end "$BRANCH, \"done:acceptance-marks\": {\"pass_file\": false, \"marks\": [], \"unmarked\": [\"01/MC-1\"], \"fails\": [], \"counts\": {}}")"
  check "$out" 'r.next_recommended_action === "ask_user" && r.notes.includes("01/MC-1") && !has("done:bug-steps") && !has("done")'
}

@test "Done stops when the marks could not be written back" {
  out="$(run_epic Done end "$BRANCH, \"done:acceptance-marks\": {\"pass_file\": true, \"unmarked\": [], \"fails\": [], \"counts\": {\"PASS\": 2}, \"writeback\": \"writeback: no place for: 01/MC-9\"}")"
  check "$out" 'r.next_recommended_action === "ask_user" && r.notes.includes("writeback: no place for: 01/MC-9") && !has("done")'
}

@test "Done with a FAIL that has no bug step yet creates one and hands it back as pending" {
  out="$(run_epic Done end "$BRANCH, \"done:acceptance-marks\": {\"pass_file\": true, \"unmarked\": [], \"fails\": [{\"case\": \"02/MC-1\", \"reason\": \"the list stays empty\", \"bug_step\": null}], \"counts\": {\"PASS\": 3, \"FAIL\": 1}, \"writeback\": \"writeback: 4 mark(s) in 2 file(s)\"}, \"done:bug-steps\": {\"ok\": true, \"branch\": \"decomposition\", \"steps\": [{\"step_id\": \"03-fix.step\", \"task_id\": \"050.3\", \"task_type\": \"BUG\", \"status\": \"PENDING\"}]}")"
  check "$out" 'has("done:bug-steps") && call("done:bug-steps").prompt.includes("a person\u0027s mark: copy it whole from '"$DIR"'/ManualChecks.md") && ["02/MC-1", "the list stays empty", "[TASK_TYPE] = BUG", "[MANUAL_CHECKS_PASS] = per-step", "Plan.md"].every((t) => call("done:bug-steps").prompt.includes(t)) && r.pending_steps.map((s) => s.step_id).join() === "03-fix.step" && r.pending_steps[0].profile === "BUG" && r.next_recommended_action === "continue" && !has("done")'
}

@test "Done with a FAIL whose bug step exists writes the report with a Manual acceptance section" {
  out="$(run_epic Done end "$BRANCH, \"done:acceptance-marks\": {\"pass_file\": true, \"unmarked\": [], \"fails\": [{\"case\": \"02/MC-1\", \"reason\": \"the list stays empty\", \"bug_step\": \"03-fix.step\"}], \"counts\": {\"PASS\": 3, \"FAIL\": 1, \"BLOCKED\": 0, \"DROPPED\": 1}, \"writeback\": \"writeback: 0 mark(s) in 0 file(s)\"}")"
  check "$out" '!has("done:bug-steps") && has("done") && ["## Manual acceptance", "PASS 3", "FAIL 1", "BLOCKED 0", "DROPPED 1", "03-fix.step", "OS version"].every((t) => call("done").prompt.includes(t)) && r.next_recommended_action === "stop"'
}

@test "Done with agent marks only and no pass file reports the devices from Validation.md, with no sessions" {
  out="$(run_epic Done end "$BRANCH, \"done:acceptance-marks\": {\"pass_file\": false, \"marks\": [{\"case\": \"01/MC-1\", \"mark\": \"PASS\", \"reason\": null, \"by\": \"agent\"}], \"unmarked\": [], \"fails\": [], \"counts\": {\"PASS\": 1}, \"writeback\": \"writeback: 1 mark(s) in 1 file(s)\"}")"
  check "$out" '!has("done:bug-steps") && has("done") && call("done").prompt.includes("## Manual acceptance") && call("done").prompt.includes("**Device:** lines of '"$DIR"'/Validation.md") && !call("done").prompt.includes("sessions") && !call("done").prompt.includes("on the collective pass '"$DIR"'/ManualChecks.md") && call("done").prompt.includes("PASS 1")'
}

@test "Done without a pass file reports as before" {
  out="$(run_epic Done end "$BRANCH, \"done:acceptance-marks\": {\"pass_file\": false, \"unmarked\": [], \"fails\": [], \"counts\": {}}")"
  check "$out" 'has("done") && !call("done").prompt.includes("## Manual acceptance") && !has("done:bug-steps")'
}

@test "end: Acceptance that returns a status other than PASSED stops for the user, and Done is not run" {
  out="$(run_epic Execute end "$DONE_STEPS, \"acceptance\": {\"validation_status\": \"FAILED\", \"artifact_path\": \"$DIR/Validation.md\", \"manual_checks\": [], \"agent_verdicts\": 0, \"summary\": \"the app did not launch\"}")"
  check "$out" 'has("acceptance") && r.next_recommended_action === "ask_user" && r.validation_status === "FAILED" && r.last_completed_stage === "Acceptance" && !has("done:acceptance-marks") && !has("done")'
}

@test "end: no validator on the platform hands the Acceptance stage back" {
  AGENTS='{"architect":"a","developer":"d","tester":"t","reviewer":"r","refactorer":"f","validator":"\u2014","security":"\u2014","diagnostics":"g","init":"\u2014"}'
  out="$(run_epic Execute end "$DONE_STEPS, $PERSON")"
  check "$out" '!has("acceptance") && r.next_recommended_action === "ask_user" && r.handback && r.handback.stage === "Acceptance" && r.handback.role === "validator" && !has("done")'
}

@test "Done with no pass file but an agent FAIL creates the bug step and hands it back as pending" {
  out="$(run_epic Done end "$BRANCH, \"done:acceptance-marks\": {\"pass_file\": false, \"marks\": [{\"case\": \"01/MC-1\", \"mark\": \"PASS\", \"reason\": null, \"by\": \"agent\"}, {\"case\": \"01/MC-2\", \"mark\": \"FAIL\", \"reason\": \"the total stays 0.00\", \"by\": \"agent\"}], \"unmarked\": [], \"fails\": [{\"case\": \"01/MC-2\", \"reason\": \"the total stays 0.00\", \"bug_step\": null}], \"counts\": {\"PASS\": 1, \"FAIL\": 1}, \"writeback\": \"writeback: 2 mark(s) in 1 file(s)\"}, \"done:bug-steps\": {\"ok\": true, \"branch\": \"decomposition\", \"steps\": [{\"step_id\": \"03-fix.step\", \"task_id\": \"050.3\", \"task_type\": \"BUG\", \"status\": \"PENDING\"}]}")"
  check "$out" 'has("done:bug-steps") && call("done:bug-steps").prompt.includes("01/MC-2") && call("done:bug-steps").prompt.includes("an agent\u0027s mark: copy case MC-2 whole from the step\u0027s own ManualChecks.md, the one in the .step folder of step 01") && !call("done:bug-steps").prompt.includes("copied from '"$DIR"'/ManualChecks.md") && r.pending_steps.map((s) => s.step_id).join() === "03-fix.step" && r.next_recommended_action === "continue" && !has("done") && !call("done:acceptance-marks").prompt.includes("When pass_file is false, return it with everything else empty")'
}

@test "end: a forward run after the pass keeps Validation.md, skips the check and goes on into Done" {
  out="$(run_epic Execute end "$DONE_STEPS, \"acceptance\": {\"already_passed\": true, \"validation_status\": \"PASSED\", \"artifact_path\": \"$DIR/Validation.md\", \"manual_checks\": [], \"agent_verdicts\": 0, \"summary\": \"s\"}, \"done:acceptance-marks\": {\"pass_file\": false, \"unmarked\": [], \"fails\": [], \"counts\": {}}")"
  check "$out" 'has("acceptance") && ["[VALIDATION_STATUS]", "already_passed"].every((t) => call("acceptance").prompt.includes(t)) && !has("manual-checks:check") && has("done") && r.notes.includes("Acceptance already ran; Validation.md kept") && r.stages.some((s) => s.stage === "Acceptance") && r.last_completed_stage === "Done"'
}

@test "end: only a PASSED earlier pass is kept; after a FAILED one the stage runs as a fresh pass" {
  out="$(run_epic Execute end "$DONE_STEPS, \"acceptance\": {\"already_passed\": false, \"validation_status\": \"PASSED\", \"artifact_path\": \"$DIR/Validation.md\", \"manual_checks_path\": \"$DIR/ManualChecks.md\", \"manual_checks\": [\"01/MC-1\"], \"manual_checks_changed\": true, \"agent_verdicts\": 1, \"summary\": \"s\"}")"
  check "$out" 'call("acceptance").prompt.includes("already carries the line [VALIDATION_STATUS] = PASSED") && call("acceptance").prompt.includes("A status FAILED or FLAKY there means the earlier pass did not complete") && has("manual-checks:check") && r.next_recommended_action === "ask_user" && r.last_completed_stage === "Acceptance" && !r.notes.includes("Acceptance already ran") && !has("done")'
}

@test "Method B and the manual-checks skill say a collected case is copied whole and never merged" {
  grep -qF 'never merged' "$ROOT/skills/workflow-epic/SKILL.md" || { echo "workflow-epic does not say that cases are never merged"; return 1; }
  grep -qF 'never merged' "$ROOT/skills/manual-checks/SKILL.md" || { echo "manual-checks ## Collective pass does not say that cases are never merged"; return 1; }
  grep -qF 'may be missing from the pass file' "$ROOT/skills/workflow-epic/SKILL.md" || { echo "workflow-epic does not say that an unmarked case may be missing from the pass file"; return 1; }
}

@test "Method B and the orchestrator know the Acceptance stage" {
  skill="$ROOT/skills/workflow-epic/SKILL.md"
  grep -qF 'Research → Plan → Execute → Acceptance → Done' "$skill" || { echo "workflow-epic does not order the stages with Acceptance"; return 1; }
  grep -qE '^- \*\*Acceptance\*\* — `\[validator\]`' "$skill" || { echo "workflow-epic has no Acceptance stage owned by the validator"; return 1; }
  grep -qF 'bug step' "$skill" && grep -qF '[MANUAL_CHECKS_PASS] = per-step' "$skill" \
    || { echo "workflow-epic does not say that Done turns a FAIL into a per-step bug step"; return 1; }
  grep -qF "an agent's mark from the step's own \`ManualChecks.md\`" "$skill" \
    || { echo "workflow-epic does not say where the case of an agent's FAIL is copied from"; return 1; }
  grep -qF 'When the stage'"'"'s own status is `FAILED` or `FLAKY`, return `next_recommended_action=ask_user` with `last_completed_stage=Acceptance` and do not run Done' "$skill" \
    || { echo "workflow-epic does not stop for the user, with no Done, on a FAILED or FLAKY Acceptance"; return 1; }
  orch="$ROOT/skills/orchestrator/SKILL.md"
  grep -qF 'every step is done, `manual_checks_pass` is `end` and the epic folder holds no `Validation.md` whose status line is `[VALIDATION_STATUS] = PASSED` → `Acceptance`' "$orch" \
    || { echo "State Detection does not route an epic to Acceptance"; return 1; }
  grep -qF "re-dispatch the epic by State Detection item 4's rule, applied directly" "$orch" \
    || { echo "the pending_steps re-dispatch does not say it bypasses the unticked Plan.md rows"; return 1; }
  grep -qF 'Research → Plan → Execute → Acceptance → Done' "$ROOT/README.md" || { echo "README's EPIC row lacks Acceptance"; return 1; }
}
