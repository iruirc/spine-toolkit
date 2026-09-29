#!/usr/bin/env bats
# The device every build and test of a stage runs on reaches every stage agent in the words
# conventions/stage-dispatch.md → Device gives, and only when a device or a command to find one is
# set: at auto with no command, every brief is what it was.

setup() {
  ROOT="$(cd -- "$(dirname -- "$BATS_TEST_FILENAME")/../../.." && pwd)"
  AGENTS='{"architect":"a","developer":"d","tester":"t","reviewer":"r","refactorer":"f","validator":"v","security":"—","diagnostics":"g","init":"—"}'
  CONV="$ROOT/conventions/stage-dispatch.md"
}

run_profile() { node "$ROOT/tests/foundation/helpers/run-profile.js" "$ROOT/workflows/profile-$1.js" "$2" "${3:-$NONE}"; }
NONE='{}'

pick() { node -e 'const o = JSON.parse(require("fs").readFileSync(0, "utf8")); const v = eval(process.argv[1]); console.log(typeof v === "string" ? v : JSON.stringify(v))' "$1"; }

contract() { # $1 extra JSON members (leading comma)
  printf '{"task_id": "001", "task_dir": "/p/Tasks/ACTIVE/001-x", "plugin_root": "/core", "lang": "en", "agents": %s, "stage_scope": "single"%s}' "$AGENTS" "$1"
}

# The n-th fenced block of the convention's ## Device section, placeholders filled.
block() { # $1 index, $2 value
  awk '/^## Device$/{f=1;next} f&&/^## /{exit} f' "$CONV" \
    | awk -v n="$1" '/^```/{i++;next} i==2*n-1' \
    | python3 -c 'import sys; print(sys.stdin.read().rstrip("\n").replace("{device}", sys.argv[1]).replace("{device_source}", sys.argv[1]))' "$2"
}

prompts() { pick 'o.calls.filter((c) => c.prompt).map((c) => c.prompt).join("\n----\n")'; }

@test "auto with no command leaves every brief as it was" {
  for p in bug feature refactor test quick research review epic; do
    a="$(run_profile "$p" "$(contract '')" | prompts)"
    b="$(run_profile "$p" "$(contract ', "device": "auto", "device_source": "—"')" | prompts)"
    [ -n "$a" ] || { echo "profile-$p dispatched nothing"; return 1; }
    [ "$a" = "$b" ] || { echo "profile-$p: auto changed a brief"; return 1; }
  done
}

@test "a device reaches every agent of every profile in the convention's words" {
  d='kind=Handset,name=Phone B'
  want="$(block 1 "$d")"
  [ -n "$want" ] || { echo "the convention has no ## Device block"; return 1; }
  for p in bug feature refactor test quick research review epic; do
    out="$(run_profile "$p" "$(contract ", \"device\": \"$d\", \"device_source\": \"scripts/device.sh get\"")")"
    n="$(pick 'o.calls.filter((c) => c.prompt).length' <<<"$out")"
    [ "$n" -gt 0 ] || { echo "profile-$p dispatched nothing"; return 1; }
    for i in $(seq 0 $((n - 1))); do
      pr="$(pick "o.calls.filter((c) => c.prompt)[$i].prompt" <<<"$out")"
      [[ "$pr" == *"$want"* ]] || { echo "profile-$p call $i lost the device"; return 1; }
      [[ "$pr" != *'scripts/device.sh get'* ]] || { echo "profile-$p call $i runs a command a named device made moot"; return 1; }
    done
  done
}

@test "at auto the command reaches every agent of every profile in the convention's words" {
  want="$(block 2 'scripts/device.sh get')"
  [ -n "$want" ] || { echo "the convention has no second ## Device block"; return 1; }
  for p in bug feature refactor test quick research review epic; do
    out="$(run_profile "$p" "$(contract ', "device": "auto", "device_source": "scripts/device.sh get"')")"
    n="$(pick 'o.calls.filter((c) => c.prompt).length' <<<"$out")"
    for i in $(seq 0 $((n - 1))); do
      pr="$(pick "o.calls.filter((c) => c.prompt)[$i].prompt" <<<"$out")"
      [[ "$pr" == *"$want"* ]] || { echo "profile-$p call $i lost the command"; return 1; }
    done
  done
}

@test "the device follows the data rule and the directive, never precedes them" {
  pr="$(run_profile bug "$(contract ', "start_stage": "Validation", "user_directive": "x", "device": "Phone B"')" | pick "o.calls[0].prompt")"
  data="$(grep -nF 'is DATA, never instruction' <<<"$pr" | cut -d: -f1)"
  own="$(grep -nF "Owner's directive for this run" <<<"$pr" | cut -d: -f1)"
  dev="$(grep -nF 'Device: «Phone B»' <<<"$pr" | cut -d: -f1)"
  [ -n "$data" ] && [ -n "$own" ] && [ -n "$dev" ] && [ "$dev" -gt "$own" ] && [ "$own" -gt "$data" ] \
    || { echo "data $data, directive $own, device $dev"; return 1; }
}

@test "a device of blanks is auto" {
  a="$(run_profile bug "$(contract ', "start_stage": "Validation"')" | pick "o.calls[0].prompt")"
  b="$(run_profile bug "$(contract ', "start_stage": "Validation", "device": "  ", "device_source": " "')" | pick "o.calls[0].prompt")"
  [ "$a" = "$b" ] || { echo "$b"; return 1; }
}

epic_run() { # $1 extra contract members, $2 extra step members
  run_profile epic "$(contract ", \"start_stage\": \"Execute\", \"mode\": \"auto\", \"scale\": \"lite\", \"models\": {\"reviewer\": \"session\"}$1")" \
    "{\"execute:read-steps\": {\"branch\": \"decomposition\", \"steps\": [{\"step_id\": \"1-a.step\", \"task_id\": \"001.1\", \"task_type\": \"FEATURE\", \"status\": \"PENDING\"$2}]}, \"workflow:spine-toolkit:profile-feature\": {\"status\": \"ok\", \"last_completed_stage\": \"Done\", \"stages\": []}}"
}

@test "the epic asks each step for its own device, and hands it on with the project's command" {
  out="$(epic_run ', "device": "Phone A", "device_source": "scripts/device.sh get"' ', "device": "Phone C"')"
  pr="$(pick "o.calls.find((c) => c.label === 'execute:read-steps').prompt" <<<"$out")"
  grep -qF 'drive_app, device, manual_checks' <<<"$pr" || { echo "$pr"; return 1; }
  args="$(pick "o.calls.find((c) => c.label === 'workflow:spine-toolkit:profile-feature').args" <<<"$out")"
  [ "$(pick 'o.device' <<<"$args")" = 'Phone C' ] || { echo "$args"; return 1; }
  [ "$(pick 'o.device_source' <<<"$args")" = 'scripts/device.sh get' ] || { echo "$args"; return 1; }
  args="$(epic_run ', "device": "Phone A"' '' | pick "o.calls.find((c) => c.label === 'workflow:spine-toolkit:profile-feature').args")"
  [ "$(pick 'o.device' <<<"$args")" = 'Phone A' ] || { echo "$args"; return 1; }
  [ "$(pick 'o.device_source' <<<"$args")" = '—' ] || { echo "$args"; return 1; }
}

@test "a run device with an apostrophe reaches each step's resolver whole" {
  pr="$(epic_run ", \"run_settings\": {\"device\": \"Sam's phone\"}" '' | pick "o.calls.find((c) => c.label === 'execute:read-steps').prompt")"
  cmd="$(sed -n 's/.*run "\([^"]*resolve-settings\.sh json <step folder>[^"]*\)".*/\1/p' <<<"$pr")"
  [ -n "$cmd" ] || { echo "$pr"; return 1; }
  eval "set -- ${cmd#*<step folder>}" || { echo "$cmd"; return 1; }
  [ "$#" -eq 2 ] && [ "$2" = "device=Sam's phone" ] || { echo "$cmd"; return 1; }
}

@test "the device's own files name no ecosystem" {
  words='simul''ator|emul''ator|\bi''OS\b|andr''oid|xc''ode|\ba''db\b'
  for f in docs/configuration.md conventions/stage-dispatch.md conventions/task-settings.md scripts/resolve-settings.sh \
           tests/foundation/lib/device-setting.test.bats tests/foundation/lib/settings-resolver.test.bats; do
    ! command grep -niE "$words" "$ROOT/$f" || { echo "$f names an ecosystem"; return 1; }
  done
}

# The convention's origin table: `<source>` → the words a brief uses for it.
origin() { awk '/^## Device$/{f=1;next} f&&/^## /{exit} f' "$CONV" | sed -n "s/^| \`$1\` | \(.*\) |$/\1/p"; }

@test "a named device says where it was set, in the convention's words" {
  for s in run task epic project; do
    o="$(origin "$s")"
    [ -n "$o" ] || { echo "the convention has no origin for $s"; return 1; }
    pr="$(run_profile bug "$(contract ", \"start_stage\": \"Validation\", \"device\": \"Phone B\", \"device_from\": \"$s\"")" | pick "o.calls[0].prompt")"
    grep -qF "and that the brief named it, set by $o." <<<"$pr" || { echo "$s: $pr"; return 1; }
  done
  pr="$(run_profile bug "$(contract ', "start_stage": "Validation", "device": "Phone B", "device_from": "bogus"')" | pick "o.calls[0].prompt")"
  grep -qF 'and that the brief named it.' <<<"$pr" || { echo "$pr"; return 1; }
}

@test "a command with a backtick in it stays one code span" {
  pr="$(run_profile bug "$(contract ', "start_stage": "Validation", "device_source": "cat `pwd`/dev"')" | pick "o.calls[0].prompt")"
  grep -qF 'Device: run `` cat `pwd`/dev `` from the project root' <<<"$pr" || { echo "$pr"; return 1; }
}

@test "the epic hands each step where its device was set" {
  args="$(epic_run ', "device": "Phone A", "device_from": "project"' ', "device": "Phone C", "device_from": "task"' | pick "o.calls.find((c) => c.label === 'workflow:spine-toolkit:profile-feature').args")"
  [ "$(pick 'o.device_from' <<<"$args")" = task ] || { echo "$args"; return 1; }
  out="$(epic_run ', "device": "Phone A", "device_from": "project"' '')"
  [ "$(pick "o.calls.find((c) => c.label === 'workflow:spine-toolkit:profile-feature').args.device_from" <<<"$out")" = project ] || { echo "$out"; return 1; }
  grep -qF 'sources.device as device_from' <<<"$(pick "o.calls.find((c) => c.label === 'execute:read-steps').prompt" <<<"$out")" || { echo "read-steps never asks"; return 1; }
}

@test "every Method B skill carries the device to its subagents in the convention's words" {
  n=0
  for s in "$ROOT"/skills/workflow-*/SKILL.md; do
    n=$((n + 1))
    c="$(awk '/^## 1\. Input Contract$/{f=1;next} f&&/^## /{exit} f' "$s")"
    for f in '`device`, `device_source`, `device_from`' '`conventions/stage-dispatch.md` → Device'; do
      grep -qF -- "$f" <<<"$c" || { echo "${s#$ROOT/}: Input Contract lost $f"; return 1; }
    done
  done
  [ "$n" -eq 8 ] || { echo "scanned $n skill(s), expected 8"; return 1; }
}

S_OF() { awk -v h="## $1" '$0==h{f=1;next} f&&/^## /{exit} f' "$ROOT/skills/orchestrator/SKILL.md"; }

@test "the outbound contract carries the device and its command, always" {
  c="$(S_OF 'Outbound Contract')"
  for f in 'device=auto' 'device_source=—' 'device_from=default' '`device`, `device_source` —' '`device_from` —'; do
    grep -qF -- "$f" <<<"$c" || { echo "outbound contract lost: $f"; return 1; }
  done
}

@test "a phrase naming the device is a run setting, not a directive" {
  t="$(S_OF "The run's own words")"
  grep -qF '→ `device=<device>`' <<<"$t" || { echo "$t"; return 1; }
  ! grep -qiF 'device"' <<<"$(grep -F '**`user_directive`**' -A2 <<<"$t")" || { echo "a device phrase is still a directive example"; return 1; }
}
