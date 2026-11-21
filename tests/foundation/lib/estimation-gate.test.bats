#!/usr/bin/env bats
# changed: sweep workflows
# How [ESTIMATION] and [ESTIMATION_UNIT] shape the FEATURE Plan and Done: which skill the briefs
# name, which fields the Plan schema requires, the gate that stops before Execute, and the
# run_forecast the orchestrator prints at the manual gate — driven through the script with stubbed
# agents.

load "$(dirname "$BATS_TEST_FILENAME")/../helpers/run-profile-read"

setup() {
  AGENTS='{"architect":"a","developer":"d","tester":"t","reviewer":"r","refactorer":"f","validator":"v","security":"—","diagnostics":"g","init":"—"}'
  PHASES='"phases": [{"id": "1", "title": "t", "kind": "code"}]'
  FORECAST='"run_forecast": {"best": "1h 10m", "worst": "2h 30m", "gates": "1–2", "confidence": "medium"}'
}

# contract <scale> <estimation> <unit> <from> <start stage> <stage members, leading comma>
contract() {
  printf '{"task_id": "001", "task_dir": "/p/Tasks/ACTIVE/001-x", "plugin_root": "/core", "lang": "en", "agents": %s, "scale": "%s", "estimation": "%s", "estimation_unit": "%s", "estimation_from": "%s", "start_stage": "%s"%s}' \
    "$AGENTS" "$1" "$2" "$3" "$4" "$5" "$6"
}

# plan_only <scale> <estimation> <unit> <from> [plan reply]: the Plan brief, the Plan schema's
# required list, and the result of a run that ends at Plan.
plan_only() {
  local reply="${5:-}"
  [ -n "$reply" ] || reply="{\"ok\": true, \"artifact_path\": \"p\", \"summary\": \"s\", $PHASES}"
  rp feature "$(contract "$1" "$2" "$3" "$4" Plan ', "end_stage": "Plan"')" "{\"plan\": $reply}" \
    "o.calls.find((c) => c.label === 'plan').prompt" \
    "o.calls.find((c) => c.label === 'plan').schema.required.join(' ')" \
    'JSON.stringify(o.result.run_forecast || null)'
}

# done_only <scale> <estimation> <unit> <from>: the Done brief.
done_only() {
  rp feature "$(contract "$1" "$2" "$3" "$4" Done ', "stage_scope": "single"')" '{}' \
    "o.calls.find((c) => c.label === 'done').prompt"
}

@test "estimation off at full: no estimation in the Plan brief, no gate, no retrospective in Done" {
  plan_only full off agent-run project
  for w in '## Estimation' feature-estimation run-forecast estimation_gate; do
    if grep -qF -- "$w" <<<"${V[0]}"; then echo "the Plan brief names $w"; return 1; fi
  done
  if grep -qw estimation_gate <<<"${V[1]}"; then echo "estimation_gate is required: ${V[1]}"; return 1; fi
  if grep -qw run_forecast <<<"${V[1]}"; then echo "run_forecast is required: ${V[1]}"; return 1; fi
  done_only full off agent-run project
  for w in '## Estimate retrospective' feature-estimation run-forecast; do
    if grep -qF -- "$w" <<<"${V[0]}"; then echo "the Done brief names $w"; return 1; fi
  done
}

@test "agent-run: the Plan brief names run-forecast and the gate" {
  plan_only full on agent-run scale
  grep -qF run-forecast <<<"${V[0]}" || { echo "the Plan brief does not name run-forecast"; return 1; }
  grep -qF conventions/estimation-gate.md <<<"${V[0]}" || { echo "the Plan brief does not name the gate convention"; return 1; }
  if grep -qF feature-estimation <<<"${V[0]}"; then echo "the Plan brief names feature-estimation"; return 1; fi
  if grep -qF AI-assisted <<<"${V[0]}"; then echo "the Plan brief speaks of an AI-assisted range"; return 1; fi
  grep -qw estimation_gate <<<"${V[1]}" || { echo "estimation_gate is not required: ${V[1]}"; return 1; }
  grep -qw run_forecast <<<"${V[1]}" || { echo "run_forecast is not required: ${V[1]}"; return 1; }
  done_only full on agent-run scale
  grep -qF '## Estimate retrospective' <<<"${V[0]}" || { echo "the Done brief has no retrospective"; return 1; }
  grep -qF run-forecast <<<"${V[0]}" || { echo "the Done brief does not name run-forecast"; return 1; }
  grep -qF -- --project-sessions <<<"${V[0]}" || { echo "the Done brief does not read the project's sessions"; return 1; }
  grep -qF Tasks/_calibration/agent-run-log.md <<<"${V[0]}" || { echo "the Done brief does not name the agent-run log"; return 1; }
  if grep -qF feature-estimation <<<"${V[0]}"; then echo "the Done brief names feature-estimation"; return 1; fi
}

@test "an old config with no estimation unit plans in agent-run, not in days" {
  rp feature "$(printf '{"task_id": "001", "task_dir": "/p/Tasks/ACTIVE/001-x", "plugin_root": "/core", "lang": "en", "agents": %s, "start_stage": "Plan", "end_stage": "Plan"}' "$AGENTS")" \
    "{\"plan\": {\"ok\": true, \"artifact_path\": \"p\", \"summary\": \"s\", $PHASES}}" \
    "o.calls.find((c) => c.label === 'plan').prompt"
  grep -qF run-forecast <<<"${V[0]}" || { echo "the Plan brief does not name run-forecast"; return 1; }
  if grep -qF feature-estimation <<<"${V[0]}"; then echo "the Plan brief names feature-estimation"; return 1; fi
}

@test "days: the Plan brief is the day estimate" {
  plan_only full on days project
  grep -qF feature-estimation <<<"${V[0]}" || { echo "the Plan brief does not name feature-estimation"; return 1; }
  grep -qF conventions/estimation-gate.md <<<"${V[0]}" || { echo "the Plan brief does not name the gate convention"; return 1; }
  if grep -qF run-forecast <<<"${V[0]}"; then echo "the Plan brief names run-forecast"; return 1; fi
  grep -qw estimation_gate <<<"${V[1]}" || { echo "estimation_gate is not required: ${V[1]}"; return 1; }
  if grep -qw run_forecast <<<"${V[1]}"; then echo "run_forecast is required: ${V[1]}"; return 1; fi
  done_only full on days project
  grep -qF feature-estimation <<<"${V[0]}" || { echo "the Done brief does not name feature-estimation"; return 1; }
  if grep -qF run-forecast <<<"${V[0]}"; then echo "the Done brief names run-forecast"; return 1; fi
}

@test "both: both skills" {
  plan_only full on both project
  for w in feature-estimation run-forecast conventions/estimation-gate.md; do
    grep -qF "$w" <<<"${V[0]}" || { echo "the Plan brief does not name $w"; return 1; }
  done
  for f in estimation_gate run_forecast; do
    grep -qw "$f" <<<"${V[1]}" || { echo "$f is not required: ${V[1]}"; return 1; }
  done
  done_only full on both project
  for w in feature-estimation run-forecast; do
    grep -qF "$w" <<<"${V[0]}" || { echo "the Done brief does not name $w"; return 1; }
  done
}

@test "a blocked gate stops before Execute at every unit" {
  for u in agent-run days both; do
    rp feature "$(contract full on "$u" project Plan '')" \
      "{\"plan\": {\"ok\": true, \"artifact_path\": \"p\", \"summary\": \"s\", $PHASES, $FORECAST, \"estimation_gate\": {\"status\": \"blocked\", \"reason\": \"a pending_user row\"}}}" \
      'o.result.next_recommended_action' 'o.calls.map((c) => c.label).join(" ")' 'o.result.estimation_gate'
    [ "${V[0]}" = ask_user ] || { echo "$u: next is ${V[0]}"; return 1; }
    if grep -qE '(^| )(execute|develop|phase)' <<<"${V[1]}"; then echo "$u: Execute ran: ${V[1]}"; return 1; fi
    [ "${V[2]}" = blocked ] || { echo "$u: estimation_gate is ${V[2]}"; return 1; }
  done
}

@test "run_forecast reaches the result" {
  plan_only full on agent-run project "{\"ok\": true, \"artifact_path\": \"p\", \"summary\": \"s\", $PHASES, $FORECAST, \"estimation_gate\": {\"status\": \"ok\"}}"
  [ "${V[2]}" = '{"best":"1h 10m","worst":"2h 30m","gates":"1–2","confidence":"medium"}' ] || { echo "run_forecast: ${V[2]}"; return 1; }
  rp feature "$(contract full on agent-run project Plan '')" \
    "{\"plan\": {\"ok\": true, \"artifact_path\": \"p\", \"summary\": \"s\", $PHASES, $FORECAST, \"estimation_gate\": {\"status\": \"blocked\", \"reason\": \"r\"}}}" \
    'JSON.stringify(o.result.run_forecast || null)'
  [ "${V[0]}" = '{"best":"1h 10m","worst":"2h 30m","gates":"1–2","confidence":"medium"}' ] || { echo "blocked: run_forecast: ${V[0]}"; return 1; }
}

@test "at lite with estimation following the scale, a raised plan estimates" {
  plan_only lite off agent-run scale
  grep -qF 'If you raise the scale' <<<"${V[0]}" || { echo "no instruction for a raised plan"; return 1; }
  grep -qF run-forecast <<<"${V[0]}" || { echo "the raised plan is not told to apply run-forecast"; return 1; }
  grep -qF '## Estimation' <<<"${V[0]}" || { echo "the raised plan is not told to write ## Estimation"; return 1; }
  grep -qF estimation_gate <<<"${V[0]}" || { echo "the raised plan is not told to report estimation_gate"; return 1; }
  if grep -qF feature-estimation <<<"${V[0]}"; then echo "agent-run: the raised plan names feature-estimation"; return 1; fi
  if grep -qw estimation_gate <<<"${V[1]}"; then echo "estimation_gate is required before the raise: ${V[1]}"; return 1; fi
  plan_only lite off days scale
  grep -qF 'If you raise the scale' <<<"${V[0]}" && grep -qF feature-estimation <<<"${V[0]}" \
    || { echo "days: the raised plan is not told to apply feature-estimation"; return 1; }
  plan_only lite off agent-run task
  for w in 'If you raise the scale' '## Estimation' run-forecast feature-estimation estimation_gate; do
    if grep -qF -- "$w" <<<"${V[0]}"; then echo "an explicit off names $w"; return 1; fi
  done
}

@test "a plan raised from lite with estimation following the scale turns the Done retrospective on" {
  rp feature "$(contract lite off agent-run scale Plan '')" \
    "{\"plan\": {\"ok\": true, \"artifact_path\": \"p\", \"summary\": \"s\", $PHASES, $FORECAST, \"estimation_gate\": {\"status\": \"ok\"}, \"scale_escalation\": {\"to\": \"full\", \"reason\": \"two packages\"}}, \"execute:1\": {\"ok\": true, \"phase_id\": \"1\", \"committed\": true, \"summary\": \"s\"}, \"validation\": {\"validation_status\": \"PASSED\", \"artifact_path\": \"v\", \"summary\": \"s\"}, \"review\": {\"review_status\": \"APPROVED\", \"artifact_path\": \"r\", \"summary\": \"s\"}}" \
    "(o.calls.find((c) => c.label === 'done') || {prompt: 'no Done: ' + o.calls.map((c) => c.label).join(' ')}).prompt"
  grep -qF '## Estimate retrospective' <<<"${V[0]}" || { echo "no retrospective after the raise: ${V[0]:0:300}"; return 1; }
  grep -qF run-forecast <<<"${V[0]}" || { echo "the Done brief does not name run-forecast"; return 1; }
}
