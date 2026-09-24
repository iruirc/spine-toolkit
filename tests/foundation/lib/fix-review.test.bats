#!/usr/bin/env bats
# One round of the fix loop, driven through the scripts with stubbed agents: the findings become
# one phase, and nothing downstream runs on a phase that did not commit.

setup() {
  ROOT="$(cd -- "$(dirname -- "$BATS_TEST_FILENAME")/../../.." && pwd)"
  AGENTS='{"architect":"a","developer":"d","tester":"t","reviewer":"r","refactorer":"f","validator":"v","security":"—","diagnostics":"g","init":"—"}'
  RANGES='{"since": "reviewed", "repos": {".": {"range": "c3..HEAD", "commits": 0, "state": "ok"}}}'
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

@test "a Review after this run's own fix reads the range, not the counts taken before it" {
  for pair in $PAIRS; do
    p="${pair%%:*}"; s="${pair#*:}"; l="$(tr '[:upper:]' '[:lower:]' <<<"$s")"
    r="$(run_profile "$p" "$(contract "$s" ", \"action\": \"fix-review\", \"fix_findings\": $FINDINGS, \"fix_round\": 2, \"after_done\": false")" "$(replies "$l" true)" | prompt_of review)"
    grep -qF '.: c3..HEAD' <<<"$r" || { echo "profile-$p: Review lost the range"; return 1; }
    grep -qF "The commits this run's own phases added are inside these ranges." <<<"$r" || { echo "profile-$p: Review is not told of the fix commits"; return 1; }
    for f in 'do not rescan' '(0 commits)'; do
      if grep -qF "$f" <<<"$r"; then echo "profile-$p: Review got the stale: $f"; return 1; fi
    done
  done
}

@test "a re-review carries a still-open prior finding into its own findings" {
  for pair in $PAIRS; do
    p="${pair%%:*}"; s="${pair#*:}"; l="$(tr '[:upper:]' '[:lower:]' <<<"$s")"
    r="$(run_profile "$p" "$(contract "$s" ", \"action\": \"fix-review\", \"fix_findings\": $FINDINGS, \"fix_round\": 2, \"after_done\": false")" "$(replies "$l" true)" | prompt_of review)"
    grep -qF 'A prior Critical or Major that is Still open or Regressed is a finding of this review too: list it under ### Findings at its severity and in blocking_findings.' <<<"$r" || { echo "profile-$p: still-open findings are not carried"; return 1; }
  done
}

@test "CHANGES_REQUESTED returns the reviewer's findings" {
  for pair in $PAIRS; do
    p="${pair%%:*}"; s="${pair#*:}"; l="$(tr '[:upper:]' '[:lower:]' <<<"$s")"
    rep="$(replies "$l" true | node -e 'const o = JSON.parse(require("fs").readFileSync(0, "utf8")); o.review = {review_status: "CHANGES_REQUESTED", artifact_path: "r", summary: "s", blocking_findings: ["a race"], done_findings: ["a typo in Plan.md"]}; console.log(JSON.stringify(o))')"
    out="$(run_profile "$p" "$(contract "$s" ", \"action\": \"fix-review\", \"fix_findings\": $FINDINGS, \"fix_round\": 2, \"after_done\": false")" "$rep")"
    [ "$(pick 'o.result.blocking_findings' <<<"$out")" = '["a race"]' ] || { echo "profile-$p: $(pick 'o.result' <<<"$out")"; return 1; }
    [ "$(pick 'o.result.done_findings' <<<"$out")" = '["a typo in Plan.md"]' ] || { echo "profile-$p: done_findings lost"; return 1; }
  done
}

@test "the fix phase takes on no work its findings do not ask for" {
  for pair in $PAIRS; do
    p="${pair%%:*}"; s="${pair#*:}"; l="$(tr '[:upper:]' '[:lower:]' <<<"$s")"
    ph="$(run_profile "$p" "$(contract "$s" ", \"action\": \"fix-review\", \"fix_findings\": $FINDINGS, \"fix_round\": 2, \"after_done\": false")" "$(replies "$l" true)" | prompt_of "$l:R2")"
    grep -qF 'Nothing in the stage guidance above adds work to this phase — a regression test included — unless a finding asks for it.' <<<"$ph" || { echo "profile-$p: stage guidance still adds work"; return 1; }
  done
}

@test "the catch-up phase is a progress-table row, and after_done counts its ranges before Done.md changes" {
  for pair in $PAIRS; do
    p="${pair%%:*}"; s="${pair#*:}"; l="$(tr '[:upper:]' '[:lower:]' <<<"$s")"
    d="$(run_profile "$p" "$(contract "$s" ", \"action\": \"fix-review\", \"fix_findings\": $FINDINGS, \"fix_round\": 2, \"after_done\": true")" "$(replies "$l" true)" | prompt_of done)"
    for f in '"Catch-up: commits after Done" — a row in the top-level progress table and a detail section' 'before you rewrite Done.md, run'; do
      grep -qF "$f" <<<"$d" || { echo "profile-$p: after_done Done lost: $f"; return 1; }
    done
    d="$(run_profile "$p" "$(contract Validation ", \"action\": \"catch-up\"")" "$(replies "$l" true)" | prompt_of done)"
    grep -qF '"Catch-up: commits after Done" — a row in the top-level progress table and a detail section' <<<"$d" || { echo "profile-$p: catch-up Done appends no table row"; return 1; }
  done
}
