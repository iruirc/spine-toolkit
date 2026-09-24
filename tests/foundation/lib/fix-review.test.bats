#!/usr/bin/env bats
# One round of the fix loop, driven through the scripts with stubbed agents: the findings become
# one phase, and nothing downstream runs on a phase that did not commit.

setup() {
  ROOT="$(cd -- "$(dirname -- "$BATS_TEST_FILENAME")/../../.." && pwd)"
  AGENTS='{"architect":"a","developer":"d","tester":"t","reviewer":"r","refactorer":"f","validator":"v","security":"—","diagnostics":"g","init":"—"}'
  RANGES='{"since": "reviewed", "repos": {".": {"range": "c3..HEAD", "commits": 1, "state": "ok"}}}'
  FINDINGS='["a race in the cache", "the retry never stops"]'
}

# profile:stage pairs — the stage that changes code in each ranged profile.
PAIRS="bug:Fix feature:Execute refactor:Refactor test:Write"

contract() { # $1 start stage, $2 extra JSON members (leading comma)
  printf '{"task_id": "001", "task_dir": "/p/Tasks/ACTIVE/001-x", "plugin_root": "/core", "lang": "en", "agents": %s, "start_stage": "%s", "stage_scope": "forward", "review_ranges": %s%s}' "$AGENTS" "$1" "$RANGES" "$2"
}

replies() { # $1 lower-case stage, $2 committed true|false
  printf '{"%s:R2": {"ok": true, "phase_id": "R2", "committed": %s, "summary": "s"}, "%s:1": {"ok": true, "phase_id": "1", "committed": true, "summary": "s"}, "%s:read-plan": {"ok": true, "artifact_path": "p", "summary": "s", "phases": [{"id": "1", "title": "t", "kind": "code"}]}, "validation": {"validation_status": "PASSED", "reproduction_status": "fixed", "artifact_path": "v", "summary": "s", "driver_status": "ok"}, "review": {"review_status": "APPROVED", "artifact_path": "r", "summary": "s"}, "done": {"ok": true, "artifact_path": "d", "summary": "s", "closed_findings": []}}' "$1" "$2" "$1" "$1"
}

run_profile() { node "$ROOT/tests/foundation/helpers/run-profile.js" "$ROOT/workflows/profile-$1.js" "$2" "$3"; }

pick() { node -e 'const o = JSON.parse(require("fs").readFileSync(0, "utf8")); const v = eval(process.argv[1]); console.log(typeof v === "string" ? v : JSON.stringify(v))' "$1"; }

prompt_of() { pick "(o.calls.find((c) => c.label === '$1') || {}).prompt || ''"; }

@test "fix-review runs one phase built from the findings, never reading the plan" {
  for pair in $PAIRS; do
    p="${pair%%:*}"; s="${pair#*:}"; l="$(tr '[:upper:]' '[:lower:]' <<<"$s")"
    out="$(run_profile "$p" "$(contract "$s" ", \"action\": \"fix-review\", \"fix_findings\": $FINDINGS, \"fix_round\": 2, \"after_done\": false")" "$(replies "$l" true)")"
    [ "$(pick "o.calls.filter((c) => c.label.endsWith(':read-plan')).length" <<<"$out")" = 0 ] || { echo "profile-$p read the plan"; return 1; }
    ph="$(prompt_of "$l:R2" <<<"$out")"
    for f in 'Review fixes 2' 'not in Plan.md yet' 'a race in the cache' 'the retry never stops' 'phase-verification'; do
      grep -qF "$f" <<<"$ph" || { echo "profile-$p: the fix phase lost: $f"; return 1; }
    done
    for l2 in validation review done; do
      [ -n "$(prompt_of "$l2" <<<"$out")" ] || { echo "profile-$p: $l2 did not run after the fix"; return 1; }
    done
    [ "$(pick 'o.result.next_recommended_action' <<<"$out")" = stop ] || { echo "profile-$p: $(pick 'o.result' <<<"$out")"; return 1; }
  done
}

@test "only fixes after a catch-up carry the catch-up duty to Done" {
  for pair in $PAIRS; do
    p="${pair%%:*}"; s="${pair#*:}"; l="$(tr '[:upper:]' '[:lower:]' <<<"$s")"
    d="$(run_profile "$p" "$(contract "$s" ", \"action\": \"fix-review\", \"fix_findings\": $FINDINGS, \"fix_round\": 2, \"after_done\": true")" "$(replies "$l" true)" | prompt_of done)"
    for f in 'Catch-up: commits after Done' '/core/scripts/task-ranges.sh" ranges /p/Tasks/ACTIVE/001-x --since done'; do
      grep -qF "$f" <<<"$d" || { echo "profile-$p: after_done Done lost: $f"; return 1; }
    done
    d="$(run_profile "$p" "$(contract "$s" ", \"action\": \"fix-review\", \"fix_findings\": $FINDINGS, \"fix_round\": 2, \"after_done\": false")" "$(replies "$l" true)" | prompt_of done)"
    if grep -qF 'Catch-up: commits after Done' <<<"$d"; then echo "profile-$p: Done got the catch-up duty without after_done"; return 1; fi
  done
}

@test "a fix phase that does not commit stops the run" {
  for pair in $PAIRS; do
    p="${pair%%:*}"; s="${pair#*:}"; l="$(tr '[:upper:]' '[:lower:]' <<<"$s")"
    out="$(run_profile "$p" "$(contract "$s" ", \"action\": \"fix-review\", \"fix_findings\": $FINDINGS, \"fix_round\": 2, \"after_done\": false")" "$(replies "$l" false)")"
    [ -z "$(prompt_of validation <<<"$out")" ] || { echo "profile-$p: Validation ran on an uncommitted fix"; return 1; }
    [ "$(pick 'o.result.next_recommended_action' <<<"$out")" = ask_user ] || { echo "profile-$p: $(pick 'o.result' <<<"$out")"; return 1; }
  done
}

@test "an empty fix_findings reads the plan as before" {
  for pair in $PAIRS; do
    p="${pair%%:*}"; s="${pair#*:}"; l="$(tr '[:upper:]' '[:lower:]' <<<"$s")"
    out="$(run_profile "$p" "$(contract "$s" ", \"action\": \"fix-review\", \"fix_findings\": [], \"fix_round\": 2, \"after_done\": false")" "$(replies "$l" true)")"
    [ -n "$(prompt_of "$l:read-plan" <<<"$out")" ] || { echo "profile-$p: no read-plan with empty findings"; return 1; }
    [ -z "$(prompt_of "$l:R2" <<<"$out")" ] || { echo "profile-$p: an empty fix phase ran"; return 1; }
  done
}

@test "without fix-review the phase brief is as before" {
  for pair in $PAIRS; do
    p="${pair%%:*}"; s="${pair#*:}"; l="$(tr '[:upper:]' '[:lower:]' <<<"$s")"
    ph="$(run_profile "$p" "$(contract "$s" '')" "$(replies "$l" true)" | prompt_of "$l:1")"
    [ -n "$ph" ] || { echo "profile-$p: the planned phase did not run"; return 1; }
    if grep -qF 'not in Plan.md yet' <<<"$ph"; then echo "profile-$p: a plain run got the fix guidance"; return 1; fi
  done
}
