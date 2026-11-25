#!/usr/bin/env bats
# changed: sweep workflows
# Claude Code in auto permission mode does not start an agent whose output schema is over 4096
# characters. A step carries every setting of its own folder, so only the calls that need them get
# the whole step: Plan returns just what finds a QUICK type and counts the steps, and Execute reads
# the rest off disk.

setup() {
  ROOT="$(cd -- "$(dirname -- "$BATS_TEST_FILENAME")/../../.." && pwd)"
  AGENTS='{"architect":"a","developer":"d","tester":"t","reviewer":"r","refactorer":"f","validator":"v","security":"—","diagnostics":"g","init":"—"}'
  PLANNED_KEYS='need_review,need_test,status,step_id,task_id,task_type,title'
}

contract() { # $1 = start stage
  echo '{"task_id": "050", "task_dir": "/p/Tasks/ACTIVE/050-e", "plugin_root": "/core", "lang": "en", "mode": "auto", "agents": '"$AGENTS"', "start_stage": "'"$1"'", "stage_scope": "single"}'
}

run_epic() { # $1 = start stage, $2 = replies
  node "$ROOT/tests/foundation/helpers/run-profile.js" "$ROOT/workflows/profile-epic.js" "$(contract "$1")" "$2"
}

# The item schema of the steps array that the call labelled $2 was given.
step_items() { # $1 = run output, $2 = label
  node -e 'const o = JSON.parse(process.argv[1]); const c = o.calls.find((x) => x.label === process.argv[2])
    if (!c) { console.log("no call labelled " + process.argv[2]); process.exit(1) }
    console.log(JSON.stringify(c.schema.properties.steps.items))' "$1" "$2"
}

keys_of() { node -e 'console.log(Object.keys(JSON.parse(process.argv[1]).properties).sort().join())' "$1"; }

plan_reply() { # $1 = task type of the planned step
  echo '"plan": {"ok": true, "artifact_path": "x", "summary": "s", "branch": "decomposition", "steps": [{"step_id": "1.step", "task_id": "050.1", "task_type": "'"$1"'", "status": "PENDING"}]}'
}

@test "plan gets the planned step" {
  out="$(run_epic Plan "{$(plan_reply BUG)}")"
  items="$(step_items "$out" plan)"
  [ "$(keys_of "$items")" = "$PLANNED_KEYS" ] || { echo "$items"; return 1; }
  node -e 'const r = JSON.parse(process.argv[1]).required.join(); if (r !== "step_id,task_id,task_type,status") { console.log(r); process.exit(1) }' "$items"
}

@test "plan:retype gets the planned step" {
  retyped='"plan:retype": {"ok": true, "branch": "decomposition", "steps": [{"step_id": "1.step", "task_id": "050.1", "task_type": "BUG", "status": "PENDING"}]}'
  out="$(run_epic Plan "{$(plan_reply QUICK), $retyped}")"
  items="$(step_items "$out" plan:retype)"
  [ "$(keys_of "$items")" = "$PLANNED_KEYS" ] || { echo "$items"; return 1; }
}

read_steps() {
  run_epic Execute '{"execute:read-steps": {"ok": true, "branch": "decomposition", "steps": [{"step_id": "1.step", "task_id": "050.1", "task_type": "BUG", "status": "PENDING"}]}}'
}

@test "the step reader gets the whole step" {
  items="$(step_items "$(read_steps)" execute:read-steps)"
  node -e 'const p = JSON.parse(process.argv[1]).properties; if (!p.drive_app || !p.resolved_models) process.exit(1)' "$items" \
    || { echo "$items"; return 1; }
}

@test "STEP carries one shared description instead of one per setting" {
  items="$(step_items "$(read_steps)" execute:read-steps)"
  node -e 'const s = JSON.parse(process.argv[1])
    if (!/^A setting with no description of its own .*resolve-settings\.sh json/.test(s.description || "")) { console.log("no shared description for the settings alone: " + s.description); process.exit(1) }
    if (s.properties.drive_app.description !== undefined) { console.log("drive_app keeps its own"); process.exit(1) }
    if (s.properties.step_id.description === undefined) { console.log("step_id lost its own"); process.exit(1) }' "$items"
}
