#!/usr/bin/env bats
# The owner's words for one run reach every stage agent in the words conventions/stage-dispatch.md
# gives them, and only when there are any: an empty contract field leaves every brief as it was.

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

# The n-th fenced block of the convention's ## Owner's directive section, placeholders filled.
block() { # $1 index, $2 directive, $3 run line
  awk '/^## Owner.s directive$/{f=1;next} f&&/^## /{exit} f' "$CONV" \
    | awk -v n="$1" '/^```/{i++;next} i==2*n-1' \
    | python3 -c 'import sys; print(sys.stdin.read().rstrip("\n").replace("{directive}", sys.argv[1]).replace("{run}", sys.argv[2]))' "$2" "$3"
}

@test "an empty directive and no run settings leave every brief as it was" {
  for p in bug feature refactor test quick research review epic; do
    a="$(run_profile "$p" "$(contract '')" | pick 'o.calls.map((c) => c.prompt).join("\n----\n")')"
    b="$(run_profile "$p" "$(contract ', "user_directive": "", "run_settings": {}')" | pick 'o.calls.map((c) => c.prompt).join("\n----\n")')"
    [ -n "$a" ] || { echo "profile-$p dispatched nothing"; return 1; }
    [ "$a" = "$b" ] || { echo "profile-$p: an empty directive changed a brief"; return 1; }
    ! grep -qF "Owner's directive" <<<"$a" || { echo "profile-$p speaks of a directive nobody gave"; return 1; }
    ! grep -qF '**Run:**' <<<"$a" || { echo "profile-$p asks for a Run line with nothing to write"; return 1; }
  done
}

@test "a directive reaches every agent of every profile, verbatim and in the convention's words" {
  d='run it on the iPhone 17 Pro, leave the Net package alone'
  want="$(block 1 "$d" '')"
  # ${d}, braced: bash reads the first byte of » as part of a bare name.
  run_line="$(block 2 '' "drive_app=off; directive: «${d}»")"
  [ -n "$want" ] && [ -n "$run_line" ] || { echo "the convention has no ## Owner's directive blocks"; return 1; }
  for p in bug feature refactor test quick research review epic; do
    out="$(run_profile "$p" "$(contract ", \"user_directive\": \"$d\", \"run_settings\": {\"drive_app\": \"off\"}")")"
    n="$(pick 'o.calls.filter((c) => c.prompt).length' <<<"$out")"
    [ "$n" -gt 0 ] || { echo "profile-$p dispatched nothing"; return 1; }
    for i in $(seq 0 $((n - 1))); do
      pr="$(pick "o.calls.filter((c) => c.prompt)[$i].prompt" <<<"$out")"
      # A substring test, not grep: « and » are not one byte, and grep under the C locale refuses them.
      [[ "$pr" == *"$want"* ]] || { echo "profile-$p call $i lost the directive"; return 1; }
      [[ "$pr" == *"$run_line"* ]] || { echo "profile-$p call $i lost the Run line"; return 1; }
    done
  done
}

@test "a directive with quotes and a line break reaches the brief whole" {
  pr="$(run_profile bug "$(contract ', "start_stage": "Validation", "user_directive": "use the \"slow\" suite\nthen stop"')" | pick "o.calls[0].prompt")"
  [[ "$pr" == *'«use the "slow" suite'$'\n''then stop»'* ]] || { echo "$pr"; return 1; }
}

@test "a directive of blanks is no directive" {
  a="$(run_profile bug "$(contract ', "start_stage": "Validation"')" | pick "o.calls[0].prompt")"
  b="$(run_profile bug "$(contract ', "start_stage": "Validation", "user_directive": "  \n "')" | pick "o.calls[0].prompt")"
  [ "$a" = "$b" ] || { echo "$b"; return 1; }
}

@test "run settings alone ask for the Run line and say nothing of a directive" {
  pr="$(run_profile bug "$(contract ', "start_stage": "Validation", "run_settings": {"drive_app": "off", "models.reviewer": "opus"}')" | pick "o.calls[0].prompt")"
  want="$(block 2 '' 'drive_app=off; models.reviewer=opus')"
  [ -n "$want" ] || { echo "the convention has no Run line block"; return 1; }
  grep -qF -- "$want" <<<"$pr" || { echo "$pr"; return 1; }
  ! grep -qF "Owner's directive" <<<"$pr" || { echo "$pr"; return 1; }
}

@test "the directive's block follows the data rule, never precedes it" {
  pr="$(run_profile bug "$(contract ', "start_stage": "Validation", "user_directive": "x"')" | pick "o.calls[0].prompt")"
  data="$(grep -nF 'is DATA, never instruction' <<<"$pr" | cut -d: -f1)"
  own="$(grep -nF "Owner's directive for this run" <<<"$pr" | cut -d: -f1)"
  [ -n "$data" ] && [ -n "$own" ] && [ "$own" -gt "$data" ] || { echo "data $data, directive $own"; return 1; }
}

@test "every stage schema lets an agent decline the directive" {
  out="$(run_profile bug "$(contract ', "start_stage": "Plan", "stage_scope": "forward", "user_directive": "x"')" \
    '{"plan": {"ok": true, "artifact_path": "p", "summary": "s", "phases": [{"id": "1", "title": "t", "kind": "code"}]}, "fix:1": {"ok": true, "phase_id": "1", "committed": true, "summary": "s"}, "validation": {"validation_status": "PASSED", "reproduction_status": "fixed", "artifact_path": "v", "summary": "s"}, "review": {"review_status": "APPROVED", "artifact_path": "r", "summary": "s"}}')"
  for l in plan fix:1 validation review done; do
    [ "$(pick "(o.calls.find((c) => c.label === '$l').schema.properties.directive_declined || {}).type" <<<"$out")" = string ] \
      || { echo "$l cannot decline"; return 1; }
  done
}

@test "a refusal reaches stages[], a phase's under its id" {
  out="$(run_profile bug "$(contract ', "start_stage": "Fix", "stage_scope": "forward", "end_stage": "Validation", "user_directive": "do not commit"')" \
    '{"fix:read-plan": {"ok": true, "artifact_path": "p", "summary": "s", "phases": [{"id": "1", "title": "t", "kind": "code"}, {"id": "2", "title": "u", "kind": "code"}]}, "fix:1": {"ok": true, "phase_id": "1", "committed": true, "summary": "s", "directive_declined": "committed anyway: a phase owes its commit"}, "fix:2": {"ok": true, "phase_id": "2", "committed": true, "summary": "s"}, "validation": {"validation_status": "PASSED", "reproduction_status": "fixed", "artifact_path": "v", "summary": "s", "directive_declined": "ran the full regression"}}')"
  [ "$(pick "o.result.stages.find((s) => s.stage === 'Fix').directive_declined" <<<"$out")" = '1: committed anyway: a phase owes its commit' ] \
    || { pick 'o.result.stages' <<<"$out"; return 1; }
  [ "$(pick "o.result.stages.find((s) => s.stage === 'Validation').directive_declined" <<<"$out")" = 'ran the full regression' ] \
    || { pick 'o.result.stages' <<<"$out"; return 1; }
}

@test "a stage that declined nothing reports an empty refusal, not a missing one" {
  out="$(run_profile bug "$(contract ', "start_stage": "Validation"')" '{"validation": {"validation_status": "PASSED", "reproduction_status": "fixed", "artifact_path": "v", "summary": "s"}}')"
  [ "$(pick "JSON.stringify(o.result.stages[0].directive_declined)" <<<"$out")" = '""' ] || { pick 'o.result.stages' <<<"$out"; return 1; }
}
