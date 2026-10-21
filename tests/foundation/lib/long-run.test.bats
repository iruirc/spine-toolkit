#!/usr/bin/env bats
# A stage agent waited out a test run in the foreground until the tool limit killed the wait.
# long-run.sh is what lets it wait in slices and tell done, live, hung and over budget apart.

setup() {
  ROOT="$(cd -- "$(dirname -- "$BATS_TEST_FILENAME")/../../.." && pwd)"
  LR="$ROOT/scripts/long-run.sh"
  LOG="$BATS_TEST_TMPDIR/run.log"
  export LONG_RUN_POLL=1 LONG_RUN_GRACE=2 LONG_RUN_REGISTRY="$BATS_TEST_TMPDIR/registry"
}

teardown() {
  # A log written by hand points at a process this test does not own (pid 1 among them, and
  # `kill -- -1` signals every process of the user): never signal it.
  [ -f "$LOG.foreign" ] && return 0
  [ -f "$LOG.pid" ] && kill -KILL -- "-$(cat "$LOG.pid")" 2>/dev/null || true
}

# A long-run log for a process this test did not start, as a sandboxed host sees one started
# outside the sandbox: the signal is refused, not missing.
foreign_log() {
  : >"$LOG"; echo "$1" >"$LOG.pid"; date +%s >"$LOG.start"; : >"$LOG.foreign"
}

# A process group of another user, whose leader is not pid 1, or nothing.
foreign_group() {
  ps -A -o pid=,pgid=,user= | awk '$3=="root" && $1==$2 && $1>1 {print $1; exit}'
}

@test "a command that succeeds is done with exit 0" {
  run "$LR" start --log "$LOG" -- sh -c 'echo hello'
  [ "$status" -eq 0 ] && [[ "$output" == "pid="*" log=$LOG" ]] || { echo "$output"; return 1; }
  run "$LR" wait "$LOG" --for 10
  [ "$status" -eq 0 ] || { echo "$output"; return 1; }
  [ "${lines[0]}" = "status=done exit=0" ] || { echo "$output"; return 1; }
  [[ "$output" == *hello* ]] || { echo "the tail is missing: $output"; return 1; }
}

@test "a command that fails is done with its own exit code" {
  "$LR" start --log "$LOG" -- sh -c 'echo boom; exit 7' >/dev/null
  run "$LR" wait "$LOG" --for 10
  [ "$status" -eq 1 ] && [ "${lines[0]}" = "status=done exit=7" ] || { echo "$output"; return 1; }
}

@test "a live command that keeps printing is running when the slice ends" {
  "$LR" start --log "$LOG" -- sh -c 'while :; do echo tick; sleep 1; done' >/dev/null
  run "$LR" wait "$LOG" --for 3 --stall 60
  [ "$status" -eq 3 ] || { echo "$output"; return 1; }
  [[ "${lines[0]}" == "status=running +"*" lines" ]] || { echo "$output"; return 1; }
  "$LR" stop "$LOG" >/dev/null
}

@test "a quiet command stalls only after --stall" {
  start=$(date +%s)
  "$LR" start --log "$LOG" -- sleep 30 >/dev/null
  run "$LR" wait "$LOG" --for 20 --stall 3
  [ "$status" -eq 4 ] && [ "${lines[0]}" = "status=stalled" ] || { echo "$output"; return 1; }
  [ $(( $(date +%s) - start )) -ge 3 ] || { echo "stalled before --stall elapsed"; return 1; }
  kill -0 "$(cat "$LOG.pid")" || { echo "wait killed a stalled command; only stop may"; return 1; }
  "$LR" stop "$LOG" >/dev/null
}

@test "a command past --max is timeout even while it prints" {
  "$LR" start --log "$LOG" -- sh -c 'while :; do echo tick; sleep 1; done' >/dev/null
  run "$LR" wait "$LOG" --for 20 --stall 60 --max 2
  [ "$status" -eq 5 ] && [ "${lines[0]}" = "status=timeout" ] || { echo "$output"; return 1; }
  "$LR" stop "$LOG" >/dev/null
}

@test "stop leaves nothing of the group alive" {
  "$LR" start --log "$LOG" -- sh -c 'sleep 30 & sleep 30' >/dev/null
  pid="$(cat "$LOG.pid")"
  run "$LR" stop "$LOG"
  [ "$status" -eq 0 ] && [ "$output" = "stopped pid=$pid" ] || { echo "$output"; return 1; }
  if kill -0 -- "-$pid" 2>/dev/null; then echo "a process of group $pid survived"; return 1; fi
  run "$LR" wait "$LOG" --for 5
  [ "$status" -eq 1 ] && [[ "${lines[0]}" == "status=done exit="* ]] || { echo "$output"; return 1; }
}

@test "the rule tells an agent what to do with every status" {
  s="$(awk '$0=="## Long-running commands"{f=1;next} f&&/^## /{exit} f' "$ROOT/conventions/agent-tooling.md")"
  [ -n "$s" ] || { echo "no ## Long-running commands"; return 1; }
  for f in 'scripts/long-run.sh start' 'never in the foreground' 'Do not silence its output' \
           'other than `running`' 'then `stop`' 'not as failed' 'Pass `--stall` and `--max` to `wait`, exactly as your brief gives them' \
           '`stop` exits 2 and says so when the host refuses the signal'; do
    grep -qF -- "$f" <<<"$s" || { echo "the section lost: $f"; return 1; }
  done
}

# Two clones validating the same task number at once wrote to the same /tmp/v<task>… logs.
@test "the rule keeps an agent's logs out of shared fixed paths" {
  s="$(awk '$0=="## Long-running commands"{f=1;next} f&&/^## /{exit} f' "$ROOT/conventions/agent-tooling.md")"
  for f in 'mktemp -d' 'never a fixed path'; do
    grep -qF -- "$f" <<<"$s" || { echo "the section lost: $f"; return 1; }
  done
}

@test "start records the job in the registry stage-leftovers.sh reads" {
  run "$LR" start --log "$LOG" -- sh -c 'echo hi'
  [ "$status" -eq 0 ] || { echo "$output"; return 1; }
  read -r pid when session log <"$LONG_RUN_REGISTRY"
  [ "$pid" = "$(cat "$LOG.pid")" ] && [ "$log" = "$LOG" ] || { echo "registry: $(cat "$LONG_RUN_REGISTRY")"; return 1; }
  [[ "$session" =~ ^[0-9]+$ ]] || { echo "no session pid in the registry line: $session"; return 1; }
  [ $(( $(date +%s) - when )) -lt 60 ] || { echo "registry time is not now: $when"; return 1; }
}

@test "start records a codex session as the owner" {
  # A symlink, not a copy: macOS kills a copied system binary, and ps reports the name invoked.
  ln -s /bin/bash "$BATS_TEST_TMPDIR/codex"
  "$BATS_TEST_TMPDIR/codex" -c '"$1" start --log "$2" -- sh -c "echo hi" >/dev/null; echo $$ >"$2.owner"' _ "$LR" "$LOG"
  read -r pid when session log < <(tail -1 "$LONG_RUN_REGISTRY")
  [ "$session" = "$(cat "$LOG.owner")" ] || { echo "owner $session, codex was $(cat "$LOG.owner")"; false; }
}

# Codex runs a build outside its sandbox and the wait inside it: kill -0 is refused there, and a
# refusal read as "no such process" reported a running build as lost.
@test "wait takes a process it may not signal as alive" {
  [ "$(id -u)" -ne 0 ] || skip "root may signal pid 1"
  foreign_log 1
  run "$LR" wait "$LOG" --for 2 --stall 60
  [ "$status" -eq 3 ] && [[ "${lines[0]}" == "status=running"* ]] || { echo "$output"; return 1; }
  echo 0 >"$LOG.exit"
  run "$LR" wait "$LOG" --for 2
  [ "$status" -eq 0 ] && [ "${lines[0]}" = "status=done exit=0" ] || { echo "$output"; return 1; }
}

@test "wait still reports a vanished process as lost" {
  sh -c 'exit 0' & gone=$!; wait "$gone"
  foreign_log "$gone"
  run "$LR" wait "$LOG" --for 2
  [ "$status" -eq 1 ] && [ "${lines[0]}" = "status=done exit=lost" ] || { echo "$output"; return 1; }
}

@test "stop refuses a pid of 1" {
  # `kill -- -1` signals every process of the user, and a run of this test against a script
  # without the guard once did. The script runs with kill shadowed: an exported function
  # outranks the builtin in the child bash, so a regressed guard is recorded, never sent.
  foreign_log 1
  kill() { echo "kill $*" >>"$BATS_TEST_TMPDIR/kills"; }
  export -f kill
  run "$LR" stop "$LOG"
  unset -f kill
  [ "$status" -eq 2 ] || { echo "$output"; return 1; }
  [ ! -s "$BATS_TEST_TMPDIR/kills" ] || { echo "stop reached kill: $(cat "$BATS_TEST_TMPDIR/kills")"; return 1; }
  [ ! -f "$LOG.exit" ] || { echo "stop wrote an exit file"; return 1; }
}

@test "stop says so when it may not signal the group" {
  [ "$(id -u)" -ne 0 ] || skip "root may signal any group"
  g="$(foreign_group)"; [ -n "$g" ] || skip "no process group of another user"
  foreign_log "$g"
  run "$LR" stop "$LOG"
  [ "$status" -eq 2 ] || { echo "$output"; return 1; }
  [ "$output" = "stop is not permitted here: rerun outside the sandbox" ] || { echo "$output"; return 1; }
  [ ! -f "$LOG.exit" ] || { echo "stop wrote an exit file"; return 1; }
}
