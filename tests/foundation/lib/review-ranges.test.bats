#!/usr/bin/env bats
# What Review reads, what it may hand to Done, and how a catch-up runs — driven through the
# scripts themselves with stubbed agents, so a prompt that loses a range fails here.

setup() {
  ROOT="$(cd -- "$(dirname -- "$BATS_TEST_FILENAME")/../../.." && pwd)"
  RANGED="bug feature refactor test"
  AGENTS='{"architect":"a","developer":"d","tester":"t","reviewer":"r","refactorer":"f","validator":"v","security":"—","diagnostics":"g","init":"—"}'
  TWO='{"since": "base", "repos": {".": {"range": "a1..HEAD", "commits": 3, "state": "ok"}, "Packages/Core": {"range": "b2..HEAD", "commits": 1, "state": "ok"}}}'
  PASSED='"validation": {"validation_status": "PASSED", "reproduction_status": "fixed", "artifact_path": "v", "summary": "s", "driver_status": "ok"}'
}

contract() { # $1 start stage, $2 extra JSON members (leading comma)
  printf '{"task_id": "001", "task_dir": "/p/Tasks/ACTIVE/001-x", "plugin_root": "/core", "lang": "en", "agents": %s, "start_stage": "%s", "stage_scope": "forward"%s}' "$AGENTS" "$1" "$2"
}

run_profile() { node "$ROOT/tests/foundation/helpers/run-profile.js" "$ROOT/workflows/profile-$1.js" "$2" "$3"; }

pick() { # $1 JS expression over o; stdin: harness output
  node -e 'const o = JSON.parse(require("fs").readFileSync(0, "utf8")); const v = eval(process.argv[1]); console.log(typeof v === "string" ? v : JSON.stringify(v))' "$1"
}

prompt_of() { pick "(o.calls.find((c) => c.label === '$1') || {}).prompt || ''"; }

@test "Review reads exactly the ranges the contract names" {
  for p in $RANGED; do
    out="$(run_profile "$p" "$(contract Review ", \"review_ranges\": $TWO")" '{}')"
    r="$(prompt_of review <<<"$out")"
    for f in 'Review exactly these ranges, one per repository' '.: a1..HEAD (3 commits)' 'Packages/Core: b2..HEAD (1 commit)'; do
      grep -qF "$f" <<<"$r" || { echo "profile-$p: review prompt lost: $f"; return 1; }
    done
    if grep -qF 'Your previous review' <<<"$r"; then echo "profile-$p: a first pass is told of a previous review"; return 1; fi
  done
}

@test "a re-review checks the previous findings, and an idle one does not rescan" {
  idle='{"since": "reviewed", "repos": {".": {"range": "a1..HEAD", "commits": 0, "state": "ok"}}}'
  for p in $RANGED; do
    out="$(run_profile "$p" "$(contract Review ", \"review_ranges\": $idle, \"archive_paths\": [\"/p/Tasks/ACTIVE/001-x/_archive/Review-2026-09-24T100000.md\"]")" '{}')"
    r="$(prompt_of review <<<"$out")"
    for f in '_archive/Review-2026-09-24T100000.md' 'Resolved, Still open or Regressed' 'do not rescan the tree'; do
      grep -qF "$f" <<<"$r" || { echo "profile-$p: re-review prompt lost: $f"; return 1; }
    done
  done
}

@test "a repository with no known base is scoped by hand, never read as idle" {
  blind='{"since": "reviewed", "repos": {".": {"range": "a1..HEAD", "commits": 0, "state": "ok"}, "Packages/Core": {"range": null, "commits": null, "state": "unknown"}}}'
  for p in $RANGED; do
    out="$(run_profile "$p" "$(contract Review ", \"review_ranges\": $blind, \"archive_paths\": [\"/p/Tasks/ACTIVE/001-x/_archive/Review-2026-09-24T100000.md\"]")" '{}')"
    r="$(prompt_of review <<<"$out")"
    grep -qF "Packages/Core: no known base — review this task's own commits there" <<<"$r" || { echo "profile-$p: no clause for the unknown repository"; return 1; }
    if grep -qF 'do not rescan the tree' <<<"$r"; then echo "profile-$p: an unknown repository reads as idle"; return 1; fi
  done
}

@test "without review_ranges the Review prompt reads as before" {
  for p in bug feature refactor; do
    r="$(run_profile "$p" "$(contract Review '')" '{}' | prompt_of review)"
    grep -qF 'Review the diff this task produced' <<<"$r" || { echo "profile-$p: the old wording is gone"; return 1; }
  done
  r="$(run_profile test "$(contract Review '')" '{}' | prompt_of review)"
  grep -qF 'Review the TESTS this task added — not the production code' <<<"$r" || { echo "profile-test: the old wording is gone"; return 1; }
}

@test "Review records its tips and knows what goes to Done" {
  for p in $RANGED; do
    out="$(run_profile "$p" "$(contract Review ", \"review_ranges\": $TWO")" '{}')"
    r="$(prompt_of review <<<"$out")"
    for f in '/core/scripts/task-ranges.sh" tips /p/Tasks/ACTIVE/001-x --kind reviewed' 'done_findings' '## For Done' 'without a single code commit'; do
      grep -qF "$f" <<<"$r" || { echo "profile-$p: review prompt lost: $f"; return 1; }
    done
    [ "$(pick "JSON.stringify(Object.keys(o.calls.find((c) => c.label === 'review').schema.properties).includes('done_findings'))" <<<"$out")" = true ] \
      || { echo "profile-$p: REVIEW schema has no done_findings"; return 1; }
  done
}

@test "an APPROVED review with done_findings runs Done, which is handed them" {
  replies='{"review": {"review_status": "APPROVED", "artifact_path": "r", "summary": "s", "done_findings": ["swap the package commit in ## Release"]}, "done": {"ok": true, "artifact_path": "d", "summary": "s", "closed_findings": ["swap the package commit in ## Release"]}}'
  for p in $RANGED; do
    out="$(run_profile "$p" "$(contract Review ", \"review_ranges\": $TWO")" "$replies")"
    [ "$(pick 'o.result.next_recommended_action' <<<"$out")" = stop ] || { echo "profile-$p: $(pick 'o.result' <<<"$out")"; return 1; }
    d="$(prompt_of done <<<"$out")"
    for f in 'swap the package commit in ## Release' '## Review findings closed' 'closed_findings' '--kind done'; do
      grep -qF -- "$f" <<<"$d" || { echo "profile-$p: done prompt lost: $f"; return 1; }
    done
  done
}

@test "Done that leaves an item open stops the run" {
  replies='{"review": {"review_status": "APPROVED", "artifact_path": "r", "summary": "s", "done_findings": ["swap the package commit"]}, "done": {"ok": true, "artifact_path": "d", "summary": "s", "closed_findings": []}}'
  for p in $RANGED; do
    out="$(run_profile "$p" "$(contract Review ", \"review_ranges\": $TWO")" "$replies")"
    [ "$(pick 'o.result.next_recommended_action' <<<"$out")" = ask_user ] || { echo "profile-$p: $(pick 'o.result' <<<"$out")"; return 1; }
    grep -qF 'swap the package commit' <<<"$(pick 'o.result.notes' <<<"$out")" || { echo "profile-$p: the note does not name the item"; return 1; }
  done
}

@test "CHANGES_REQUESTED still stops before Done" {
  replies='{"review": {"review_status": "CHANGES_REQUESTED", "artifact_path": "r", "summary": "s", "blocking_findings": ["a race"], "done_findings": ["x"]}}'
  for p in $RANGED; do
    out="$(run_profile "$p" "$(contract Review ", \"review_ranges\": $TWO")" "$replies")"
    [ -z "$(prompt_of done <<<"$out")" ] || { echo "profile-$p: Done ran after CHANGES_REQUESTED"; return 1; }
  done
}

@test "catch-up validates, reviews and closes only the delta" {
  delta='{"since": "done", "repos": {".": {"range": "d1..HEAD", "commits": 2, "state": "ok"}, "Packages/Core": {"range": "d2..HEAD", "commits": 1, "state": "ok"}}}'
  replies="{$PASSED, \"review\": {\"review_status\": \"APPROVED\", \"artifact_path\": \"r\", \"summary\": \"s\"}}"
  for p in $RANGED; do
    out="$(run_profile "$p" "$(contract Validation ", \"action\": \"catch-up\", \"review_ranges\": $delta")" "$replies")"
    v="$(prompt_of validation <<<"$out")"
    grep -qF 'catches up commits that landed after' <<<"$v" || { echo "profile-$p: validation is not told it catches up"; return 1; }
    grep -qF 'Packages/Core: d2..HEAD (1 commit)' <<<"$v" || { echo "profile-$p: validation lost a range"; return 1; }
    grep -qF 'Review exactly these ranges' <<<"$(prompt_of review <<<"$out")" || { echo "profile-$p: review is not ranged"; return 1; }
    grep -qF 'Catch-up: commits after Done' <<<"$(prompt_of done <<<"$out")" || { echo "profile-$p: Done adds no catch-up phase"; return 1; }
  done
}

@test "the profiles without Review-then-Done code carry none of it" {
  for f in "$ROOT"/workflows/profile-*.js; do
    grep -qF "const RANGED = ['FEATURE', 'BUG', 'REFACTOR', 'TEST', 'QUICK'].includes(PROFILE)" "$f" \
      || { echo "$(basename "$f"): no RANGED gate"; return 1; }
  done
  for p in research review epic; do
    if grep -qE 'DONE_ARTIFACT|reviewScope\(|CATCH_UP_VALIDATION\}' <<<"$(sed -n '/── end prelude/,$p' "$ROOT/workflows/profile-$p.js")"; then
      echo "profile-$p.js uses a ranged helper"; return 1
    fi
  done
}
