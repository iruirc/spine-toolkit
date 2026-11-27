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
  ME="$(id -u)"
}

# One ps row: pid ppid lstart-time command. The day is fixed; only the clock time varies. The
# process leads its own group and belongs to this user unless PG or U says otherwise.
row() { printf '%s %s %s %s 0.0 Fri Sep 25 %s 2026 %s\n' "$1" "$2" "${PG:-$1}" "${U:-$ME}" "$3" "$4"; }
# A process under PID 1 whose group's leader was another process: orow pid pgid time command.
orow() { PG="$2" row "$1" 1 "$3" "$4"; }

before() {
  { row 100 1 09:00:00 claude
    row 110 100 09:00:01 'node xcodebuildmcp'
    row 120 100 09:00:01 'npm exec claude-in-mobile'
    row 121 120 09:00:02 'node claude-in-mobile'
    row 200 1 09:00:00 claude
    row 210 200 09:00:01 'node xcodebuildmcp'; } >"$T/ps"
}

snap() { "$SL" snap --out "$T/snap" "$@"; }

@test "diff takes the file with the --out it was snapped with" {
  before; snap
  { row 111 110 14:00:00 'xcodebuild test -scheme App'; } >>"$T/ps"
  run "$SL" diff --out "$T/snap"
  [ "$status" -eq 1 ] || { echo "$output"; return 1; }
  [[ "$output" == "process pid=111 "* ]] || { echo "$output"; return 1; }
}

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
  sed -i.bak "s/^111 110 111 $ME 0.0 Fri Sep 25 08:00:00 2026 xcodebuild old\$/111 110 111 $ME 0.0 Fri Sep 25 14:30:00 2026 xcodebuild new/" "$T/ps"
  run "$SL" diff "$T/snap"
  [ "$status" -eq 1 ] && [[ "$output" == *"pid=111 "*"cmd=xcodebuild new"* ]] || { echo "$output"; return 1; }
}

@test "a long-run job started after the snapshot and still running is shown" {
  before; snap
  row 300 1 15:00:00 'bash -c xcodebuild test' >>"$T/ps"
  echo "300 $STAGE_LEFTOVERS_NOW 100 $T/run.log" >>"$LONG_RUN_REGISTRY"
  run "$SL" diff "$T/snap"
  [ "$status" -eq 1 ] && [[ "$output" == "process pid=300 "*"parent=1 "* ]] || { echo "$output"; return 1; }
}

@test "a long-run job started in the snapshot's own second is shown" {
  export STAGE_LEFTOVERS_NOW="$STAGE_LEFTOVERS_NOW.7"
  before; snap
  row 300 1 15:00:00 'bash -c xcodebuild test' >>"$T/ps"
  echo "300 ${STAGE_LEFTOVERS_NOW%.*} 100 $T/run.log" >>"$LONG_RUN_REGISTRY"
  run "$SL" diff "$T/snap"
  [ "$status" -eq 1 ] || { echo "a job registered in the same whole second was missed: $output"; return 1; }
}

@test "a long-run job that finished, or started before the snapshot, is not shown" {
  before; snap
  { row 300 1 15:00:00 'bash -c done'; row 301 1 08:00:00 'bash -c old'; } >>"$T/ps"
  touch "$T/done.log.exit"
  { echo "300 $STAGE_LEFTOVERS_NOW 100 $T/done.log"; echo "301 1 100 $T/old.log"; } >>"$LONG_RUN_REGISTRY"
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

# A build can rewrite a tracked file on every run, a lockfile under local dependencies: restoring it
# only starts the same question again after the next stage, so a file that comes back the same is marked.
@test "a file restored and rewritten with the same content comes back marked again" {
  before; repo; snap --root "$T/repo"
  printf 'rewritten\n' >fixture.sqlite
  run "$SL" restore "$T/snap" "$T/repo" fixture.sqlite
  [ "$status" -eq 0 ] && [ "$(cat fixture.sqlite)" = b ] || { echo "$output"; return 1; }
  snap --root "$T/repo"; printf 'rewritten\n' >fixture.sqlite
  run "$SL" diff "$T/snap"
  [ "$status" -eq 1 ] || { echo "$output"; return 1; }
  [ "$output" = "tree root=$T/repo path=fixture.sqlite change=modified again=1" ] || { echo "$output"; return 1; }
}

@test "a restored file rewritten with other content is an ordinary line" {
  before; repo; snap --root "$T/repo"
  printf 'rewritten\n' >fixture.sqlite
  "$SL" restore "$T/snap" "$T/repo" fixture.sqlite
  snap --root "$T/repo"; printf 'other\n' >fixture.sqlite
  run "$SL" diff "$T/snap"
  [ "$output" = "tree root=$T/repo path=fixture.sqlite change=modified" ] || { echo "$output"; return 1; }
}

@test "restore of a path git does not know leaves the memo alone and passes git's exit" {
  before; repo; snap --root "$T/repo"
  run "$SL" restore "$T/snap" "$T/repo" nosuch
  [ "$status" -ne 0 ] && [ "$status" -ne 2 ] || { echo "$status $output"; return 1; }
  [ ! -e "$T/snap.memo" ] || { cat "$T/snap.memo"; return 1; }
}

@test "a broken memo reads as no memo, and restore writes it anew" {
  before; repo; snap --root "$T/repo"
  printf 'not json' >"$T/snap.memo"
  printf 'rewritten\n' >fixture.sqlite
  run "$SL" diff "$T/snap"
  [ "$output" = "tree root=$T/repo path=fixture.sqlite change=modified" ] || { echo "$output"; return 1; }
  run "$SL" restore "$T/snap" "$T/repo" fixture.sqlite
  [ "$status" -eq 0 ] || { echo "$output"; return 1; }
  python3 -c 'import json,sys; json.load(open(sys.argv[1]))' "$T/snap.memo"
}

@test "restore refuses a quoted path and a nested repository" {
  before; repo; snap --root "$T/repo"
  run "$SL" restore "$T/snap" "$T/repo" '"a\nb"'
  [ "$status" -eq 2 ] && [[ "$output" == *'"a\nb"'* ]] || { echo "$output"; return 1; }
  run "$SL" restore "$T/snap" "$T/repo" clone/
  [ "$status" -eq 2 ] && [[ "$output" == *clone/* ]] || { echo "$output"; return 1; }
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

# Final review of the first cut: each test below reproduces one finding.

@test "a build left under a Bash-tool shell the stage started is shown" {
  before; snap
  { row 140 100 14:00:00 '/bin/zsh -c source snapshot && eval xcodebuild'
    row 141 140 14:00:01 'xcodebuild test'; } >>"$T/ps"
  run "$SL" diff "$T/snap"
  [ "$status" -eq 1 ] && [[ "$output" == "process pid=141 "*"cmd=xcodebuild test" ]] || { echo "$output"; return 1; }
}

@test "an MCP server relaunched through npm exec is not offered as a leftover" {
  before; snap
  { row 150 100 14:00:00 'npm exec claude-in-mobile@latest'; row 151 150 14:00:01 'node claude-in-mobile'; } >>"$T/ps"
  run "$SL" diff "$T/snap"
  [ "$status" -eq 0 ] || { echo "$output"; return 1; }
}

@test "the watch and whatever shares the caller's shell are not leftovers" {
  before; snap
  { row 160 100 14:00:00 '/bin/zsh -c eval stage-leftovers.sh watch'
    row 161 160 14:00:00 '/usr/bin/python3 - watch --dir /x --stall 300 --idle 1800'
    row 170 100 14:59:59 '/bin/zsh -c eval stage-leftovers.sh diff | cat'
    row 171 170 14:59:59 '/usr/bin/python3 - diff /s'
    row 172 170 14:59:59 'cat'; } >>"$T/ps"
  STAGE_LEFTOVERS_SELF=171 run "$SL" diff "$T/snap"
  [ "$status" -eq 0 ] || { echo "$output"; return 1; }
}

@test "another session's long-run job, an old-format line and a recycled pid are not shown" {
  before; snap
  { row 300 1 15:00:00 'bash -c other'; row 301 1 15:00:00 'bash -c old'; row 302 1 14:00:00 'bash -c reused'; } >>"$T/ps"
  { echo "300 $STAGE_LEFTOVERS_NOW 200 $T/a.log"; echo "301 $STAGE_LEFTOVERS_NOW $T/b.log"
    echo "302 $STAGE_LEFTOVERS_NOW 100 $T/c.log"; } >>"$LONG_RUN_REGISTRY"
  run "$SL" diff "$T/snap"
  [ "$status" -eq 0 ] || { echo "$output"; return 1; }
}

@test "a root below its repository's top reports paths from the root and nothing outside it" {
  before; git init -q "$T/mono" && cd "$T/mono" && mkdir -p ios/Tasks/ACTIVE/1 web
  printf 'a\n' >ios/a; printf 'w\n' >web/w
  git add . && git -c user.email=t@t -c user.name=t commit -qm init
  snap --root "$T/mono/ios" --exclude "$T/mono/ios/Tasks/*/1"
  printf 'b\n' >ios/a; printf 'x\n' >web/w; printf 'v\n' >ios/Tasks/ACTIVE/1/Validation.md
  run "$SL" diff "$T/snap"
  [ "$output" = "tree root=$T/mono/ios path=a change=modified" ] || { echo "$output"; return 1; }
}

@test "the task folder is excluded after it moves to another status directory" {
  before; repo; mkdir -p Tasks/ACTIVE/042; snap --root "$T/repo" --exclude "$T/repo/Tasks/*/042"
  mkdir -p Tasks/DONE/042; printf 'x\n' >Tasks/DONE/042/Done.md
  run "$SL" diff "$T/snap"
  [ "$status" -eq 0 ] || { echo "$output"; return 1; }
}

# Milestone 7: every Kotlin build left .kotlin/sessions/*.salive, in a project whose .gitignore
# predates Kotlin 2, and the check asked about it after every stage.
@test "a platform's build traces are left out at the root and at any depth below it" {
  before; repo
  snap --root "$T/repo" --exclude "$T/repo/.kotlin" --exclude "$T/repo/*/.kotlin"
  mkdir -p .kotlin/sessions app/.kotlin/sessions lib/core/.kotlin/errors
  : >.kotlin/sessions/a.salive; : >app/.kotlin/sessions/b.salive; : >lib/core/.kotlin/errors/c.log
  run "$SL" diff "$T/snap"
  [ "$status" -eq 0 ] || { echo "$output"; return 1; }
  : >notkotlin.txt
  run "$SL" diff "$T/snap"
  [ "$status" -eq 1 ] && [[ "$output" == *notkotlin.txt* ]] || { echo "$output"; return 1; }
}

@test "the orchestrator passes the platform's build traces to snap, and the contract defines them" {
  grep -qF "\`dirs\` row of the platform manifest's \`## Build traces\`" "$ROOT/skills/orchestrator/SKILL.md"
  grep -qF -- "--exclude '<root>/*/<dir>'" "$ROOT/skills/orchestrator/SKILL.md"
  grep -qx '## `## Build traces`' "$ROOT/conventions/platform-contract.md"
}

@test "ps is read the same under a non-English LC_TIME" {
  loc="$(locale -a 2>/dev/null | grep -m1 -i '^ru_RU' || true)"
  [ -n "$loc" ] || skip "no ru_RU locale on this machine"
  unset STAGE_LEFTOVERS_PS
  LC_ALL="$loc" STAGE_LEFTOVERS_SESSION_PID=1 run "$SL" snap --out "$T/live"
  [ "$status" -eq 0 ] || { echo "$output"; return 1; }
  n="$(python3 -c 'import json,sys; print(len(json.load(open(sys.argv[1]))["procs"]))' "$T/live")"
  [ "$n" -gt 0 ] || { echo "no process read under $loc"; return 1; }
}

@test "waiting on a hung call fires again only after another --stall" {
  before
  export STAGE_LEFTOVERS_POLL=0
  transcript a1 mcp__x__y 900 pending
  touch -t 200001010000 "$T/wf/agent-a1.jsonl" "$T/wf"
  run "$SL" watch --dir "$T/wf" --stall 300 --idle 1 --since $((STAGE_LEFTOVERS_NOW - 60))
  [ "$status" -eq 5 ] || { echo "fired again at once: $output"; return 1; }
  run "$SL" watch --dir "$T/wf" --stall 300 --idle 99999 --since $((STAGE_LEFTOVERS_NOW - 400))
  [ "$status" -eq 4 ] || { echo "$output"; return 1; }
}

@test "a copy of the API request in the transcript neither stops the watch nor reopens a call" {
  before
  export STAGE_LEFTOVERS_POLL=0
  transcript a1 mcp__x__y 900 pending
  blob='{"type":"api-request-blob","sessionId":"s","agentId":"a1","hash":"h","message":{"content":[{"type":"tool_use","id":"t1","name":"mcp__x__y"}]}}'
  t="$(sed -n 's/.*"timestamp":"\([^"]*\)".*/\1/p' "$T/wf/agent-a1.jsonl")"
  { echo "$blob"
    printf '{"type":"user","timestamp":"%s","message":{"content":[{"type":"tool_result","tool_use_id":"t1"}]}}\n' "$t"
    echo "$blob"; } >>"$T/wf/agent-a1.jsonl"
  touch -t 200001010000 "$T/wf/agent-a1.jsonl" "$T/wf"
  run "$SL" watch --dir "$T/wf" --stall 300 --idle 1
  [ "$status" -eq 5 ] || { echo "$output"; return 1; }
}

# A watch outlived the Claude Code session that started it: the session closed mid-stage, the
# watch went to PID 1 and stayed until --idle, and the next session's diff called it a leftover.
@test "the watch exits 6 once the session that started it is gone" {
  { row 200 1 09:00:00 claude; } >"$T/ps"
  export STAGE_LEFTOVERS_POLL=0
  transcript a1 mcp__x__y 60 pending
  touch -t 200001010000 "$T/wf/agent-a1.jsonl" "$T/wf"
  run "$SL" watch --dir "$T/wf" --stall 300 --idle 1
  [ "$status" -eq 6 ] && [ "$output" = "session gone pid=100" ] || { echo "$output"; return 1; }
}

# A stage's load generator, `( busy loop ) &` in a Bash-tool command, went to PID 1 when the shell
# exited, and diff said nothing while 84 such processes held the machine for half an hour.
# The snapshot is taken at 14:00, the diff runs at 15:00; the caller's shell is 170.
orphans() {
  before
  STAGE_LEFTOVERS_NOW=$((STAGE_LEFTOVERS_NOW - 3600)) snap
  { row 170 100 14:59:59 '/bin/zsh -c source /u/.claude/shell-snapshots/snapshot-zsh-1-mine.sh && eval diff'
    row 171 170 14:59:59 '/usr/bin/python3 - diff /s'; } >>"$T/ps"
}

@test "a process the stage orphaned to PID 1 is shown, once, at the top of what it started" {
  orphans
  { orow 141 140 14:30:00 'sleep 301'
    orow 142 140 14:30:00 '/bin/zsh -c source /u/.claude/shell-snapshots/snapshot-zsh-1-mine.sh && eval loop'
    PG=140 row 143 142 14:30:01 'perl -e busy'; } >>"$T/ps"
  echo "141 $((STAGE_LEFTOVERS_NOW - 1800)) 100 $T/a.log" >>"$LONG_RUN_REGISTRY"
  STAGE_LEFTOVERS_SELF=171 run "$SL" diff "$T/snap"
  [ "$status" -eq 1 ] || { echo "$output"; return 1; }
  [ "${#lines[@]}" -eq 2 ] || { echo "$output"; return 1; }
  [[ "${lines[0]}" == "process pid=141 "*"parent=1 cmd=sleep 301" ]] || { echo "$output"; return 1; }
  [[ "${lines[1]}" == "process pid=142 "*"eval loop" ]] || { echo "$output"; return 1; }
}

@test "another session's orphan, an old one, a group leader and another user's process are not shown" {
  orphans
  { orow 151 150 14:30:00 'sleep 1'
    orow 152 150 14:30:00 '/bin/zsh -c source /u/.claude/shell-snapshots/snapshot-zsh-2-other.sh && eval x'
    orow 161 160 13:00:00 'sleep 2'
    row 175 1 14:30:00 'launched by launchd'
    row 180 100 14:30:00 '/bin/zsh -c eval y'; orow 181 180 14:30:00 'sleep 3'
    U=0 orow 191 190 14:30:00 'sleep 4'; } >>"$T/ps"
  STAGE_LEFTOVERS_SELF=171 run "$SL" diff "$T/snap"
  [[ "$output" != *"pid=15"* && "$output" != *"pid=16"* && "$output" != *"pid=17"* \
     && "$output" != *"pid=181"* && "$output" != *"pid=19"* ]] || { echo "$output"; return 1; }
}

@test "a watch orphaned to PID 1 is not a leftover; the stage's own orphan beside it is" {
  orphans
  { orow 165 160 14:30:00 '/usr/bin/python3 - watch --dir /x --stall 300 --idle 1800'
    orow 141 140 14:30:00 'sleep 301'; } >>"$T/ps"
  STAGE_LEFTOVERS_SELF=171 run "$SL" diff "$T/snap"
  [ "$status" -eq 1 ] && [ "${#lines[@]}" -eq 1 ] && [[ "${lines[0]}" == "process pid=141 "* ]] \
    || { echo "$output"; return 1; }
}

# An app on the same machine restarted during a stage: its crashpad handler, double-forked, sat
# under PID 1 with its group's leader gone, and the orchestrator offered to kill it.
@test "an orphan another app is responsible for is not shown; the stage's own beside it is" {
  orphans
  { orow 141 140 14:30:00 'sleep 301'
    orow 145 144 14:30:00 '/Applications/Other.app/Contents/Frameworks/Helpers/chrome_crashpad_handler'; } >>"$T/ps"
  printf '100 1603\n141 1603\n145 7831\n' >"$T/origin"
  STAGE_LEFTOVERS_ORIGIN="$T/origin" STAGE_LEFTOVERS_SELF=171 run "$SL" diff "$T/snap"
  [ "$status" -eq 1 ] && [ "${#lines[@]}" -eq 1 ] && [[ "${lines[0]}" == "process pid=141 "* ]] \
    || { echo "$output"; return 1; }
}

@test "an orphan whose origin cannot be read is shown, and so is every orphan when the session's cannot" {
  orphans
  { orow 141 140 14:30:00 'sleep 301'
    orow 145 144 14:30:00 'helper'; } >>"$T/ps"
  printf '100 1603\n145 7831\n' >"$T/origin"
  STAGE_LEFTOVERS_ORIGIN="$T/origin" STAGE_LEFTOVERS_SELF=171 run "$SL" diff "$T/snap"
  [ "$status" -eq 1 ] && [ "${#lines[@]}" -eq 1 ] && [[ "${lines[0]}" == "process pid=141 "* ]] \
    || { echo "$output"; return 1; }
  printf '141 1603\n145 7831\n' >"$T/origin"
  STAGE_LEFTOVERS_ORIGIN="$T/origin" STAGE_LEFTOVERS_SELF=171 run "$SL" diff "$T/snap"
  [ "$status" -eq 1 ] && [ "${#lines[@]}" -eq 2 ] || { echo "$output"; return 1; }
}

@test "on macOS a process this shell sent to the background has the session's origin" {
  [ "$(uname)" = Darwin ] || skip "the responsible process is a macOS notion"
  ( exec sleep 30 & echo $! >"$T/pid" )
  run "$SL" origin "$(cat "$T/pid")" "$$"
  kill "$(cat "$T/pid")" 2>/dev/null
  [ "$status" -eq 0 ] && [ "${lines[0]}" = "${lines[1]}" ] && [ -n "${lines[0]}" ] \
    || { echo "$output"; return 1; }
}

# --- The session above the script: Claude Code or Codex CLI (runtimes/codex-cli.md → Scripts) ---

@test "the session is found above the script under codex" {
  unset STAGE_LEFTOVERS_SESSION_PID
  { row 300 1 09:00:00 'codex'; row 400 300 09:00:01 '/bin/zsh -lc x'; row 500 400 09:00:02 bash; } >"$T/ps"
  STAGE_LEFTOVERS_SELF=500 run "$SL" snap --out "$T/snap"
  [ "$status" -eq 0 ] || { echo "$output"; false; }
}

@test "the session is still found under claude" {
  unset STAGE_LEFTOVERS_SESSION_PID
  { row 300 1 09:00:00 'claude'; row 400 300 09:00:01 '/bin/zsh -c x'; row 500 400 09:00:02 bash; } >"$T/ps"
  STAGE_LEFTOVERS_SELF=500 run "$SL" snap --out "$T/snap"
  [ "$status" -eq 0 ] || { echo "$output"; false; }
}

@test "a process merely named like codex is not the session" {
  unset STAGE_LEFTOVERS_SESSION_PID
  { row 400 1 09:00:01 'codex-helper'; row 500 400 09:00:02 bash; } >"$T/ps"
  STAGE_LEFTOVERS_SELF=500 run "$SL" snap --out "$T/snap"
  [ "$status" -eq 2 ]
  grep -qF 'no claude or codex process above this one' <<<"$output"
}

@test "a sandbox that refuses ps is named, not mistaken for a missing session" {
  unset STAGE_LEFTOVERS_SESSION_PID STAGE_LEFTOVERS_PS
  mkdir -p "$T/bin"
  printf '#!/bin/sh\necho "ps: Operation not permitted" >&2\nexit 1\n' >"$T/bin/ps"; chmod +x "$T/bin/ps"
  PATH="$T/bin:$PATH" run "$SL" snap --out "$T/snap"
  [ "$status" -eq 2 ]
  grep -qF 'ps is not permitted here' <<<"$output"
}

@test "a build left under a codex shell is shown: Codex runs commands as zsh -lc" {
  row 300 1 09:00:00 codex >"$T/ps"
  STAGE_LEFTOVERS_SESSION_PID=300 snap
  { row 310 300 14:00:00 '/bin/zsh -lc ./build.sh'
    row 311 310 14:00:01 'xcodebuild test -scheme App'; } >>"$T/ps"
  STAGE_LEFTOVERS_SESSION_PID=300 run "$SL" diff "$T/snap"
  [ "$status" -eq 1 ] || { echo "$output"; return 1; }
  [[ "$output" == "process pid=311 "* ]] || { echo "$output"; return 1; }
}

# A stage left 25 xcodebuild logs and long-run sidecars in its step folder; the task folder is
# excluded from the tree check, so diff said nothing and the task's commit would have taken them.
task() { repo; mkdir -p Tasks/ACTIVE/042; : >Tasks/ACTIVE/042/Task.md; }
tsnap() { snap --root "$T/repo" --exclude "$T/repo/Tasks/*/042" --task-dir "$T/repo/Tasks/*/042"; }

@test "a long-run sidecar the stage left in the task folder is shown as added" {
  before; task; tsnap
  : >Tasks/ACTIVE/042/x.log.pid
  run "$SL" diff "$T/snap"
  [ "$status" -eq 1 ] || { echo "$output"; return 1; }
  [ "$output" = "tree root=$T/repo/Tasks/ACTIVE/042 path=x.log.pid change=added" ] || { echo "$output"; return 1; }
}

@test "the task's documents, a step's documents and evidence logs are not leftovers" {
  before; task; tsnap
  cd Tasks/ACTIVE/042
  mkdir -p 1.step validation-evidence/t phase-evidence/phase-1 experiment _archive/old
  : >Done.md; : >Run.json; : >1.step/Plan.md; : >validation-evidence/t/a.log
  : >phase-evidence/phase-1/m.log; : >experiment/s.png; : >_archive/old/x.bin
  run "$SL" diff "$T/snap"
  [ "$status" -eq 0 ] || { echo "$output"; return 1; }
}

@test "a sidecar inside an evidence folder and a log at the step's top are shown" {
  before; task; tsnap
  mkdir -p Tasks/ACTIVE/042/validation-evidence/t Tasks/ACTIVE/042/1.step
  : >Tasks/ACTIVE/042/validation-evidence/t/a.log.exit; : >Tasks/ACTIVE/042/1.step/run.log
  run "$SL" diff "$T/snap"
  [ "$output" = "tree root=$T/repo/Tasks/ACTIVE/042 path=1.step/run.log change=added
tree root=$T/repo/Tasks/ACTIVE/042 path=validation-evidence/t/a.log.exit change=added" ] || { echo "$output"; return 1; }
}

@test "a foreign file that was there before the snapshot is not shown" {
  before; task; : >Tasks/ACTIVE/042/mock.png; tsnap
  run "$SL" diff "$T/snap"
  [ "$status" -eq 0 ] || { echo "$output"; return 1; }
}

@test "a foreign file is found under the status directory the folder moved to" {
  before; task; tsnap
  mv Tasks/ACTIVE Tasks/DONE; : >Tasks/DONE/042/x.log
  run "$SL" diff "$T/snap"
  [ "$output" = "tree root=$T/repo/Tasks/DONE/042 path=x.log change=added" ] || { echo "$output"; return 1; }
}

@test "a task folder that is gone at diff time adds no lines" {
  before; task; tsnap
  rm -rf Tasks/ACTIVE/042
  run "$SL" diff "$T/snap"
  [ "$status" -eq 0 ] && [ -z "$output" ] || { echo "$output"; return 1; }
}

@test "foreign lists untracked foreign files and leaves tracked and ignored ones alone" {
  task; cd Tasks/ACTIVE/042
  : >mock.png; printf 'ignored.bin\n' >.gitignore
  git add . && git -c user.email=t@t -c user.name=t commit -qm docs
  : >ignored.bin; : >x.log; : >'my notes.txt'; : >Plan.md
  run "$SL" foreign "$T/repo/Tasks/ACTIVE/042"
  [ "$status" -eq 1 ] || { echo "$output"; return 1; }
  [ "$output" = "foreign path=my notes.txt
foreign path=x.log" ] || { echo "$output"; return 1; }
}

@test "foreign walks a task folder outside git" {
  mkdir -p "$T/plain"; : >"$T/plain/Task.md"; : >"$T/plain/Done.md"
  run "$SL" foreign "$T/plain"
  [ "$status" -eq 0 ] && [ -z "$output" ] || { echo "$output"; return 1; }
  : >"$T/plain/x.log"
  run "$SL" foreign "$T/plain"
  [ "$status" -eq 1 ] && [ "$output" = "foreign path=x.log" ] || { echo "$output"; return 1; }
}

@test "foreign without a directory is a usage error" {
  run "$SL" foreign
  [ "$status" -eq 2 ] || { echo "$output"; return 1; }
  run "$SL" foreign "$T/nonexistent"
  [ "$status" -eq 2 ] || { echo "$output"; return 1; }
}

# A project whose .gitignore lists Tasks/ keeps its tasks out of git, and the stage's logs with them;
# ls-files sees nothing there, and the logs still clutter the folder the documents cite them from.
@test "a task folder its project ignores is walked, after a stage and by foreign" {
  before; task; printf 'Tasks/\n' >.gitignore
  git add .gitignore && git -c user.email=t@t -c user.name=t commit -qm ignore
  tsnap
  : >Tasks/ACTIVE/042/x.log; : >Tasks/ACTIVE/042/Plan.md; : >Tasks/ACTIVE/042/.DS_Store
  run "$SL" diff "$T/snap"
  [ "$output" = "tree root=$T/repo/Tasks/ACTIVE/042 path=x.log change=added" ] || { echo "$output"; return 1; }
  run "$SL" foreign "$T/repo/Tasks/ACTIVE/042"
  [ "$status" -eq 1 ] && [ "$output" = "foreign path=x.log" ] || { echo "$output"; return 1; }
}

# A path is matched literally except where a component is `*`: a folder named with [x] in it is
# not a character class that silently matches nothing.
@test "a task folder whose name holds glob characters is still excluded and still checked" {
  before; repo; mkdir -p 'Tasks/ACTIVE/044 [x]'; : >'Tasks/ACTIVE/044 [x]/Task.md'
  git add . && git -c user.email=t@t -c user.name=t commit -qm task
  snap --root "$T/repo" --exclude "$T/repo/Tasks/*/044 [x]" --task-dir "$T/repo/Tasks/*/044 [x]"
  : >'Tasks/ACTIVE/044 [x]/Done.md'
  run "$SL" diff "$T/snap"
  [ "$status" -eq 0 ] || { echo "$output"; return 1; }
  : >'Tasks/ACTIVE/044 [x]/z.log'
  run "$SL" diff "$T/snap"
  [ "$output" = "tree root=$T/repo/Tasks/ACTIVE/044 [x] path=z.log change=added" ] || { echo "$output"; return 1; }
}

# One finding is one line: a name that holds a newline is quoted the way git quotes it.
@test "a file name with a newline is quoted on one line" {
  task; : >Tasks/ACTIVE/042/$'a\nb.log'
  run "$SL" foreign "$T/repo/Tasks/ACTIVE/042"
  [ "$status" -eq 1 ] && [ "$output" = 'foreign path="a\nb.log"' ] || { echo "$output"; return 1; }
}

# A failed move can leave the folder under two status directories: both are checked.
@test "every folder the glob matches is checked" {
  before; task; mkdir -p Tasks/DONE/042; : >Tasks/DONE/042/Task.md; : >Tasks/ACTIVE/042/mock.png
  : >Tasks/DONE/042/mock.png; tsnap
  : >Tasks/DONE/042/x.log
  run "$SL" diff "$T/snap"
  [ "$output" = "tree root=$T/repo/Tasks/DONE/042 path=x.log change=added" ] || { echo "$output"; return 1; }
}

# A repository a stage cloned into the task folder is one finding, a folder, in git and outside it:
# the orchestrator shows it and never removes it, for it may hold work pushed nowhere.
@test "a nested repository is one folder finding, in git and outside it" {
  task; git init -q Tasks/ACTIVE/042/clone; : >Tasks/ACTIVE/042/clone/a.txt
  run "$SL" foreign "$T/repo/Tasks/ACTIVE/042"
  [ "$status" -eq 1 ] && [ "$output" = "foreign path=clone/" ] || { echo "$output"; return 1; }
  mkdir -p "$T/plain"; : >"$T/plain/Task.md"; git init -q "$T/plain/clone"; : >"$T/plain/clone/a.txt"
  run "$SL" foreign "$T/plain"
  [ "$status" -eq 1 ] && [ "$output" = "foreign path=clone/" ] || { echo "$output"; return 1; }
}
