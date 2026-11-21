#!/usr/bin/env bats
load "$(dirname "$BATS_TEST_FILENAME")/../helpers/tm-test-helpers"

setup_file() {
  local wf="$(tm_home home-a)/projects/-tmp-proj/11111111-1111-1111-1111-111111111111/workflows"
  # Discovery now orders runs by state-file mtime, not filename; pin these so
  # every "runs.N" assertion below stays meaningful regardless of checkout order.
  touch -t 202601010000 "$wf/wf_aaa1111-111.json"
  touch -t 202601010005 "$wf/wf_bbb2222-222.json"
  touch -t 202601010010 "$wf/wf_ccc3333-333.json"

  local task395="$(tm_home home-a)/projects/-tmp-proj/55555555-5555-5555-5555-555555555555/workflows"
  touch -t 202601020000 "$task395/wf_9664a933-1b1.json"
  touch -t 202601020010 "$task395/wf_8ea8c484-343.json"

  # Task 700 was interrupted and continued: two sessions, the second one newer.
  local proj="$(tm_home home-a)/projects/-tmp-proj"
  touch -t 202601030000 "$proj/$T700_A/workflows/wf_t700exe-a01.json"
  touch -t 202601030010 "$proj/$T700_A/workflows/wf_t700val-a02.json"
  touch -t 202601040000 "$proj/$T700_B/workflows/wf_t700rev-b01.json"
  touch -t 202601040010 "$proj/$T700_B/workflows/wf_t700fix-b02.json"
  touch -t 202601030020 "$proj/$T700_A"
  touch -t 202601040020 "$proj/$T700_B"
}

T700_A=70707070-7070-7070-7070-707070707070
T700_B=71717171-7171-7171-7171-717171717171

# The JSON of one field, so a null is told apart from a missing key or an empty string.
field_json() {
  python3 -c '
import json, sys
node = json.loads(sys.argv[1])
for key in sys.argv[2].split("."):
    node = node[int(key)] if key.isdigit() else node[key]
print(json.dumps(node))
' "$1" "$2"
}

@test "unknown session yields an empty document, not an error" {
  run tm_metrics home-empty --session 99999999-9999-9999-9999-999999999999
  [ "$status" -eq 0 ]
  [ "$(tm_field "$output" reason)" = "session directory not found" ]
  [ "$(tm_field "$output" runs)" = "[]" ]
}

@test "unknown option exits 2" {
  run tm_metrics home-empty --nope
  [ "$status" -eq 2 ]
  tm_contains "$output" "unknown option"
}

@test "unknown format exits 2" {
  run tm_metrics home-empty --format yaml
  [ "$status" -eq 2 ]
  tm_contains "$output" "unknown format"
}

@test "missing python3 exits 2 with a readable reason" {
  local stub="$(mktemp -d)"
  # /bin/bash by absolute path: with PATH stubbed empty, a `#!/usr/bin/env bash`
  # shebang would fail to resolve its own interpreter before the script runs.
  run env PATH="$stub" CLAUDE_CONFIG_DIR="$(tm_home home-empty)" \
      /bin/bash "$(tm_repo_root)/scripts/agent-metrics.sh"
  rmdir "$stub"
  [ "$status" -eq 2 ]
  tm_contains "$output" "python3 not found"
}

@test "an option without its value exits 2, not 1" {
  run tm_metrics home-empty --session
  [ "$status" -eq 2 ]
  tm_contains "$output" "missing value for --session"
}

@test "a --session match that is not a directory is treated as not found" {
  run tm_metrics home-a --session 66666666-6666-6666-6666-666666666666
  [ "$status" -eq 0 ]
  [ "$(tm_field "$output" reason)" = "session directory not found" ]
}

@test "the default session lookup skips a sibling that is not a session directory" {
  local cfg proj slug
  cfg="$(mktemp -d)"
  proj="$(cd -- "$(mktemp -d)" && pwd -P)"
  slug="$(printf '%s' "$proj" | tr -c 'A-Za-z0-9' '-')"
  # `memory/` is newer than the real session dir but isn't one — no session-id
  # name, no workflows/subagents subdirectory. Only max(mtime) would pick it.
  mkdir -p "$cfg/projects/$slug/memory"
  mkdir -p "$cfg/projects/$slug/88888888-8888-8888-8888-888888888888/workflows"
  touch -t 202501010000 "$cfg/projects/$slug/88888888-8888-8888-8888-888888888888"
  touch -t 202601010000 "$cfg/projects/$slug/memory"
  run env CLAUDE_CONFIG_DIR="$cfg" CLAUDE_CODE_SESSION_ID="" \
      bash -c "cd '$proj' && '$(tm_repo_root)/scripts/agent-metrics.sh'"
  rm -rf "$cfg" "$proj"
  [ "$status" -eq 0 ]
  [ "$(tm_field "$output" session)" = "88888888-8888-8888-8888-888888888888" ]
}

@test "a malformed wf_*.json degrades to an empty result, not a traceback" {
  run tm_metrics home-a --session 33333333-3333-3333-3333-333333333333
  [ "$status" -eq 0 ]
  [ "$(tm_field "$output" reason)" = "could not parse run state" ]
  [ "$(tm_field "$output" runs)" = "[]" ]
}

@test "method A run exposes phases in order" {
  run tm_metrics home-a --session 11111111-1111-1111-1111-111111111111
  [ "$status" -eq 0 ]
  [ "$(tm_field "$output" runs.0.workflow)" = "profile-refactor" ]
  [ "$(tm_field "$output" runs.0.task_id)" = "077" ]
  [ "$(tm_field "$output" runs.0.elapsedMs)" = "252000" ]
  [ "$(tm_field "$output" runs.0.phases.0.title)" = "Analyze" ]
  [ "$(tm_field "$output" runs.0.phases.2.title)" = "Review" ]
}

@test "method A agents carry stage, model, ctx and tool count" {
  run tm_metrics home-a --session 11111111-1111-1111-1111-111111111111
  [ "$(tm_field "$output" runs.0.agents.0.phase)" = "Analyze" ]
  [ "$(tm_field "$output" runs.0.agents.0.agentType)" = "fixture-platform:fixture-architect" ]
  [ "$(tm_field "$output" runs.0.agents.0.model)" = "claude-opus-5" ]
  [ "$(tm_field "$output" runs.0.agents.0.ctx)" = "312000" ]
  [ "$(tm_field "$output" runs.0.agents.0.tools)" = "24" ]
  [ "$(tm_field "$output" runs.0.agents.0.elapsedMs)" = "64000" ]
}

@test "a phase with no agent of its own stays todo" {
  run tm_metrics home-a --session 11111111-1111-1111-1111-111111111111
  [ "$(tm_field "$output" runs.0.phases.0.state)" = "done" ]
  [ "$(tm_field "$output" runs.0.phases.2.state)" = "todo" ]
}

@test "out is summed from the agent transcript, never taken from run state" {
  run tm_metrics home-a --session 11111111-1111-1111-1111-111111111111
  [ "$(tm_field "$output" runs.0.agents.0.out)" = "1148" ]
}

@test "artifact and summary come from the journal result" {
  run tm_metrics home-a --session 11111111-1111-1111-1111-111111111111
  [ "$(tm_field "$output" runs.0.agents.0.artifact)" = "Tasks/ACTIVE/077-refactor-di/Research.md" ]
  [ "$(tm_field "$output" runs.0.agents.0.summary)" = "scope confirmed" ]
}

@test "totals sum out across the agents of a run" {
  run tm_metrics home-a --session 11111111-1111-1111-1111-111111111111 --run wf_aaa1111-111
  [ "$(tm_field "$output" totals.out)" = "1148" ]
  [ "$(tm_field "$output" totals.agents)" = "2" ]
}

@test "the agent record sums input, cache-write and cache-read tokens from the transcript" {
  # agent-a0000000000000001.jsonl carries two usage blocks: input 2+2, cache
  # write 1000+2000, cache read 9000+40000.
  run tm_metrics home-a --session 11111111-1111-1111-1111-111111111111 --run wf_aaa1111-111
  [ "$(tm_field "$output" runs.0.agents.0.inTok)" = "4" ]
  [ "$(tm_field "$output" runs.0.agents.0.cacheWrite)" = "3000" ]
  [ "$(tm_field "$output" runs.0.agents.0.cacheRead)" = "49000" ]
}

@test "totals gain in, cacheWrite and cacheRead summed across every agent" {
  # Session 11111111 sums 3 runs' worth of usage: in 4+0+1+1=6,
  # cacheWrite 3000+0+500+200=3700, cacheRead 49000+0+7000+3000=59000.
  run tm_metrics home-a --session 11111111-1111-1111-1111-111111111111
  [ "$(tm_field "$output" totals.in)" = "6" ]
  [ "$(tm_field "$output" totals.cacheWrite)" = "3700" ]
  [ "$(tm_field "$output" totals.cacheRead)" = "59000" ]
}

@test "totals.total sums in, cacheWrite, cacheRead and out, and totalText is its formatted form" {
  # 6 + 3700 + 59000 + 1598 (out) = 64304.
  run tm_metrics home-a --session 11111111-1111-1111-1111-111111111111
  [ "$(tm_field "$output" totals.total)" = "64304" ]
  [ "$(tm_field "$output" totals.totalText)" = "64.3k" ]
}

@test "a request written over several rows counts its usage once" {
  # req_A: three rows repeat input 3, cache-write 1000, cache-read 20000; out grows to 120.
  # msg_B: two rows with no requestId, joined by message.id: 1, 500, 21000; out grows to 80.
  run tm_metrics home-a --session 12121212-1212-1212-1212-121212121212
  [ "$(tm_field "$output" runs.0.agents.0.reqs)" = "2" ]
  [ "$(tm_field "$output" runs.0.agents.0.inTok)" = "4" ]
  [ "$(tm_field "$output" runs.0.agents.0.cacheWrite)" = "1500" ]
  [ "$(tm_field "$output" runs.0.agents.0.cacheRead)" = "41000" ]
  [ "$(tm_field "$output" runs.0.agents.0.out)" = "200" ]
  [ "$(tm_field "$output" runs.0.agents.0.tools)" = "3" ]
  [ "$(tm_field "$output" runs.0.agents.0.ctx)" = "21501" ]
}

@test "distinct requests each count, and a row without usage keeps its request's" {
  # req_C 2/2000/30000 out 400, req_D 2/0/32000 out 100; req_D's last row has no usage.
  run tm_metrics home-a --session 12121212-1212-1212-1212-121212121212
  [ "$(tm_field "$output" runs.0.agents.1.reqs)" = "2" ]
  [ "$(tm_field "$output" runs.0.agents.1.cacheWrite)" = "2000" ]
  [ "$(tm_field "$output" runs.0.agents.1.cacheRead)" = "62000" ]
  [ "$(tm_field "$output" runs.0.agents.1.out)" = "500" ]
  [ "$(tm_field "$output" runs.0.agents.1.cacheReadText)" = "62.0k" ]
  [ "$(tm_field "$output" totals.cacheRead)" = "103000" ]
}

@test "a stage's entry in phases[] sums its agents' requests and cache" {
  run tm_metrics home-a --session 12121212-1212-1212-1212-121212121212
  [ "$(tm_field "$output" runs.0.phases.0.title)" = "Reproduce" ]
  [ "$(tm_field "$output" runs.0.phases.0.reqs)" = "2" ]
  [ "$(tm_field "$output" runs.0.phases.0.cacheWrite)" = "1500" ]
  [ "$(tm_field "$output" runs.0.phases.0.cacheRead)" = "41000" ]
  [ "$(tm_field "$output" runs.0.phases.0.cacheWriteText)" = "1.5k" ]
  [ "$(tm_field "$output" runs.0.phases.0.cacheReadText)" = "41.0k" ]
}

@test "md prints an agent's requests and cache on its row" {
  run tm_metrics home-a --session 12121212-1212-1212-1212-121212121212 --format md
  [ "$status" -eq 0 ]
  tm_contains "$output" "| Reproduce | fixture-diagnostics | claude-opus-5 | 2 | 200 | 21.5k | 1.5k | 41.0k | 3 | 1m 00s |"
}

@test "json carries print-ready strings beside the raw numbers" {
  run tm_metrics home-a --session 11111111-1111-1111-1111-111111111111 --run wf_aaa1111-111
  [ "$status" -eq 0 ]
  [ "$(tm_field "$output" runs.0.agents.0.ctxText)" = "312.0k" ]
  [ "$(tm_field "$output" runs.0.agents.0.elapsedText)" = "1m 04s" ]
  [ "$(tm_field "$output" totals.outText)" = "1.1k" ]
}

@test "human_time renders an hour component for long-running agents" {
  local cfg
  cfg="$(mktemp -d)"
  mkdir -p "$cfg/projects/-tmp-proj/99999999-9999-9999-9999-999999999999/workflows"
  cat > "$cfg/projects/-tmp-proj/99999999-9999-9999-9999-999999999999/workflows/wf_hour0000-000.json" <<'JSON'
{
  "runId": "wf_hour0000-000", "workflowName": "profile-refactor", "status": "completed",
  "args": {"task_id": "099", "profile": "refactor"}, "phases": [{"title": "Analyze"}],
  "workflowProgress": [
    {"type": "workflow_phase", "index": 1, "title": "Analyze"},
    {"type": "workflow_agent", "index": 1, "label": "analyze", "phaseIndex": 1,
     "phaseTitle": "Analyze", "agentId": "f0000000000000001",
     "agentType": "fixture-platform:fixture-architect", "model": "claude-opus-5",
     "state": "done", "durationMs": 3661000}
  ]
}
JSON
  run env CLAUDE_CONFIG_DIR="$cfg" CLAUDE_CODE_SESSION_ID="" \
      "$(tm_repo_root)/scripts/agent-metrics.sh" --session 99999999-9999-9999-9999-999999999999
  rm -rf "$cfg"
  [ "$status" -eq 0 ]
  [ "$(tm_field "$output" runs.0.agents.0.elapsedText)" = "1h 01m 01s" ]
}

@test "a truncated trailing line is skipped, not fatal" {
  run tm_metrics home-a --session 11111111-1111-1111-1111-111111111111 --run wf_bbb2222-222
  [ "$status" -eq 0 ]
  [ "$(tm_field "$output" runs.0.agents.0.out)" = "300" ]
  [ "$(tm_field "$output" runs.0.agents.0.tools)" = "1" ]
}

@test "started without result means running, and type comes from meta" {
  run tm_metrics home-a --session 11111111-1111-1111-1111-111111111111 --run wf_bbb2222-222
  [ "$(tm_field "$output" runs.0.agents.0.state)" = "running" ]
  [ "$(tm_field "$output" runs.0.agents.0.agentType)" = "fixture-platform:fixture-developer" ]
}

@test "a workflowProgress state of progress normalizes to running" {
  run tm_metrics home-a --session 11111111-1111-1111-1111-111111111111 --run wf_ccc3333-333
  [ "$status" -eq 0 ]
  [ "$(tm_field "$output" runs.0.agents.0.state)" = "running" ]
}

@test "elapsed for a running agent prefers lastProgressAt over now, and stays fixed" {
  # wf_ccc3333-333's agent carries startedAt 1787219600000 and lastProgressAt
  # 1787219650000 — a fixed 50s gap. A stale/killed agent still marked
  # "running" must report how long it actually worked, not now() - startedAt,
  # which would grow every time this test runs.
  run tm_metrics home-a --session 11111111-1111-1111-1111-111111111111 --run wf_ccc3333-333
  [ "$status" -eq 0 ]
  [ "$(tm_field "$output" runs.0.agents.0.elapsedMs)" = "50000" ]
  [ "$(tm_field "$output" runs.0.agents.0.elapsedText)" = "50s" ]
}

@test "a running agent from workflowProgress shows its glyph and tool in the panel" {
  run tm_metrics home-a --session 11111111-1111-1111-1111-111111111111 --run wf_ccc3333-333 --format panel
  [ "$status" -eq 0 ]
  tm_contains "$output" "🔄"
  tm_contains "$output" "Grep"
}

@test "a phase with a running agent shows running, not todo" {
  run tm_metrics home-a --session 11111111-1111-1111-1111-111111111111 --run wf_ccc3333-333
  [ "$(tm_field "$output" runs.0.phases.0.state)" = "running" ]
}

@test "--run selects exactly one run" {
  run tm_metrics home-a --session 11111111-1111-1111-1111-111111111111 --run wf_bbb2222-222
  [ "$(tm_field "$output" runs.0.runId)" = "wf_bbb2222-222" ]
  [ "$(tm_field "$output" totals.agents)" = "1" ]
}

@test "--task selects only that task's runs" {
  # Session 11111111 has three tasks (077, 081, 090) across three runs; only
  # 077's run (wf_aaa1111-111, 2 agents) should survive the filter.
  run tm_metrics home-a --session 11111111-1111-1111-1111-111111111111 --task 077
  [ "$status" -eq 0 ]
  [ "$(tm_run_count "$output")" = "1" ]
  [ "$(tm_field "$output" runs.0.runId)" = "wf_aaa1111-111" ]
  [ "$(tm_field "$output" totals.agents)" = "2" ]
}

@test "--task with a value that matches nothing yields an empty document at exit 0" {
  run tm_metrics home-a --session 11111111-1111-1111-1111-111111111111 --task nope
  [ "$status" -eq 0 ]
  [ "$(tm_field "$output" runs)" = "[]" ]
}

@test "--task with no value exits 2, like the other flags" {
  run tm_metrics home-empty --task
  [ "$status" -eq 2 ]
  tm_contains "$output" "missing value for --task"
}

@test "a session without workflow runs still shows its Task agents" {
  run tm_metrics home-a --session 22222222-2222-2222-2222-222222222222
  [ "$status" -eq 0 ]
  [ "$(tm_field "$output" runs.0.runId)" = "" ]
  [ "$(tm_field "$output" runs.0.agents.0.agentType)" = "fixture-platform:fixture-reviewer" ]
  [ "$(tm_field "$output" runs.0.agents.0.out)" = "512" ]
}

@test "the Task description stands in for a stage name" {
  run tm_metrics home-a --session 22222222-2222-2222-2222-222222222222
  [ "$(tm_field "$output" runs.0.agents.0.phase)" = "Review the diff" ]
}

@test "workflow runs hide direct-dispatch agents unless --all is passed" {
  # 11111111... has 3 workflow runs (2 + 1 + 1 agents = 4) plus one direct-dispatch
  # agent (session-level subagents/agent-*.jsonl) that only --all pulls in.
  run tm_metrics home-a --session 11111111-1111-1111-1111-111111111111
  [ "$(tm_field "$output" totals.agents)" = "4" ]
  run tm_metrics home-a --session 11111111-1111-1111-1111-111111111111 --all
  [ "$(tm_field "$output" totals.agents)" = "5" ]
}

@test "the description of an Agent-named dispatch comes through as the phase" {
  run tm_metrics home-a --session 11111111-1111-1111-1111-111111111111 --all
  [ "$status" -eq 0 ]
  [ "$(tm_field "$output" runs.3.agents.0.phase)" = "Write regression tests" ]
  [ "$(tm_field "$output" runs.3.agents.0.agentType)" = "fixture-platform:fixture-tester" ]
}

@test "totals sum across multiple workflow runs of a session, not just the first" {
  # wf_aaa1111-111 out=1148 (2 agents), wf_bbb2222-222 out=300 (1 agent),
  # wf_ccc3333-333 out=150 (1 agent): 1148 + 300 + 150 = 1598, agents 2+1+1 = 4.
  run tm_metrics home-a --session 11111111-1111-1111-1111-111111111111
  [ "$status" -eq 0 ]
  [ "$(tm_field "$output" totals.agents)" = "4" ]
  [ "$(tm_field "$output" totals.out)" = "1598" ]
}

@test "the direct-dispatch pseudo-run derives status and elapsed from its agents" {
  local cfg sess
  cfg="$(mktemp -d)"
  sess="$cfg/projects/-tmp-proj/77777777-7777-7777-7777-777777777777"
  mkdir -p "$sess/subagents"
  cat > "$cfg/projects/-tmp-proj/77777777-7777-7777-7777-777777777777.jsonl" <<'JSON'
{"type":"assistant","timestamp":"2026-08-24T10:00:00.000Z","message":{"model":"claude-opus-5","usage":{"output_tokens":10},"content":[{"type":"tool_use","id":"tu1","name":"Agent","input":{"subagent_type":"fixture-platform:fixture-developer","description":"Patch the bug"}}]}}
{"type":"user","timestamp":"2026-08-24T10:00:01.000Z","message":{"role":"user","content":[{"type":"tool_result","tool_use_id":"tu1","content":[{"type":"text","text":"agentId: e0000000000000001"}]}]}}
JSON
  cat > "$sess/subagents/agent-e0000000000000001.jsonl" <<'JSON'
{"type":"assistant","agentId":"e0000000000000001","timestamp":"2026-08-24T10:00:10.000Z","message":{"model":"claude-opus-5","usage":{"input_tokens":1,"output_tokens":50},"content":[{"type":"tool_use","id":"tu2","name":"Edit","input":{}}]}}
JSON
  cat > "$sess/subagents/agent-e0000000000000001.meta.json" <<'JSON'
{"agentType": "fixture-platform:fixture-developer", "spawnDepth": 1}
JSON
  touch "$sess/subagents/agent-e0000000000000001.jsonl"
  run env CLAUDE_CONFIG_DIR="$cfg" CLAUDE_CODE_SESSION_ID="" \
      "$(tm_repo_root)/scripts/agent-metrics.sh" \
      --session 77777777-7777-7777-7777-777777777777 --all
  rm -rf "$cfg"
  [ "$status" -eq 0 ]
  [ "$(tm_field "$output" runs.0.status)" = "running" ]
  [ "$(tm_field "$output" runs.0.elapsedMs)" = "0" ]
}

@test "a run in flight is discovered before its state file exists" {
  # Regression: discovery used to glob only workflows/wf_*.json, which is
  # written when a run ENDS. Session 44444444... has a live run under
  # subagents/workflows/ and no workflows/ directory at all — the exact
  # shape observed mid-run — so with the old discovery, runs would be empty.
  run tm_metrics home-a --session 44444444-4444-4444-4444-444444444444
  [ "$status" -eq 0 ]
  [ "$(tm_field "$output" runs.0.runId)" = "wf_9664a933-1b1" ]
}

@test "a run in flight reports its running agent from the meta file and transcript" {
  run tm_metrics home-a --session 44444444-4444-4444-4444-444444444444
  [ "$(tm_field "$output" runs.0.agents.0.state)" = "running" ]
  [ "$(tm_field "$output" runs.0.agents.0.agentType)" = "fixture-platform:fixture-architect" ]
  [ "$(tm_field "$output" runs.0.agents.0.out)" = "469" ]
}

@test "a run in flight derives status and elapsed with no state file to read them from" {
  run tm_metrics home-a --session 44444444-4444-4444-4444-444444444444
  [ "$(tm_field "$output" runs.0.status)" = "running" ]
  [ "$(tm_field "$output" runs.0.elapsedMs)" != "" ]
}

@test "a run in flight shows its running glyph in the panel, not direct dispatch" {
  run tm_metrics home-a --session 44444444-4444-4444-4444-444444444444 --format panel
  [ "$status" -eq 0 ]
  tm_contains "$output" "🔄"
  tm_lacks "$output" "direct dispatch"
}

@test "a session with state files keeps discovering the same runs in the same order" {
  run tm_metrics home-a --session 11111111-1111-1111-1111-111111111111
  [ "$(tm_field "$output" runs.0.runId)" = "wf_aaa1111-111" ]
  [ "$(tm_field "$output" runs.1.runId)" = "wf_bbb2222-222" ]
  [ "$(tm_field "$output" runs.2.runId)" = "wf_ccc3333-333" ]
}

@test "md format prints a table row per agent" {
  run tm_metrics home-a --session 11111111-1111-1111-1111-111111111111 --format md
  [ "$status" -eq 0 ]
  tm_contains "$output" "| Stage | Agent | Tuning | reqs | out | ctx | cache-w | cache-r | tools | time |"
  tm_contains "$output" "| Analyze | fixture-architect | claude-opus-5 |"
  tm_contains "$output" "312.0k"
}

@test "panel format marks state with a glyph and names the running tool" {
  run tm_metrics home-a --session 11111111-1111-1111-1111-111111111111 --run wf_bbb2222-222 --format panel
  [ "$status" -eq 0 ]
  tm_contains "$output" "🔄"
  tm_contains "$output" "fixture-developer"
}

@test "an empty document renders its reason instead of a blank screen" {
  run tm_metrics home-empty --session 99999999-9999-9999-9999-999999999999 --format panel
  [ "$status" -eq 0 ]
  tm_contains "$output" "session directory not found"
}

@test "md and panel formats both print the volume line under the totals line" {
  run tm_metrics home-a --session 11111111-1111-1111-1111-111111111111 --format md
  [ "$status" -eq 0 ]
  tm_contains "$output" "64.3k total · 59.0k cache-read · 3.7k cache-write · 6 in"
  run tm_metrics home-a --session 11111111-1111-1111-1111-111111111111 --format panel
  [ "$status" -eq 0 ]
  tm_contains "$output" "64.3k total · 59.0k cache-read · 3.7k cache-write · 6 in"
}

@test "the volume line is not printed when there are no agents" {
  run tm_metrics home-empty --session 99999999-9999-9999-9999-999999999999 --format md
  [ "$status" -eq 0 ]
  tm_lacks "$output" "cache-read"
  run tm_metrics home-empty --session 99999999-9999-9999-9999-999999999999 --format panel
  [ "$status" -eq 0 ]
  tm_lacks "$output" "cache-read"
}

@test "the volume line is skipped, not printed as em dashes, when total is zero" {
  local cfg
  cfg="$(mktemp -d)"
  mkdir -p "$cfg/projects/-tmp-proj/zz/workflows"
  cat > "$cfg/projects/-tmp-proj/zz/workflows/wf_zero0000-000.json" <<'JSON'
{
  "runId": "wf_zero0000-000", "workflowName": "profile-refactor", "status": "running",
  "args": {"task_id": "999", "profile": "refactor"}, "phases": [{"title": "Analyze"}],
  "workflowProgress": [{"type": "workflow_phase", "index": 1, "title": "Analyze"}]
}
JSON
  run env CLAUDE_CONFIG_DIR="$cfg" CLAUDE_CODE_SESSION_ID="" \
      "$(tm_repo_root)/scripts/agent-metrics.sh" --session zz --format md
  rm -rf "$cfg"
  [ "$status" -eq 0 ]
  tm_lacks "$output" "total ·"
}

@test "the panel prints no cache on a per-agent row" {
  run tm_metrics home-a --session 11111111-1111-1111-1111-111111111111 --format panel
  [ "$status" -eq 0 ]
  tm_lacks "$(echo "$output" | sed '$d' | sed '$d')" "cache"
}

@test "the panel exits on Ctrl-C and stops painting" {
  export CLAUDE_CODE_SESSION_ID=""
  export CLAUDE_CONFIG_DIR="$(tm_home home-a)"
  run tm_pty_interrupt 2 "$(tm_repo_root)/scripts/agent-monitor.sh" \
      --session 11111111-1111-1111-1111-111111111111 --interval 1
  [ "$status" -eq 0 ]
  [ "$output" = "130 0" ]
}

@test "the panel exits 143 on SIGTERM, distinct from Ctrl-C's 130" {
  export CLAUDE_CODE_SESSION_ID=""
  export CLAUDE_CONFIG_DIR="$(tm_home home-a)"
  run tm_pty_signal SIGTERM 2 "$(tm_repo_root)/scripts/agent-monitor.sh" \
      --session 11111111-1111-1111-1111-111111111111 --interval 1
  [ "$status" -eq 0 ]
  [ "$output" = "143 0" ]
}

@test "agent-monitor.sh --interval without a value exits 2, not 1" {
  run "$(tm_repo_root)/scripts/agent-monitor.sh" --interval
  [ "$status" -eq 2 ]
  tm_contains "$output" "missing value for --interval"
}

@test "monitor prints a single snapshot when stdout is not a tty" {
  run env CLAUDE_CONFIG_DIR="$(tm_home home-a)" CLAUDE_CODE_SESSION_ID="" \
      "$(tm_repo_root)/scripts/agent-monitor.sh" \
      --session 11111111-1111-1111-1111-111111111111
  [ "$status" -eq 0 ]
  tm_contains "$output" "fixture-architect"
  tm_lacks "$output" $'\033[?1049h'
}

# ── manual mode: one block per task, not one per stage ──────────────────────
# Session 55555555 has two FINISHED runs of task 261 (Analyze, then Plan), the
# shape a REFACTOR task leaves behind under manual mode's one-run-per-stage dispatch.

@test "two finished runs of the same task fold into one run record" {
  run tm_metrics home-a --session 55555555-5555-5555-5555-555555555555
  [ "$status" -eq 0 ]
  [ "$(tm_run_count "$output")" = "1" ]
  [ "$(tm_field "$output" runs.0.task_id)" = "261" ]
  [ "$(tm_field "$output" runs.0.workflow)" = "profile-refactor" ]
  [ "$(tm_field "$output" runs.0.runId)" = "" ]
  [ "$(tm_field "$output" runs.0.status)" = "completed" ]
  [ "$(tm_field "$output" runs.0.elapsedMs)" = "171000" ]
}

@test "a merged task's folded phases carry their own agent count and tuningText" {
  run tm_metrics home-a --session 55555555-5555-5555-5555-555555555555
  [ "$(tm_field "$output" runs.0.phases.0.agents)" = "1" ]
  [ "$(tm_field "$output" runs.0.phases.0.tuningText)" = "claude-opus-5" ]
  [ "$(tm_field "$output" runs.0.phases.1.agents)" = "1" ]
  [ "$(tm_field "$output" runs.0.phases.1.tuningText)" = "claude-opus-5" ]
}

@test "a merged task's phase list names each phase once, both finished stages done" {
  run tm_metrics home-a --session 55555555-5555-5555-5555-555555555555
  [ "$(python3 -c 'import json,sys; print(len(json.loads(sys.argv[1])["runs"][0]["phases"]))' "$output")" = "3" ]
  [ "$(tm_field "$output" runs.0.phases.0.title)" = "Analyze" ]
  [ "$(tm_field "$output" runs.0.phases.0.state)" = "done" ]
  [ "$(tm_field "$output" runs.0.phases.1.title)" = "Plan" ]
  [ "$(tm_field "$output" runs.0.phases.1.state)" = "done" ]
  [ "$(tm_field "$output" runs.0.phases.2.title)" = "Refactor" ]
  [ "$(tm_field "$output" runs.0.phases.2.state)" = "todo" ]
}

@test "a merged task's agents are both runs' agents, concatenated in chronological order" {
  run tm_metrics home-a --session 55555555-5555-5555-5555-555555555555
  [ "$(python3 -c 'import json,sys; print(len(json.loads(sys.argv[1])["runs"][0]["agents"]))' "$output")" = "2" ]
  [ "$(tm_field "$output" runs.0.agents.0.phase)" = "Analyze" ]
  [ "$(tm_field "$output" runs.0.agents.1.phase)" = "Plan" ]
}

@test "--run still selects exactly one run when its task has other, unmerged runs" {
  run tm_metrics home-a --session 55555555-5555-5555-5555-555555555555 --run wf_9664a933-1b1
  [ "$status" -eq 0 ]
  [ "$(tm_run_count "$output")" = "1" ]
  [ "$(tm_field "$output" runs.0.runId)" = "wf_9664a933-1b1" ]
  # Unmerged: Plan is only done on the sibling run, filtered out here.
  [ "$(tm_field "$output" runs.0.phases.1.state)" = "todo" ]
}

@test "the Method B pseudo-run stays standalone after task-merging is applied" {
  run tm_metrics home-a --session 11111111-1111-1111-1111-111111111111 --all
  [ "$status" -eq 0 ]
  [ "$(tm_run_count "$output")" = "4" ]
  [ "$(tm_field "$output" runs.3.task_id)" = "" ]
  [ "$(tm_field "$output" runs.3.runId)" = "" ]
  [ "$(tm_field "$output" totals.agents)" = "5" ]
}

# ── recovering task/profile/stage from the agent's own prompt ───────────────
# Session 44444444 is a real in-flight run (task 261, stage Analyze) with no
# state file yet — the first line of its agent's prompt is spine-toolkit's own.

@test "an in-flight run recovers task_id, workflow and stage from its own prompt" {
  run tm_metrics home-a --session 44444444-4444-4444-4444-444444444444
  [ "$status" -eq 0 ]
  [ "$(tm_field "$output" runs.0.task_id)" = "261" ]
  [ "$(tm_field "$output" runs.0.workflow)" = "profile-refactor" ]
  [ "$(tm_field "$output" runs.0.agents.0.phase)" = "Analyze" ]
  [ "$(tm_field "$output" runs.0.agents.0.state)" = "running" ]
}

@test "an in-flight run's recovered stage also lands in phases[], not just agents[]" {
  run tm_metrics home-a --session 44444444-4444-4444-4444-444444444444
  [ "$status" -eq 0 ]
  [ "$(tm_field "$output" runs.0.phases.0.title)" = "Analyze" ]
  [ "$(tm_field "$output" runs.0.phases.0.agents)" = "1" ]
  [ "$(tm_field "$output" runs.0.phases.0.tuningText)" != "" ]
}

@test "panel shows the recovered stage name for an in-flight run, not an em dash" {
  run tm_metrics home-a --session 44444444-4444-4444-4444-444444444444 --format panel
  [ "$status" -eq 0 ]
  tm_contains "$output" "Analyze"
}

@test "a prompt that does not match the Task id line leaves task_id and phase null, no crash" {
  run tm_metrics home-a --session 60606060-6060-6060-6060-606060606060
  [ "$status" -eq 0 ]
  [ "$(tm_run_count "$output")" = "1" ]
  [ "$(tm_field "$output" runs.0.task_id)" = "" ]
  [ "$(tm_field "$output" runs.0.agents.0.phase)" = "" ]
}

# One Method A run: Plan on one agent with no effort recorded; Fix on three agents across two
# model-and-effort pairs, the way a light read-plan precedes the phases.
tuning_home() {
  local sess="$1/projects/-tmp-proj/70707070-7070-7070-7070-707070707070"
  local d="$sess/subagents/workflows/wf_tune0000-000"
  mkdir -p "$sess/workflows" "$d"
  cat >"$sess/workflows/wf_tune0000-000.json" <<'JSON'
{
  "runId": "wf_tune0000-000", "workflowName": "profile-bug", "status": "completed",
  "args": {"task_id": "088", "profile": "bug"}, "phases": [{"title": "Plan"}, {"title": "Fix"}],
  "workflowProgress": [
    {"type": "workflow_phase", "index": 1, "title": "Plan"},
    {"type": "workflow_phase", "index": 2, "title": "Fix"},
    {"type": "workflow_agent", "index": 1, "label": "plan", "phaseTitle": "Plan", "agentId": "t0000000000000001",
     "agentType": "fixture-platform:fixture-architect", "model": "claude-opus-5", "state": "done",
     "tokens": 90000, "toolCalls": 10, "durationMs": 60000},
    {"type": "workflow_agent", "index": 2, "label": "fix:read-plan", "phaseTitle": "Fix", "agentId": "t0000000000000002",
     "agentType": "fixture-platform:fixture-developer", "model": "claude-sonnet-5", "state": "done",
     "tokens": 60000, "toolCalls": 2, "durationMs": 10000},
    {"type": "workflow_agent", "index": 3, "label": "fix:1", "phaseTitle": "Fix", "agentId": "t0000000000000003",
     "agentType": "fixture-platform:fixture-developer", "model": "claude-opus-5", "state": "done",
     "tokens": 250000, "toolCalls": 30, "durationMs": 600000},
    {"type": "workflow_agent", "index": 4, "label": "fix:2", "phaseTitle": "Fix", "agentId": "t0000000000000004",
     "agentType": "fixture-platform:fixture-developer", "model": "claude-opus-5", "state": "done",
     "tokens": 200000, "toolCalls": 20, "durationMs": 300000}
  ]
}
JSON
  printf '%s\n' '{"type":"assistant","message":{"model":"claude-opus-5","usage":{"output_tokens":100}}}' >"$d/agent-t0000000000000001.jsonl"
  printf '%s\n' '{"type":"assistant","effort":"low","message":{"model":"claude-sonnet-5","usage":{"output_tokens":20}}}' >"$d/agent-t0000000000000002.jsonl"
  printf '%s\n' '{"type":"assistant","effort":"xhigh","message":{"model":"claude-opus-5","usage":{"output_tokens":300}}}' >"$d/agent-t0000000000000003.jsonl"
  printf '%s\n' '{"type":"assistant","effort":"xhigh","message":{"model":"claude-opus-5","usage":{"output_tokens":200}}}' >"$d/agent-t0000000000000004.jsonl"
}

tuning_metrics() {
  env CLAUDE_CONFIG_DIR="$1" CLAUDE_CODE_SESSION_ID="" \
    "$(tm_repo_root)/scripts/agent-metrics.sh" --session 70707070-7070-7070-7070-707070707070 "${@:2}"
}

@test "an agent record carries the effort its transcript recorded, and null when none" {
  local cfg; cfg="$(mktemp -d)"; tuning_home "$cfg"
  run tuning_metrics "$cfg"
  rm -rf "$cfg"
  [ "$status" -eq 0 ]
  [ "$(tm_field "$output" runs.0.agents.1.effort)" = "low" ]
  [ "$(tm_field "$output" runs.0.agents.0.effort)" = "" ]
  [ "$(tm_field "$output" runs.0.agents.1.tuningText)" = "claude-sonnet-5 low" ]
}

@test "a phase folds its agents: pairs in order of appearance, sums, and the largest context" {
  local cfg; cfg="$(mktemp -d)"; tuning_home "$cfg"
  run tuning_metrics "$cfg"
  rm -rf "$cfg"
  [ "$status" -eq 0 ]
  [ "$(tm_field "$output" runs.0.phases.1.agents)" = "3" ]
  [ "$(tm_field "$output" runs.0.phases.1.tuningText)" = "claude-sonnet-5 low + claude-opus-5 xhigh ×2" ]
  [ "$(tm_field "$output" runs.0.phases.1.tuning.1.agents)" = "2" ]
  [ "$(tm_field "$output" runs.0.phases.1.out)" = "520" ]
  [ "$(tm_field "$output" runs.0.phases.1.tools)" = "52" ]
  [ "$(tm_field "$output" runs.0.phases.1.ctxText)" = "250.0k" ]
  [ "$(tm_field "$output" runs.0.phases.1.elapsedText)" = "15m 10s" ]
  [ "$(tm_field "$output" runs.0.phases.0.tuningText)" = "claude-opus-5" ]
}

@test "the panel shows each agent's model and effort" {
  local cfg; cfg="$(mktemp -d)"; tuning_home "$cfg"
  run tuning_metrics "$cfg" --format panel
  rm -rf "$cfg"
  [ "$status" -eq 0 ]
  # The panel shortens the model (drops the claude- prefix), unlike tuningText in JSON/md.
  tm_contains "$output" "sonnet-5 low"
  tm_contains "$output" "opus-5 xhigh"
}

long_model_home() {
  local sess="$1/projects/-tmp-proj/80808080-8080-8080-8080-808080808080"
  local d="$sess/subagents/workflows/wf_long0000-000"
  mkdir -p "$sess/workflows" "$d"
  cat >"$sess/workflows/wf_long0000-000.json" <<'JSON'
{
  "runId": "wf_long0000-000", "workflowName": "profile-bug", "status": "completed",
  "args": {"task_id": "089", "profile": "bug"}, "phases": [{"title": "Fix"}],
  "workflowProgress": [
    {"type": "workflow_phase", "index": 1, "title": "Fix"},
    {"type": "workflow_agent", "index": 1, "label": "fix:1", "phaseTitle": "Fix", "agentId": "l0000000000000001",
     "agentType": "fixture-platform:fixture-developer", "model": "claude-haiku-4-5-20251001", "state": "done",
     "tokens": 50000, "toolCalls": 5, "durationMs": 20000}
  ]
}
JSON
  printf '%s\n' '{"type":"assistant","effort":"high","message":{"model":"claude-haiku-4-5-20251001","usage":{"output_tokens":50}}}' >"$d/agent-l0000000000000001.jsonl"
}

@test "the panel shortens a long model id instead of cutting off the effort" {
  local cfg; cfg="$(mktemp -d)"; long_model_home "$cfg"
  run env CLAUDE_CONFIG_DIR="$cfg" CLAUDE_CODE_SESSION_ID="" \
    "$(tm_repo_root)/scripts/agent-metrics.sh" --session 80808080-8080-8080-8080-808080808080 --format panel
  rm -rf "$cfg"
  [ "$status" -eq 0 ]
  tm_contains "$output" "haiku-4-5 high"
  tm_lacks "$output" "2025100"
}

# ── task 700: wall-clock span per stage, a task's runs across sessions ─────
# Session 70707070 holds the Execute run and the Validation run (two agents in
# parallel); session 71717171, a day later, holds Review and a fix-review run
# with Execute and Validation.

@test "an agent record carries startedMs from its run state" {
  run tm_metrics home-a --session "$T700_A" --run wf_t700exe-a01
  [ "$(tm_field "$output" runs.0.agents.0.startedMs)" = "1787300000000" ]
}

@test "startedMs falls back to the transcript's first timestamp" {
  run tm_metrics home-a --session 44444444-4444-4444-4444-444444444444
  [ "$(tm_field "$output" runs.0.agents.0.startedMs)" = "1787585133000" ]
}

@test "a run carries its action from args.action, and null without one" {
  run tm_metrics home-a --session "$T700_B" --run wf_t700fix-b02
  [ "$(tm_field "$output" runs.0.action)" = "fix-review" ]
  run tm_metrics home-a --session 55555555-5555-5555-5555-555555555555 --run wf_9664a933-1b1
  [ "$(field_json "$output" runs.0.action)" = "null" ]
}

@test "--project-sessions gathers a task's runs from every session of the project" {
  run tm_metrics home-a --session "$T700_B" --task 700 --project-sessions
  [ "$status" -eq 0 ]
  [ "$(tm_field "$output" totals.runs)" = "4" ]
  [ "$(tm_field "$output" totals.agents)" = "6" ]
  [ "$(tm_field "$output" runs.0.agents.0.agentId)" = "f0000000000000001" ]
  [ "$(tm_field "$output" runs.0.agents.5.agentId)" = "f0000000000000006" ]
  run tm_metrics home-a --session "$T700_B" --task 700
  [ "$(tm_field "$output" totals.runs)" = "2" ]
  [ "$(tm_field "$output" totals.agents)" = "3" ]
}

@test "--project-sessions with no --session walks the sessions under the current folder's slug" {
  local cfg proj slug
  cfg="$(mktemp -d)"
  proj="$(cd -- "$(mktemp -d)" && pwd -P)"
  slug="$(printf '%s' "$proj" | tr -c 'A-Za-z0-9' '-')"
  mkdir -p "$cfg/projects/$slug"
  cp -R "$(tm_home home-a)/projects/-tmp-proj/$T700_A" "$(tm_home home-a)/projects/-tmp-proj/$T700_B" \
        "$cfg/projects/$slug/"
  touch -t 202601030000 "$cfg/projects/$slug/$T700_A/workflows/wf_t700exe-a01.json"
  touch -t 202601030010 "$cfg/projects/$slug/$T700_A/workflows/wf_t700val-a02.json"
  touch -t 202601040000 "$cfg/projects/$slug/$T700_B/workflows/wf_t700rev-b01.json"
  touch -t 202601040010 "$cfg/projects/$slug/$T700_B/workflows/wf_t700fix-b02.json"
  touch -t 202601030020 "$cfg/projects/$slug/$T700_A"
  touch -t 202601040020 "$cfg/projects/$slug/$T700_B"
  run env CLAUDE_CONFIG_DIR="$cfg" CLAUDE_CODE_SESSION_ID="" \
      bash -c "cd '$proj' && '$(tm_repo_root)/scripts/agent-metrics.sh' --task 700 --project-sessions"
  local all="$output"
  run env CLAUDE_CONFIG_DIR="$cfg" CLAUDE_CODE_SESSION_ID="" \
      bash -c "cd '$proj' && '$(tm_repo_root)/scripts/agent-metrics.sh' --task 700"
  rm -rf "$cfg" "$proj"
  [ "$(tm_field "$all" totals.runs)" = "4" ]
  [ "$(tm_field "$all" session)" = "$T700_B" ]
  [ "$(tm_field "$output" totals.runs)" = "2" ]
}

@test "--project-sessions without --task changes nothing" {
  run tm_metrics home-a --session "$T700_B" --project-sessions
  [ "$status" -eq 0 ]
  local with="$output"
  run tm_metrics home-a --session "$T700_B"
  [ "$with" = "$output" ]
}

@test "a parallel stage's span is shorter than its summed elapsed" {
  run tm_metrics home-a --session "$T700_A" --run wf_t700val-a02
  [ "$(tm_field "$output" runs.0.phases.1.title)" = "Validation" ]
  [ "$(tm_field "$output" runs.0.phases.1.elapsedMs)" = "660000" ]
  [ "$(tm_field "$output" runs.0.phases.1.spanMs)" = "420000" ]
  [ "$(tm_field "$output" runs.0.phases.1.spanText)" = "7m 00s" ]
}

@test "a phase with no agent has a null span" {
  run tm_metrics home-a --session "$T700_A" --run wf_t700exe-a01
  [ "$(tm_field "$output" runs.0.phases.2.title)" = "Review" ]
  [ "$(field_json "$output" runs.0.phases.2.spanMs)" = "null" ]
  [ "$(field_json "$output" runs.0.phases.2.spanText)" = "null" ]
}

@test "a stage that ran in two runs sums its spans, not the gap between them" {
  run tm_metrics home-a --session "$T700_B" --task 700 --project-sessions
  # The folded record: Validation's 7m in the first session plus 2m in the fix round.
  [ "$(tm_field "$output" runs.0.phases.1.title)" = "Validation" ]
  [ "$(tm_field "$output" runs.0.phases.1.spanMs)" = "540000" ]
  [ "$(tm_field "$output" totals.stageSpans.Execute)" = "600000" ]
  [ "$(tm_field "$output" totals.stageSpans.Validation)" = "420000" ]
  [ "$(tm_field "$output" totals.stageSpans.Review)" = "240000" ]
  [ "$(tm_field "$output" totals.fixSpanMs)" = "300000" ]
}

# untimed_agent <config dir>: task 700's sessions with a third Validation agent in wf_t700val-a02
# that has no startedAt, no durationMs and no transcript, so it has no place on the clock.
untimed_agent() {
  cp -R "$(tm_home home-a)/." "$1/"
  python3 - "$1/projects/-tmp-proj/$T700_A/workflows/wf_t700val-a02.json" <<'PY'
import json, sys
path = sys.argv[1]
run = json.load(open(path))
run["workflowProgress"].append({"type": "workflow_agent", "index": 1, "label": "validate-ui",
    "phaseTitle": "Validation", "agentId": "f0000000000000098",
    "agentType": "fixture-platform:fixture-validator", "model": "claude-opus-5", "state": "done"})
json.dump(run, open(path, "w"))
PY
}

@test "a phase with an untimed agent says how many, and the task totals name its stage" {
  local cfg; cfg="$(mktemp -d)"; untimed_agent "$cfg"
  run env CLAUDE_CONFIG_DIR="$cfg" CLAUDE_CODE_SESSION_ID="" \
    "$(tm_repo_root)/scripts/agent-metrics.sh" --session "$T700_A" --run wf_t700val-a02
  local one="$output"
  run env CLAUDE_CONFIG_DIR="$cfg" CLAUDE_CODE_SESSION_ID="" \
    "$(tm_repo_root)/scripts/agent-metrics.sh" --session "$T700_B" --task 700 --project-sessions
  rm -rf "$cfg"
  [ "$(tm_field "$one" runs.0.phases.1.title)" = "Validation" ]
  [ "$(tm_field "$one" runs.0.phases.1.untimed)" = "1" ]
  [ "$(tm_field "$one" runs.0.phases.0.untimed)" = "0" ]
  [ "$status" -eq 0 ] || { echo "$output"; return 1; }
  [ "$(tm_field "$output" totals.untimedStages.Validation)" = "1" ]
  [ "$(python3 -c 'import json,sys; print(sorted(json.loads(sys.argv[1])["totals"]["untimedStages"]))' "$output")" = "['Validation']" ]
}

@test "with every agent timed the task totals carry an empty untimedStages" {
  run tm_metrics home-a --session "$T700_B" --task 700 --project-sessions
  [ "$(field_json "$output" totals.untimedStages)" = "{}" ]
}

@test "fixRounds counts fix-review runs with an Execute" {
  run tm_metrics home-a --session "$T700_B" --task 700 --project-sessions
  [ "$(tm_field "$output" totals.fixRounds)" = "1" ]
}

# live_fix_round <config dir>: task 700's sessions plus, in session 71717171, a fix-review round
# still in flight — Execute 3m, Validation 2m, Review 1m — with no workflows/wf_*.json, only its
# subagents/workflows/<rid> dir, the shape a Done stage of an auto fix-review run measures.
live_fix_round() {
  cp -R "$(tm_home home-a)/." "$1/"
  local run="$1/projects/-tmp-proj/$T700_B/subagents/workflows/wf_t700liv-b04" n=0 stage start end
  mkdir -p "$run"
  : >"$run/journal.jsonl"
  for stage in Execute:10:13 Validation:13:15 Review:15:16; do
    n=$((n + 1))
    IFS=: read -r stage start end <<<"$stage"
    local id="f00000000000001$n"
    printf '{"agentType":"fixture-platform:fixture-architect","spawnDepth":1}\n' >"$run/agent-$id.meta.json"
    {
      printf '{"type":"user","agentId":"%s","timestamp":"2026-08-25T10:%02d:00.000Z","message":{"role":"user","content":"Task folder: Tasks/ACTIVE/700-x\\nTask id: 700 — profile FEATURE, stage %s.\\n[rest omitted]"}}\n' "$id" "$start" "$stage"
      printf '{"type":"assistant","agentId":"%s","timestamp":"2026-08-25T10:%02d:00.000Z","message":{"model":"claude-opus-5","usage":{"input_tokens":1,"cache_creation_input_tokens":0,"cache_read_input_tokens":0,"output_tokens":1},"content":[{"type":"text","text":"done"}]}}\n' "$id" "$end"
    } >"$run/agent-$id.jsonl"
    printf '{"type":"started","agentId":"%s"}\n{"type":"result","agentId":"%s","result":{"summary":"s"}}\n' "$id" "$id" >>"$run/journal.jsonl"
  done
  touch -t 202601040030 "$run"
}

@test "--live-action fix-review counts a fix round still in flight as a fix round" {
  local cfg; cfg="$(mktemp -d)"; live_fix_round "$cfg"
  run env CLAUDE_CONFIG_DIR="$cfg" CLAUDE_CODE_SESSION_ID="" \
    "$(tm_repo_root)/scripts/agent-metrics.sh" --session "$T700_B" --task 700 --project-sessions --live-action fix-review
  local with="$output" with_status="$status"
  run env CLAUDE_CONFIG_DIR="$cfg" CLAUDE_CODE_SESSION_ID="" \
    "$(tm_repo_root)/scripts/agent-metrics.sh" --session "$T700_B" --task 700 --project-sessions
  rm -rf "$cfg"
  [ "$with_status" -eq 0 ] || { echo "$with"; return 1; }
  [ "$(tm_field "$with" totals.runs)" = "5" ]
  [ "$(tm_field "$with" totals.fixRounds)" = "2" ]
  [ "$(tm_field "$with" totals.fixSpanMs)" = "660000" ]
  [ "$(tm_field "$with" totals.stageSpans.Execute)" = "600000" ]
  [ "$(tm_field "$with" totals.stageSpans.Validation)" = "420000" ]
  [ "$(tm_field "$with" totals.stageSpans.Review)" = "240000" ]
  # Without the flag the live run has no action, and its stages count as the stages' own time.
  [ "$status" -eq 0 ] || { echo "$output"; return 1; }
  [ "$(tm_field "$output" totals.runs)" = "5" ]
  [ "$(tm_field "$output" totals.fixRounds)" = "1" ]
  [ "$(tm_field "$output" totals.fixSpanMs)" = "300000" ]
  [ "$(tm_field "$output" totals.stageSpans.Execute)" = "780000" ]
  [ "$(tm_field "$output" totals.stageSpans.Validation)" = "540000" ]
  [ "$(tm_field "$output" totals.stageSpans.Review)" = "300000" ]
}

@test "--live-action leaves a run with a state file as its state file says" {
  run tm_metrics home-a --session "$T700_B" --task 700 --project-sessions --live-action fix-review
  [ "$status" -eq 0 ]
  [ "$(tm_field "$output" totals.fixRounds)" = "1" ]
  [ "$(tm_field "$output" totals.stageSpans.Review)" = "240000" ]
  [ "$(tm_field "$output" totals.fixSpanMs)" = "300000" ]
}

@test "the task totals are only there with --task" {
  run tm_metrics home-a --session "$T700_B"
  [ "$(python3 -c 'import json,sys; t=json.loads(sys.argv[1])["totals"]; print(sorted(set(t) & {"runs","stageSpans","fixRounds","fixSpanMs","gateRuns"}))' "$output")" = "[]" ]
}

@test "gateRuns counts the runs with an agent in Execute, Validation or Review, fix rounds included, not a Plan-only run" {
  local cfg; cfg="$(mktemp -d)"
  cp -R "$(tm_home home-a)/." "$cfg/"
  cat >"$cfg/projects/-tmp-proj/$T700_B/workflows/wf_t700pln-b03.json" <<'JSON'
{
  "runId": "wf_t700pln-b03", "workflowName": "profile-feature", "status": "completed",
  "startTime": 1787380000000, "durationMs": 120000,
  "args": {"task_id": "700", "profile": "feature", "action": "run"},
  "phases": [{"title": "Plan"}],
  "workflowProgress": [
    {"type": "workflow_phase", "index": 1, "title": "Plan"},
    {"type": "workflow_agent", "index": 1, "label": "plan", "phaseTitle": "Plan",
     "agentId": "f0000000000000099", "agentType": "fixture-platform:fixture-architect", "model": "claude-opus-5",
     "state": "done", "startedAt": 1787380000000, "tokens": 1000, "toolCalls": 2, "durationMs": 120000}
  ]
}
JSON
  run env CLAUDE_CONFIG_DIR="$cfg" CLAUDE_CODE_SESSION_ID="" \
    "$(tm_repo_root)/scripts/agent-metrics.sh" --session "$T700_B" --task 700 --project-sessions
  rm -rf "$cfg"
  [ "$status" -eq 0 ] || { echo "$output"; return 1; }
  [ "$(tm_field "$output" totals.runs)" = "5" ]
  [ "$(tm_field "$output" totals.gateRuns)" = "4" ]
}

@test "gateRuns of the task-700 fixture as it stands" {
  run tm_metrics home-a --session "$T700_B" --task 700 --project-sessions
  [ "$(tm_field "$output" totals.gateRuns)" = "4" ]
  run tm_metrics home-a --session "$T700_B" --task 700
  [ "$(tm_field "$output" totals.gateRuns)" = "2" ]
}

@test "the usage line names --project-sessions and --live-action" {
  run tm_metrics home-empty --help
  tm_contains "$output" "--project-sessions"
  tm_contains "$output" "--live-action"
}

@test "--project-sessions names a sibling session it could not read, and still counts the others" {
  # Session 33333333 sits beside task 700's sessions with a state file of the wrong shape.
  run tm_metrics home-a --session "$T700_B" --task 700 --project-sessions
  [ "$status" -eq 0 ]
  [ "$(field_json "$output" totals.skippedSessions)" = '["33333333-3333-3333-3333-333333333333"]' ]
  [ "$(tm_field "$output" totals.runs)" = "4" ]
  [ "$(tm_field "$output" totals.fixRounds)" = "1" ]
}

@test "skippedSessions is an empty list when every session was read" {
  run tm_metrics home-a --session "$T700_B" --task 700
  [ "$(field_json "$output" totals.skippedSessions)" = "[]" ]
}
