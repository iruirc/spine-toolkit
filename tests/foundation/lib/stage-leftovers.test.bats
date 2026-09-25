#!/usr/bin/env bats
# A stage left a test build running for 1h47m and a WebDriverAgent for 45m, changed a committed
# fixture, and sat 15 minutes on a silent MCP call; each was found by a person, not the toolkit.

setup() {
  ROOT="$(cd -- "$(dirname -- "$BATS_TEST_FILENAME")/../../.." && pwd)"
  SL="$ROOT/scripts/stage-leftovers.sh"
  T="$BATS_TEST_TMPDIR"
  export STAGE_LEFTOVERS_SESSION_PID=100 STAGE_LEFTOVERS_PS="$T/ps" LONG_RUN_REGISTRY="$T/registry"
  export STAGE_LEFTOVERS_NOW="$(date -j -f '%a %b %d %H:%M:%S %Y' 'Fri Sep 25 15:00:00 2026' +%s 2>/dev/null \
    || date -d 'Fri Sep 25 15:00:00 2026' +%s)"
  : >"$LONG_RUN_REGISTRY"
}

# One ps row: pid ppid lstart-time command. The day is fixed; only the clock time varies.
row() { printf '%s %s 0.0 Fri Sep 25 %s 2026 %s\n' "$1" "$2" "$3" "$4"; }

before() {
  { row 100 1 09:00:00 claude
    row 110 100 09:00:01 'node xcodebuildmcp'
    row 120 100 09:00:01 'npm exec claude-in-mobile'
    row 121 120 09:00:02 'node claude-in-mobile'
    row 200 1 09:00:00 claude
    row 210 200 09:00:01 'node xcodebuildmcp'; } >"$T/ps"
}

snap() { "$SL" snap --out "$T/snap" "$@"; }

@test "a build the stage left under an MCP server is shown, once, at the top of its subtree" {
  before; snap
  { row 111 110 14:00:00 'xcodebuild test -scheme App'
    row 112 111 14:00:05 'xctest App'; } >>"$T/ps"
  run "$SL" diff "$T/snap"
  [ "$status" -eq 1 ] || { echo "$output"; return 1; }
  [[ "$output" == "process pid=111 start="*" age=1h00m parent=110 cmd=xcodebuild test -scheme App" ]] \
    || { echo "$output"; return 1; }
}

@test "a process that was there before the stage is not shown" {
  before; row 111 110 08:00:00 'xcodebuild test' >>"$T/ps"; snap
  run "$SL" diff "$T/snap"
  [ "$status" -eq 0 ] && [ -z "$output" ] || { echo "$output"; return 1; }
}

@test "a direct child of claude is not shown: Claude Code starts those itself" {
  before; snap
  row 130 100 14:00:00 'node new-mcp-server' >>"$T/ps"
  run "$SL" diff "$T/snap"
  [ "$status" -eq 0 ] || { echo "$output"; return 1; }
}

@test "a build in another session's subtree is not shown" {
  before; snap
  row 211 210 14:00:00 'xcodebuild test' >>"$T/ps"
  run "$SL" diff "$T/snap"
  [ "$status" -eq 0 ] || { echo "$output"; return 1; }
}

@test "a pid reused by a new process is shown" {
  before; row 111 110 08:00:00 'xcodebuild old' >>"$T/ps"; snap
  sed -i.bak 's/^111 110 0.0 Fri Sep 25 08:00:00 2026 xcodebuild old$/111 110 0.0 Fri Sep 25 14:30:00 2026 xcodebuild new/' "$T/ps"
  run "$SL" diff "$T/snap"
  [ "$status" -eq 1 ] && [[ "$output" == *"pid=111 "*"cmd=xcodebuild new"* ]] || { echo "$output"; return 1; }
}

@test "a long-run job started after the snapshot and still running is shown" {
  before; snap
  row 300 1 14:10:00 'bash -c xcodebuild test' >>"$T/ps"
  echo "300 $STAGE_LEFTOVERS_NOW $T/run.log" >>"$LONG_RUN_REGISTRY"
  run "$SL" diff "$T/snap"
  [ "$status" -eq 1 ] && [[ "$output" == "process pid=300 "*"parent=1 "* ]] || { echo "$output"; return 1; }
}

@test "a long-run job started in the snapshot's own second is shown" {
  export STAGE_LEFTOVERS_NOW="$STAGE_LEFTOVERS_NOW.7"
  before; snap
  row 300 1 14:10:00 'bash -c xcodebuild test' >>"$T/ps"
  echo "300 ${STAGE_LEFTOVERS_NOW%.*} $T/run.log" >>"$LONG_RUN_REGISTRY"
  run "$SL" diff "$T/snap"
  [ "$status" -eq 1 ] || { echo "a job registered in the same whole second was missed: $output"; return 1; }
}

@test "a long-run job that finished, or started before the snapshot, is not shown" {
  before; snap
  { row 300 1 14:10:00 'bash -c done'; row 301 1 08:00:00 'bash -c old'; } >>"$T/ps"
  touch "$T/done.log.exit"
  { echo "300 $STAGE_LEFTOVERS_NOW $T/done.log"; echo "301 1 $T/old.log"; } >>"$LONG_RUN_REGISTRY"
  run "$SL" diff "$T/snap"
  [ "$status" -eq 0 ] || { echo "$output"; return 1; }
}

repo() {
  git init -q "$T/repo" && cd "$T/repo"
  printf 'a\n' >kept; printf 'b\n' >fixture.sqlite; printf 'c\n' >gone
  git add . && git -c user.email=t@t -c user.name=t commit -qm init
  printf 'local\n' >kept   # dirty before the stage: local dependency mode rewrote it
}

@test "a file the stage changed is shown; one dirty before and untouched is not" {
  before; repo; snap --root "$T/repo"
  printf 'shm\n' >fixture.sqlite; rm gone; printf 'n\n' >new
  run "$SL" diff "$T/snap"
  [ "$status" -eq 1 ] || { echo "$output"; return 1; }
  [ "$output" = "tree root=$T/repo path=fixture.sqlite change=modified
tree root=$T/repo path=gone change=deleted
tree root=$T/repo path=new change=added" ] || { echo "$output"; return 1; }
}

@test "a file dirty before the stage and changed again during it is shown" {
  before; repo; snap --root "$T/repo"
  printf 'again\n' >kept
  run "$SL" diff "$T/snap"
  [ "$output" = "tree root=$T/repo path=kept change=modified" ] || { echo "$output"; return 1; }
}

@test "the task folder is excluded" {
  before; repo; mkdir -p Tasks/ACTIVE/042; snap --root "$T/repo" --exclude "$T/repo/Tasks/ACTIVE/042"
  printf 'x\n' >Tasks/ACTIVE/042/Validation.md
  run "$SL" diff "$T/snap"
  [ "$status" -eq 0 ] || { echo "$output"; return 1; }
}

@test "kill leaves alone a pid now held by another process" {
  before
  run "$SL" kill "121:1"
  [ "$status" -eq 0 ] && [ "$output" = "gone pid=121" ] || { echo "$output"; return 1; }
}

# A transcript whose last call is <tool>, made <ago> seconds before now, answered or not.
transcript() {
  local t; t="$(date -u -r $(( STAGE_LEFTOVERS_NOW - $3 )) +%Y-%m-%dT%H:%M:%S.000Z 2>/dev/null \
    || date -u -d "@$(( STAGE_LEFTOVERS_NOW - $3 ))" +%Y-%m-%dT%H:%M:%S.000Z)"
  mkdir -p "$T/wf"
  printf '{"type":"assistant","timestamp":"%s","message":{"content":[{"type":"tool_use","id":"t1","name":"%s"}]}}\n' "$t" "$2" >"$T/wf/agent-$1.jsonl"
  [ "$4" = answered ] && printf '{"type":"user","timestamp":"%s","message":{"content":[{"type":"tool_result","tool_use_id":"t1"}]}}\n' "$t" >>"$T/wf/agent-$1.jsonl"
  return 0
}

@test "an MCP call unanswered past --stall wakes the orchestrator with exit 4" {
  before; row 111 110 14:00:00 'xcodebuild test' >>"$T/ps"
  transcript a1 mcp__XcodeBuildMCP__test_sim 900 pending
  run "$SL" watch --dir "$T/wf" --stall 300 --idle 99999
  [ "$status" -eq 4 ] || { echo "$output"; return 1; }
  [ "${lines[0]}" = "hung agent=a1 tool=mcp__XcodeBuildMCP__test_sim age=15m" ] || { echo "$output"; return 1; }
  [[ "$output" == *"proc pid=111 "*"cmd=xcodebuild test"* ]] || { echo "the process under the call is missing: $output"; return 1; }
}

@test "an answered call, a young call or a Bash call does not wake it" {
  before
  export STAGE_LEFTOVERS_POLL=0
  for c in "mcp__x__y 900 answered" "mcp__x__y 60 pending" "Bash 900 pending"; do
    set -- $c
    transcript a1 "$1" "$2" "$3"
    touch -t 200001010000 "$T/wf/agent-a1.jsonl" "$T/wf"
    run "$SL" watch --dir "$T/wf" --stall 300 --idle 1
    [ "$status" -eq 5 ] || { echo "$c: $output"; return 1; }
  done
}
