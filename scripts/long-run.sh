#!/usr/bin/env bash
# Runs a command that may outlast one tool call, and tells done, live, hung and over budget apart.
# How an agent uses it: conventions/agent-tooling.md → Long-running commands.
#
# Usage: scripts/long-run.sh start [--log <path>] -- <cmd> [args…]   # prints pid=<n> log=<path>
#        scripts/long-run.sh wait <log> [--for s] [--stall s] [--max s]
#        scripts/long-run.sh stop <log>
# Exit (wait): 0 done ok, 1 done failed, 3 running, 4 stalled, 5 timeout. 2: usage, any subcommand.
set -uo pipefail

POLL="${LONG_RUN_POLL:-10}"
GRACE="${LONG_RUN_GRACE:-10}"

usage() { echo "usage: $0 start [--log <path>] -- <cmd…> | wait <log> [--for s] [--stall s] [--max s] | stop <log>" >&2; exit 2; }
mtime() { stat -c %Y "$1" 2>/dev/null || stat -f %m "$1"; }
lines_of() { wc -l <"$1" | tr -d ' '; }
report() { echo "status=$1"; echo "--- tail $2"; tail -n 40 "$2"; }

cmd_start() {
  local log=''
  while [ $# -gt 0 ]; do
    case "$1" in
      --log) [ $# -ge 2 ] || usage; log="$2"; shift 2 ;;
      --) shift; break ;;
      *) usage ;;
    esac
  done
  [ $# -gt 0 ] || usage
  [ -n "$log" ] || log="$(mktemp "${TMPDIR:-/tmp}/long-run.XXXXXX")"
  : >"$log" || exit 2
  rm -f "$log.exit"
  date +%s >"$log.start"
  # set -m gives the job a process group of its own: stop signals the group, children included.
  ( set -m
    LONG_RUN_LOG="$log" bash -c 'trap "" HUP; "$@"; echo $? >"$LONG_RUN_LOG.exit"' long-run "$@" \
      </dev/null >>"$log" 2>&1 &
    echo $! >"$log.pid" )
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
    if ! kill -0 "$pid" 2>/dev/null; then
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
  kill -TERM -- "-$pid" 2>/dev/null
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
