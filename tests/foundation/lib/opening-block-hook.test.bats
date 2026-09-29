#!/usr/bin/env bats
# hooks/opening-block shows the run's opening block as the host's own message, so a reply that
# skips it cannot drop it. It fires on every Workflow and Skill call of a session: whatever is not
# the orchestrator's dispatch, and whatever it cannot read, must pass in silence and never block.

setup() {
  ROOT="$(cd -- "$(dirname -- "$BATS_TEST_FILENAME")/../../.." && pwd)"
  HOOK="$ROOT/hooks/opening-block"
  PROJ="$BATS_TEST_TMPDIR/proj"
  TASK="$PROJ/Tasks/ACTIVE/042-a-task"
  mkdir -p "$TASK" "$BATS_TEST_TMPDIR/tmp"
  printf '# CLAUDE-spine-toolkit.md\n\n## Task defaults\n\n[WORKFLOW_MODE] = [auto]\n' >"$PROJ/CLAUDE-spine-toolkit.md"
  printf '[TASK_TYPE] = [BUG]\n' >"$TASK/Task.md"
  export TMPDIR="$BATS_TEST_TMPDIR/tmp"
}

# The contract a dispatch carries, $1 merged over it.
contract() {
  python3 -c 'import json,sys; c={"task_id":"042","task_dir":"Tasks/ACTIVE/042-a-task","profile":"bug","start_stage":"Reproduce","end_stage":None,"stage_scope":"forward","lang":"en","progress":"normal","method_reason":"","user_directive":"","run_settings":{}}; c.update(json.loads(sys.argv[1]) or {}); print(json.dumps(c))' "${1:-null}"
}
workflow() { printf '{"name": "spine-toolkit:profile-bug", "args": %s}' "$(contract "$@")"; }

# Runs the hook on a PreToolUse input: $1 the tool, $2 its tool_input as JSON, $3 the prompt id.
hook() {
  python3 -c 'import json,sys; print(json.dumps({"session_id":"s-1","prompt_id":sys.argv[3],"cwd":sys.argv[4],"hook_event_name":"PreToolUse","tool_name":sys.argv[1],"tool_input":json.loads(sys.argv[2])}))' \
    "$1" "$2" "${3:-p-1}" "$PROJ" >"$BATS_TEST_TMPDIR/in"
  run "$HOOK" <"$BATS_TEST_TMPDIR/in"
}
message() { python3 -c 'import json,sys; print(json.load(sys.stdin)["systemMessage"])' <<<"$output"; }

@test "a Method A dispatch gets the block as a systemMessage, by name or by scriptPath" {
  hook Workflow "$(workflow)"
  [ "$status" -eq 0 ] || { echo "$output"; return 1; }
  [ "$(message | head -1)" = "BUG 042 · Reproduce → Done · Progress: normal · Method A" ] || { echo "$output"; return 1; }
  hook Workflow "$(printf '{"scriptPath": "/Users/u/.claude/plugins/cache/m/spine-toolkit/2.26.0/workflows/profile-bug.js", "args": %s}' "$(contract)")" p-2
  [ "$(message | head -1)" = "BUG 042 · Reproduce → Done · Progress: normal · Method A" ] || { echo "$output"; return 1; }
}

@test "a Method B dispatch gets the block with its reason" {
  args="$(printf '%s\n' 'task_dir=Tasks/ACTIVE/042-a-task' 'profile=bug' 'start_stage=Reproduce' 'end_stage=null' \
    'stage_scope=forward' 'lang=en' 'progress=normal' 'method_reason="Workflow is not callable here"' \
    'user_directive=""' 'run_settings={}')"
  hook Skill "$(python3 -c 'import json,sys; print(json.dumps({"skill":"spine-toolkit:workflow-bug","args":sys.argv[1]}))' "$args")"
  [ "$(message | head -1)" = "BUG 042 · Reproduce → Done · Progress: normal · Method B (spine-toolkit:workflow-bug): Workflow is not callable here" ] \
    || { echo "$output"; return 1; }
}

@test "a call that is not the orchestrator's dispatch passes in silence" {
  for t in 'Skill|{"skill": "superpowers:brainstorming", "args": "x"}' \
           "Workflow|{\"name\": \"other:profile-bug\", \"args\": $(contract)}" \
           'Skill|{"skill": "spine-toolkit:orchestrator", "args": "run 042"}'; do
    hook "${t%%|*}" "${t#*|}"
    [ "$status" -eq 0 ] && [ -z "$output" ] || { echo "$t: $output"; return 1; }
  done
}

@test "the block goes out once per task in a turn, and again in the next turn" {
  hook Workflow "$(workflow)" p-1
  [ -n "$output" ] || { echo "no block the first time"; return 1; }
  hook Workflow "$(workflow)" p-1
  [ "$status" -eq 0 ] && [ -z "$output" ] || { echo "the block again in the same turn: $output"; return 1; }
  hook Workflow "$(workflow)" p-2
  [ -n "$output" ] || { echo "no block in the next turn"; return 1; }
}

@test "at quiet the hook prints nothing" {
  hook Workflow "$(workflow '{"progress": "quiet"}')"
  [ "$status" -eq 0 ] && [ -z "$output" ] || { echo "$output"; return 1; }
}

@test "a block the script could not write is one line, and the call still goes" {
  hook Workflow "$(workflow '{"method_reason": "not under A"}')"
  [ "$status" -eq 0 ] || { echo "$output"; return 1; }
  [ "$(message | wc -l | tr -d ' ')" = 1 ] || { echo "$output"; return 1; }
  message | grep -qF 'did not come out' || { echo "$output"; return 1; }
}

@test "input the hook cannot read passes in silence" {
  for input in 'not json' '{"tool_name": "Workflow"}' \
               '{"tool_name": "Workflow", "tool_input": {"name": "spine-toolkit:profile-bug", "args": 7}}'; do
    printf '%s' "$input" >"$BATS_TEST_TMPDIR/in"
    run "$HOOK" <"$BATS_TEST_TMPDIR/in"
    [ "$status" -eq 0 ] && [ -z "$output" ] || { echo "$input: $output"; return 1; }
  done
}

@test "at live the panel's command names the session the hook was given" {
  hook Workflow "$(workflow '{"progress": "live"}')"
  message | grep -qF 'agent-monitor.sh" --session s-1' || { echo "$output"; return 1; }
}
