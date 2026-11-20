#!/usr/bin/env bats
# changed: sweep workflows
# What the Validation gate lets through: PASSED and PASSED_WITH_FLAKES go on to Review in every
# ranged profile and in the epic, FAILED and FLAKY still stop — driven through the scripts with
# stubbed agents.

load "$(dirname "$BATS_TEST_FILENAME")/../helpers/run-profile-read"

setup() {
  ROOT="$(cd -- "$(dirname -- "$BATS_TEST_FILENAME")/../../.." && pwd)"
  RANGED="bug feature refactor test quick"
  AGENTS='{"architect":"a","developer":"d","tester":"t","reviewer":"r","refactorer":"f","validator":"v","security":"—","diagnostics":"g","init":"—"}'
  FLAKE='{"repository": ".", "module": "Core", "test": "CoreTests.testClock", "outcome": "flaky", "entry": "—"}'
  KNOWN='{"repository": ".", "module": "Core", "test": "CoreTests.testOld", "outcome": "known", "entry": "KF-1"}'
  FLAKES1='"outside_failures": ['"$FLAKE"']'
  FLAKES2='"outside_failures": ['"$FLAKE"', '"$FLAKE"', '"$KNOWN"']'
  APPROVED='{"review_status": "APPROVED", "artifact_path": "r", "summary": "s"}'
}

contract() { # $1 start stage
  printf '{"task_id": "001", "task_dir": "/p/Tasks/ACTIVE/001-x", "plugin_root": "/core", "lang": "en", "agents": %s, "start_stage": "%s", "stage_scope": "forward"}' "$AGENTS" "$1"
}

# validation_reply <status> <extra members, leading comma>
validation_reply() {
  printf '{"validation_status": "%s", "artifact_path": "v", "summary": "s", "reproduction_status": "fixed"%s}' "$1" "$2"
}

# gate <profile> <status> <extra members>: the labels dispatched and the notes of the run.
gate() {
  rp "$1" "$(contract Validation)" "{\"validation\": $(validation_reply "$2" "$3"), \"review\": $APPROVED}" \
    'o.calls.map((c) => c.label).join(" ")' 'o.result.notes' 'o.result.next_recommended_action'
}

@test "PASSED_WITH_FLAKES goes on to Review in every ranged profile" {
  for p in $RANGED; do
    gate "$p" PASSED_WITH_FLAKES ", $FLAKES1"
    grep -qw review <<<"${V[0]}" || { echo "profile-$p: Review did not run: ${V[0]}"; return 1; }
    grep -qF 'Validation passed with 1 flake(s) outside the task.' <<<"${V[1]}" || { echo "profile-$p: no flake note: ${V[1]}"; return 1; }
    if grep -qF 'Review and Done were not run' <<<"${V[1]}"; then echo "profile-$p: stopped: ${V[1]}"; return 1; fi
  done
}

@test "the flake note counts only the flaky rows of outside_failures" {
  for p in $RANGED; do
    gate "$p" PASSED_WITH_FLAKES ", $FLAKES2"
    grep -qF 'Validation passed with 2 flake(s) outside the task.' <<<"${V[1]}" || { echo "profile-$p: ${V[1]}"; return 1; }
  done
}

@test "a plain PASSED goes on to Review and carries no flake note" {
  for p in $RANGED; do
    gate "$p" PASSED ''
    grep -qw review <<<"${V[0]}" || { echo "profile-$p: Review did not run"; return 1; }
    if grep -qF 'flake(s)' <<<"${V[1]}"; then echo "profile-$p: a flake note on PASSED: ${V[1]}"; return 1; fi
  done
}

@test "FAILED and FLAKY still stop before Review" {
  for p in $RANGED; do
    for s in FAILED FLAKY; do
      gate "$p" "$s" ", $FLAKES1"
      if grep -qwE 'review|done' <<<"${V[0]}"; then echo "profile-$p: $s went on: ${V[0]}"; return 1; fi
      grep -qF "Validation returned $s" <<<"${V[1]}" || { echo "profile-$p: $s left no stop note: ${V[1]}"; return 1; }
      [ "${V[2]}" = ask_user ] || { echo "profile-$p: $s did not ask the user: ${V[2]}"; return 1; }
    done
  done
}

@test "a TEST run passes with flakes and stops on FLAKY, though both are unstable" {
  gate test PASSED_WITH_FLAKES ", $FLAKES1"
  grep -qw review <<<"${V[0]}" || { echo "PASSED_WITH_FLAKES stopped TEST: ${V[0]}"; return 1; }
  gate test FLAKY ''
  if grep -qw review <<<"${V[0]}"; then echo "FLAKY went on to Review"; return 1; fi
  grep -qF 'Validation returned FLAKY' <<<"${V[1]}" || { echo "${V[1]}"; return 1; }
}

@test "a BUG Validation with flakes still stops on a replay that did not pass" {
  rp bug "$(contract Validation)" "{\"validation\": $(validation_reply PASSED_WITH_FLAKES ", $FLAKES1" | sed 's/"fixed"/"still-reproduces"/'), \"review\": $APPROVED}" \
    'o.calls.map((c) => c.label).join(" ")' 'o.result.notes' 'o.result.next_recommended_action'
  if grep -qw review <<<"${V[0]}"; then echo "a replay that still reproduces went on: ${V[0]}"; return 1; fi
  grep -qF 'reproduction_status still-reproduces' <<<"${V[1]}" || { echo "${V[1]}"; return 1; }
  [ "${V[2]}" = ask_user ] || { echo "${V[2]}"; return 1; }
}

@test "a BUG Validation with flakes and a deferred replay goes on" {
  gate bug PASSED_WITH_FLAKES ", $FLAKES1, \"reproduction_status\": \"deferred-manual\""
  grep -qw review <<<"${V[0]}" || { echo "${V[0]}"; return 1; }
}

# ── the epic ────────────────────────────────────────────────────────────────

epic_contract() { # $1 start stage
  printf '{"task_id": "050", "task_dir": "/p/Tasks/ACTIVE/050-e", "plugin_root": "/core", "lang": "en", "mode": "auto", "agents": %s, "start_stage": "%s", "stage_scope": "forward", "manual_checks_pass": "end"}' "$AGENTS" "$1"
}

epic() { node "$ROOT/tests/foundation/helpers/run-profile.js" "$ROOT/workflows/profile-epic.js" "$1" "$2"; }

@test "an epic step that passed with flakes is not a failed step" {
  steps='"execute:read-steps": {"ok": true, "branch": "decomposition", "steps": [{"step_id": "1.step", "task_id": "050.1", "task_type": "FEATURE", "status": "PENDING"}]}'
  out="$(epic "$(epic_contract Execute)" "{$steps, \"workflow:spine-toolkit:profile-feature\": {\"status\": \"ok\", \"next_recommended_action\": \"stop\", \"validation_status\": \"PASSED_WITH_FLAKES\", \"review_status\": \"APPROVED\"}}")"
  node -e 'const o = JSON.parse(process.argv[1]); const r = o.result
    if (r.failed_steps.length || r.completed_steps.map((s) => s.step_id).join() !== "1.step" || !o.calls.some((c) => c.label === "execute:tick:1.step")) { console.log(JSON.stringify(r)); process.exit(1) }' "$out"
}

@test "an epic step that ended FLAKY is still a failed step" {
  steps='"execute:read-steps": {"ok": true, "branch": "decomposition", "steps": [{"step_id": "1.step", "task_id": "050.1", "task_type": "FEATURE", "status": "PENDING"}]}'
  out="$(epic "$(epic_contract Execute)" "{$steps, \"workflow:spine-toolkit:profile-feature\": {\"status\": \"ok\", \"next_recommended_action\": \"ask_user\", \"validation_status\": \"FLAKY\"}}")"
  node -e 'const o = JSON.parse(process.argv[1]); const r = o.result
    if (r.completed_steps.length || r.failed_steps.length !== 1 || !r.failed_steps[0].error_reason.startsWith("FLAKY")) { console.log(JSON.stringify(r)); process.exit(1) }' "$out"
}

@test "Acceptance passes with flakes and goes on to Done" {
  steps='"execute:read-steps": {"ok": true, "branch": "decomposition", "steps": [{"step_id": "1.step", "task_id": "050.1", "task_type": "FEATURE", "status": "DONE"}]}'
  acc='"acceptance": {"validation_status": "PASSED_WITH_FLAKES", "artifact_path": "v", "manual_checks": [], "agent_verdicts": 0, "summary": "s"}'
  out="$(epic "$(epic_contract Execute)" "{$steps, $acc, \"done:read-branch\": {\"branch\": \"decomposition\"}}")"
  node -e 'const o = JSON.parse(process.argv[1]); const r = o.result
    if (!o.calls.some((c) => c.label === "done") || r.notes.includes("Done was not run")) { console.log(JSON.stringify(r)); process.exit(1) }' "$out"
  acc='"acceptance": {"validation_status": "FLAKY", "artifact_path": "v", "manual_checks": [], "agent_verdicts": 0, "summary": "s"}'
  out="$(epic "$(epic_contract Execute)" "{$steps, $acc}")"
  node -e 'const o = JSON.parse(process.argv[1]); const r = o.result
    if (o.calls.some((c) => c.label === "done") || !r.notes.includes("Acceptance returned FLAKY")) { console.log(JSON.stringify(r)); process.exit(1) }' "$out"
}

@test "the Acceptance schema and brief take PASSED_WITH_FLAKES as passed" {
  rp epic "$(epic_contract Acceptance)" '{}' \
    'o.calls[0].schema.properties.validation_status.enum.join(" ")' \
    '(o.calls[0].prompt.match(/already carries the line [^,]*/) || [""])[0]' \
    'o.calls[0].prompt'
  [ "${V[0]}" = 'PASSED PASSED_WITH_FLAKES FAILED FLAKY' ] || { echo "enum: ${V[0]}"; return 1; }
  for f in 'already carries the line [VALIDATION_STATUS] = PASSED or [VALIDATION_STATUS] = PASSED_WITH_FLAKES' \
           'return already_passed true, validation_status as that line says' \
           'A status FAILED or FLAKY there means the earlier pass did not complete' \
           '[VALIDATION_STATUS] = PASSED | PASSED_WITH_FLAKES | FAILED | FLAKY'; do
    grep -qF -- "$f" <<<"${V[2]}" || { echo "the Acceptance brief lost: $f"; return 1; }
  done
}

# ── the schema ──────────────────────────────────────────────────────────────

@test "the Validation schema carries the new status and fields" {
  for p in $RANGED research review epic; do
    f="$ROOT/workflows/profile-$p.js"
    grep -qF "enum: ['PASSED', 'PASSED_WITH_FLAKES', 'FAILED', 'FLAKY']" "$f" || { echo "profile-$p: the status enum"; return 1; }
    for k in 'outside_failures' "enum: ['known', 'flaky', 'red']" 'known_failures_cleared'; do
      grep -qF -- "$k" "$f" || { echo "profile-$p: lost $k"; return 1; }
    done
  done
}

@test "the gate is one function in the prelude, and no profile still compares with PASSED" {
  grep -qF "const passed = (status) => status === 'PASSED' || status === 'PASSED_WITH_FLAKES'" "$ROOT/workflow-src/prelude.js" || { echo "no passed() in the prelude"; return 1; }
  for p in $RANGED; do
    if grep -qF "validation_status !== 'PASSED'" "$ROOT/workflows/profile-$p.js"; then echo "profile-$p: the gate still compares with PASSED"; return 1; fi
  done
  if grep -qF "acceptance.validation_status !== 'PASSED'" "$ROOT/workflows/profile-epic.js"; then echo "epic: Acceptance still compares with PASSED"; return 1; fi
}
