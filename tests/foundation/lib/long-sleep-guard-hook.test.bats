#!/usr/bin/env bats
# hooks/long-sleep-guard refuses a foreground `sleep` longer than the limit. Such a sleep waits its
# whole length even when the job it waits for has already finished, and on Claude Code it holds
# back the job's completion notification until it ends. The hook fires on every Bash call of a
# session: a short sleep, a sleep inside an argument, a background call, and input it cannot read
# must pass in silence.

bats_require_minimum_version 1.5.0

setup() {
  ROOT="$(cd -- "$(dirname -- "$BATS_TEST_FILENAME")/../../.." && pwd)"
  HOOK="$ROOT/hooks/long-sleep-guard"
  unset SPINE_SLEEP_LIMIT
}

# Runs the hook on a PreToolUse input: $1 the tool, $2 its tool_input as JSON.
hook() {
  python3 -c 'import json,sys; print(json.dumps({"session_id":"s-1","hook_event_name":"PreToolUse","tool_name":sys.argv[1],"tool_input":json.loads(sys.argv[2])}))' \
    "$1" "$2" >"$BATS_TEST_TMPDIR/in"
  run --separate-stderr "$HOOK" <"$BATS_TEST_TMPDIR/in"
}
bash_call() { hook Bash "$(python3 -c 'import json,sys; print(json.dumps({"command": sys.argv[1]}))' "$1")"; }

@test "a foreground sleep over the limit is refused, and the reason names the way out" {
  bash_call 'sleep 1200; tail x'
  [ "$status" -eq 2 ] || { echo "status $status: $stderr"; return 1; }
  grep -qF 'long-run.sh wait' <<<"$stderr" || { echo "$stderr"; return 1; }
  grep -qF 'run_in_background' <<<"$stderr" || { echo "$stderr"; return 1; }
  [ -z "$output" ] || { echo "stdout: $output"; return 1; }
}

@test "a sleep in command position after an operator or a shell keyword is refused" {
  for c in 'cd x && sleep 300' 'true || sleep 300' 'a | sleep 300' 'x & sleep 300' \
           'while true; do sleep 90; done' 'if x; then sleep 61; fi' 'if x; then :; else sleep 61; fi' \
           'echo $(sleep 120)' '(sleep 120)' $'make\nsleep 120' '  sleep 120'; do
    bash_call "$c"
    [ "$status" -eq 2 ] || { echo "not refused: $c"; return 1; }
  done
}

@test "units are read, and several arguments add up" {
  for c in 'sleep 2m' 'sleep 1h' 'sleep 1d' 'sleep 61s' 'sleep 60.5' 'sleep 30 31' 'sleep 1m 1'; do
    bash_call "$c"
    [ "$status" -eq 2 ] || { echo "not refused: $c"; return 1; }
  done
}

@test "a sleep at or under the limit passes in silence" {
  for c in 'sleep 60' 'sleep 5' 'sleep 1m' 'sleep 30 30' 'sleep 0.5; ls'; do
    bash_call "$c"
    [ "$status" -eq 0 ] && [ -z "$output" ] && [ -z "$stderr" ] || { echo "$c: $status $stderr"; return 1; }
  done
}

@test "a sleep inside an argument passes" {
  for c in 'git commit -m "a foreground sleep 1200 kept the session waiting"' \
           "echo '{\"command\":\"sleep 1200\"}'" 'grep -rn "sleep 1200" .' 'nosleep 1200' 'my_sleep 1200'; do
    bash_call "$c"
    [ "$status" -eq 0 ] || { echo "refused: $c"; return 1; }
  done
}

@test "a background call passes, whatever it sleeps" {
  hook Bash '{"command": "sleep 1200", "run_in_background": true}'
  [ "$status" -eq 0 ] && [ -z "$stderr" ] || { echo "$status $stderr"; return 1; }
}

@test "long-run.sh wait passes: it returns when the job exits" {
  bash_call 'scripts/long-run.sh wait /tmp/x.log --for 540'
  [ "$status" -eq 0 ] || { echo "$stderr"; return 1; }
}

@test "a tool other than Bash passes" {
  hook Read '{"file_path": "/tmp/x", "command": "sleep 1200"}'
  [ "$status" -eq 0 ] && [ -z "$stderr" ] || { echo "$status $stderr"; return 1; }
}

@test "SPINE_SLEEP_LIMIT raises the limit, and a value it cannot read keeps 60" {
  export SPINE_SLEEP_LIMIT=600
  bash_call 'sleep 300'
  [ "$status" -eq 0 ] || { echo "refused under 600: $stderr"; return 1; }
  bash_call 'sleep 601'
  [ "$status" -eq 2 ] || { echo "not refused over 600"; return 1; }
  grep -qF '600 s' <<<"$stderr" || { echo "$stderr"; return 1; }
  export SPINE_SLEEP_LIMIT=soon
  bash_call 'sleep 61'
  [ "$status" -eq 2 ] || { echo "not refused with a bad limit"; return 1; }
}

@test "input the hook cannot read passes in silence" {
  for input in '' 'not json sleep 1200' '{"tool_name": "Bash"}' \
               '{"tool_name": "Bash", "tool_input": {"command": 7}}' '{"tool_name": "Bash", "tool_input": "sleep 1200"}'; do
    run --separate-stderr "$HOOK" <<<"$input"
    [ "$status" -eq 0 ] && [ -z "$output" ] && [ -z "$stderr" ] || { echo "$input: $status $stderr"; return 1; }
  done
}

@test "every hook command in hooks.json is an executable in hooks/, and Bash goes to long-sleep-guard" {
  run python3 - "$ROOT" <<'PY'
import json, os, sys
root = sys.argv[1]
spec = json.load(open(os.path.join(root, 'hooks', 'hooks.json')))
bash = []
for event, entries in spec['hooks'].items():
    for entry in entries:
        for h in entry['hooks']:
            path = h['command'].strip('"').replace('${CLAUDE_PLUGIN_ROOT}', root)
            if not (os.path.isfile(path) and os.access(path, os.X_OK)):
                sys.exit('%s: %s is not an executable file' % (event, h['command']))
            if h.get('async') is not False:
                sys.exit('%s: %s must run with async false' % (event, h['command']))
            if event == 'PreToolUse' and entry['matcher'] == 'Bash':
                bash.append(os.path.basename(path))
if bash != ['long-sleep-guard']:
    sys.exit('PreToolUse Bash hooks: %r' % bash)
PY
  [ "$status" -eq 0 ] || { echo "$output"; return 1; }
}
