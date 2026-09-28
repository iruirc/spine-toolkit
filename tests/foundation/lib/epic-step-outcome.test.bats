#!/usr/bin/env bats
# A pushed step counts as done only when its own run reached the end: a profile hands a verdict it
# cannot act on back as status ok with ask_user, and the walk must not build on it.

setup() {
  ROOT="$(cd -- "$(dirname -- "$BATS_TEST_FILENAME")/../../.." && pwd)"
  AGENTS='{"architect":"a","developer":"d","tester":"t","reviewer":"r","refactorer":"f","validator":"v","security":"—","diagnostics":"g","init":"—"}'
  CONTRACT='{"task_id": "050", "task_dir": "/p/Tasks/ACTIVE/050-e", "plugin_root": "/core", "lang": "en", "mode": "auto", "agents": '"$AGENTS"', "start_stage": "Execute", "stage_scope": "single"}'
  STEPS='"execute:read-steps": {"ok": true, "branch": "decomposition", "steps": [{"step_id": "1.step", "task_id": "050.1", "task_type": "BUG", "status": "PENDING"}, {"step_id": "2.step", "task_id": "050.2", "task_type": "REVIEW", "status": "PENDING"}]}'
}

walk() { node "$ROOT/tests/foundation/helpers/run-profile.js" "$ROOT/workflows/profile-epic.js" "$CONTRACT" "{$STEPS, $1}"; }

# The first step failed with the given reason, the second is pending, nothing was ticked.
failed_first() {
  node -e 'const o = JSON.parse(process.argv[1]); const r = o.result
    if (r.completed_steps.length || r.failed_steps.length !== 1 || !r.failed_steps[0].error_reason.includes(process.argv[2]) || r.pending_steps.map((s) => s.step_id).join() !== "2.step" || o.calls.some((c) => /^execute:tick/.test(c.label))) { console.log(JSON.stringify(o)); process.exit(1) }' "$1" "$2"
}

@test "a step whose Validation failed is not done" {
  out="$(walk '"workflow:spine-toolkit:profile-bug": {"status": "ok", "next_recommended_action": "ask_user", "validation_status": "FAILED", "notes": "Validation returned FAILED"}')"
  failed_first "$out" 'Validation returned FAILED'
}

@test "a step whose Review requested changes is not done" {
  out="$(walk '"workflow:spine-toolkit:profile-bug": {"status": "ok", "next_recommended_action": "ask_user", "validation_status": "PASSED", "review_status": "CHANGES_REQUESTED", "notes": "Review requested changes"}')"
  failed_first "$out" 'Review requested changes'
}

@test "a step that stopped on any other question is not done" {
  out="$(walk '"workflow:spine-toolkit:profile-bug": {"status": "ok", "next_recommended_action": "ask_user", "reproducible": "no", "notes": "The bug could not be reproduced"}')"
  failed_first "$out" 'The bug could not be reproduced'
}

@test "a REVIEW step that requested changes stops the walk although its run ended" {
  out="$(walk '"workflow:spine-toolkit:profile-bug": {"status": "ok", "next_recommended_action": "stop", "validation_status": "PASSED", "review_status": "APPROVED"}, "workflow:spine-toolkit:profile-review": {"status": "ok", "next_recommended_action": "stop", "review_status": "CHANGES_REQUESTED", "action_taken": "recorded-awaiting-changes"}')"
  node -e 'const o = JSON.parse(process.argv[1]); const r = o.result
    if (r.completed_steps.map((s) => s.step_id).join() !== "1.step" || r.failed_steps.map((s) => s.step_id).join() !== "2.step" || !/CHANGES_REQUESTED/.test(r.failed_steps[0].error_reason) || o.calls.some((c) => c.label === "execute:tick:2.step")) { console.log(JSON.stringify(o)); process.exit(1) }' "$out"
}

@test "a step that ran to the end is done and ticked" {
  out="$(walk '"workflow:spine-toolkit:profile-bug": {"status": "ok", "next_recommended_action": "stop", "validation_status": "PASSED", "review_status": "APPROVED"}, "workflow:spine-toolkit:profile-review": {"status": "ok", "next_recommended_action": "stop", "review_status": "APPROVED", "action_taken": "moved-to-done"}')"
  node -e 'const o = JSON.parse(process.argv[1]); const r = o.result
    if (r.completed_steps.length !== 2 || r.failed_steps.length || !o.calls.some((c) => c.label === "execute:tick:2.step")) { console.log(JSON.stringify(o)); process.exit(1) }' "$out"
}

@test "Method B stops on a step that did not reach its end" {
  grep -qF 'If the step returned `status=ok` with `next_recommended_action=ask_user`, or with a `validation_status` other than `PASSED` or a `review_status` other than `APPROVED`' "$ROOT/skills/workflow-epic/SKILL.md" \
    || { echo "Method B counts an unfinished step as done"; return 1; }
}
