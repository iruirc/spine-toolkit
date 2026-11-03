#!/usr/bin/env bash
# Runs a command that may outlast one tool call, and tells done, live, hung and over budget apart.
# How an agent uses it: conventions/agent-tooling.md → Long-running commands.
#
# Usage: scripts/long-run.sh start [--log <path>] [--parallel] -- <cmd> [args…]   # prints pid=<n> log=<path>
#        scripts/long-run.sh wait <log> [--for s] [--stall s] [--max s]
#        scripts/long-run.sh stop <log>
# Exit (wait): 0 done ok, 1 done failed, 3 running, 4 stalled, 5 timeout. 2: usage, any subcommand.
# Exit (start): 2 also while a job started from the same folder still runs, unless --parallel.
# Exit (stop): 2 also when the host refuses the signal (a sandbox; the command runs outside it).
set -uo pipefail

POLL="${LONG_RUN_POLL:-10}"
GRACE="${LONG_RUN_GRACE:-10}"

usage() { echo "usage: $0 start [--log <path>] [--parallel] -- <cmd…> | wait <log> [--for s] [--stall s] [--max s] | stop <log>" >&2; exit 2; }
mtime() { stat -c %Y "$1" 2>/dev/null || stat -f %m "$1"; }
lines_of() { wc -l <"$1" | tr -d ' '; }
# A process the host will not let this one signal (a sandbox looking at a command started outside
# it) is alive: only "no such process" means it is gone.
alive() { local err; err="$(LC_ALL=C kill -0 "$1" 2>&1)" || [[ "$err" == *'not permitted'* ]]; }
report() { echo "status=$1"; echo "--- tail $2"; tail -n 40 "$2" | cut -c1-500; }

# When a process started, from its elapsed time ([[dd-]hh:]mm:ss); empty when ps cannot tell.
started_at() {
  local et d=0 h=0 m s
  et="$(LC_ALL=C ps -o etime= -p "$1" 2>/dev/null | tr -d ' ')"
  [[ "$et" =~ ^(([0-9]+)-)?(([0-9]+):)?([0-9]+):([0-9]+)$ ]] || return 0
  d="${BASH_REMATCH[2]:-0}"; h="${BASH_REMATCH[4]:-0}"; m="${BASH_REMATCH[5]}"; s="${BASH_REMATCH[6]}"
  echo $(( $(date +%s) - ((10#$d * 24 + 10#$h) * 60 + 10#$m) * 60 - 10#$s ))
}

# The live job a start from this folder would run beside: two builds sharing derived data corrupt
# each other. A registry line outlives its job and its pid can be reused: a job that left its exit
# file is over whatever its pid says, and so is one whose pid now names a process that started
# elsewhen (a job killed from outside writes no exit file). A --parallel job writes no .cwd.
running_here() {
  local registry="${LONG_RUN_REGISTRY:-${TMPDIR:-/tmp}/spine-long-run.registry}" here pid ts _owner log t
  [ -f "$registry" ] || return 1
  here="$(pwd -P)"
  while read -r pid ts _owner log; do
    [ -n "$log" ] && [ -f "$log.cwd" ] && [ ! -f "$log.exit" ] || continue
    [ "$(cat "$log.cwd")" = "$here" ] && alive "$pid" || continue
    t="$(started_at "$pid")"
    [ -n "$t" ] && [[ "$ts" =~ ^[0-9]+$ ]] && [ $(( t > ts ? t - ts : ts - t )) -le 5 ] || continue
    echo "pid=$pid log=$log"; return 0
  done <"$registry"
  return 1
}

cmd_start() {
  local log='' parallel='' first
  while [ $# -gt 0 ]; do
    case "$1" in
      --log) [ $# -ge 2 ] || usage; log="$2"; shift 2 ;;
      --parallel) parallel=1; shift ;;
      --) shift; break ;;
      *) usage ;;
    esac
  done
  [ $# -gt 0 ] || usage
  if [ -z "$parallel" ] && first="$(running_here)"; then
    echo "long-run: a job is still running in this folder: $first; wait for it; a job that builds nothing starts with --parallel" >&2
    exit 2
  fi
  [ -n "$log" ] || log="$(mktemp "${TMPDIR:-/tmp}/long-run.XXXXXX")"
  : >"$log" || exit 2
  rm -f "$log.exit" "$log.exit.tmp"
  rm -f "$log.cwd"
  date +%s >"$log.start"
  [ -n "$parallel" ] || pwd -P >"$log.cwd"
  # set -m gives the job a process group of its own: stop signals the group, children included.
  ( set -m
    LONG_RUN_LOG="$log" bash -c 'trap "" HUP; "$@"; echo $? >"$LONG_RUN_LOG.exit.tmp" && mv "$LONG_RUN_LOG.exit.tmp" "$LONG_RUN_LOG.exit"' long-run "$@" \
      </dev/null >>"$log" 2>&1 &
    echo $! >"$log.pid" )
  # The job leaves the caller's process tree; stage-leftovers.sh finds it through this registry.
  local owner=$PPID
  while [ "${owner:-0}" -gt 1 ] && ! [[ "$(basename "$(ps -o comm= -p "$owner" 2>/dev/null)")" =~ ^(claude|codex)$ ]]; do
    owner="$(ps -o ppid= -p "$owner" 2>/dev/null | tr -d ' ')"
  done
  echo "$(cat "$log.pid") $(date +%s) ${owner:-0} $log" >>"${LONG_RUN_REGISTRY:-${TMPDIR:-/tmp}/spine-long-run.registry}"
  echo "pid=$(cat "$log.pid") log=$log"
}

cmd_wait() {
  [ $# -ge 1 ] || usage
  local log="$1" for_s=540 stall_s=300 max_s=1800
  shift
  while [ $# -gt 0 ]; do
    [ $# -ge 2 ] && [[ "$2" =~ ^[1-9][0-9]*$ ]] || usage
    case "$1" in
      --for) for_s="$2" ;;
      --stall) stall_s="$2" ;;
      --max) max_s="$2" ;;
      *) usage ;;
    esac
    shift 2
  done
  [ -f "$log" ] && [ -f "$log.pid" ] && [ -f "$log.start" ] || { echo "not a long-run log: $log" >&2; exit 2; }
  local pid start first deadline now code
  pid="$(cat "$log.pid")"; start="$(cat "$log.start")"
  first="$(lines_of "$log")"
  deadline=$(( $(date +%s) + for_s ))
  while :; do
    now="$(date +%s)"
    if [ -f "$log.exit" ]; then
      code="$(cat "$log.exit")"
      report "done exit=$code" "$log"
      [ "$code" = 0 ] && exit 0 || exit 1
    fi
    if ! alive "$pid"; then
      [ -f "$log.exit" ] && continue
      report "done exit=lost" "$log"; exit 1
    fi
    if [ $(( now - start )) -ge "$max_s" ]; then report timeout "$log"; exit 5; fi
    if [ $(( now - $(mtime "$log") )) -ge "$stall_s" ]; then report stalled "$log"; exit 4; fi
    if [ "$now" -ge "$deadline" ]; then
      report "running +$(( $(lines_of "$log") - first )) lines" "$log"; exit 3
    fi
    sleep "$POLL"
  done
}

cmd_stop() {
  [ $# -eq 1 ] && [ -f "$1.pid" ] || usage
  local log="$1" pid i=0
  pid="$(cat "$log.pid")"
  # `kill -- -1` signals every process of the user: a pid file never names a group that wide.
  [[ "$pid" =~ ^[0-9]+$ ]] && [ "$pid" -gt 1 ] || usage
  # A finished command's pgid may already be reused by an unrelated process; signal it only
  # while the command is still the one that holds it.
  if [ -f "$log.exit" ]; then
    echo "stopped pid=$pid"
    return
  fi
  local err
  if ! err="$(LC_ALL=C kill -TERM -- "-$pid" 2>&1)" && [[ "$err" == *'not permitted'* ]]; then
    echo 'stop is not permitted here: rerun outside the sandbox'
    exit 2
  fi
  while kill -0 -- "-$pid" 2>/dev/null && [ "$i" -lt "$GRACE" ]; do sleep 1; i=$((i + 1)); done
  kill -KILL -- "-$pid" 2>/dev/null
  [ -f "$log.exit" ] || echo stopped >"$log.exit"
  echo "stopped pid=$pid"
}

[ $# -ge 1 ] || usage
sub="$1"; shift
case "$sub" in
  start) cmd_start "$@" ;;
  wait) cmd_wait "$@" ;;
  stop) cmd_stop "$@" ;;
  *) usage ;;
esac
