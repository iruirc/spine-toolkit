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

@test "the walkthrough is refreshed after Done, which is told to keep out of it" {
  replies='{"review": {"review_status": "APPROVED", "artifact_path": "r", "summary": "s"}}'
  for p in $RANGED quick; do
    out="$(run_profile "$p" "$(contract Review ", \"review_ranges\": $TWO")" "$replies")"
    order="$(pick "o.calls.map((c) => c.label).filter((l) => l === 'done' || l === 'walkthrough').join(' ')" <<<"$out")"
    [ "$order" = 'done walkthrough' ] || { echo "profile-$p: dispatched $order"; return 1; }
    d="$(prompt_of done <<<"$out")"
    grep -qF 'Never edit /p/Tasks/ACTIVE/001-x/Walkthrough.md' <<<"$d" || { echo "profile-$p: Done is not kept out of the file"; return 1; }
    [ "$(pick "JSON.stringify(Object.keys(o.calls.find((c) => c.label === 'done').schema.properties).includes('walkthrough_findings'))" <<<"$out")" = true ] \
      || { echo "profile-$p: DONE schema has no walkthrough_findings"; return 1; }
  done
}

@test "an epic writes its walkthrough after Done, which is told to keep out of it" {
  out="$(run_profile epic "$(contract Done ", \"walkthrough\": \"deep\"")" '{"done:read-branch": {"branch": "decomposition"}}')"
  order="$(pick "o.calls.map((c) => c.label).filter((l) => l === 'done' || l === 'walkthrough').join(' ')" <<<"$out")"
  [ "$order" = 'done walkthrough' ] || { echo "dispatched $order"; return 1; }
  grep -qF 'Never edit /p/Tasks/ACTIVE/001-x/Walkthrough.md' <<<"$(prompt_of done <<<"$out")" || { echo "Done is not kept out of the file"; return 1; }
  out="$(run_profile epic "$(contract Done ", \"walkthrough\": \"off\"")" '{"done:read-branch": {"branch": "decomposition"}}')"
  if grep -qF 'Walkthrough.md' <<<"$(prompt_of done <<<"$out")"; then echo "Done names a file no writer takes"; return 1; fi
}

@test "a current walkthrough is not rewritten after a Done that committed nothing outside the tasks" {
  idle='"done": {"ok": true, "artifact_path": "d", "summary": "s", "closed_findings": [], "committed_outside_tasks": false}'
  busy='"done": {"ok": true, "artifact_path": "d", "summary": "s", "closed_findings": [], "committed_outside_tasks": true}'
  handed='"done": {"ok": true, "artifact_path": "d", "summary": "s", "closed_findings": [], "committed_outside_tasks": false, "walkthrough_findings": ["name the third commit"]}, "review": {"review_status": "APPROVED", "artifact_path": "r", "summary": "s", "done_findings": ["name the third commit"]}, "walkthrough": {"ok": true, "artifact_path": "w", "summary": "s", "changed": true}'
  approved='"review": {"review_status": "APPROVED", "artifact_path": "r", "summary": "s"}'
  for p in $RANGED quick; do
    out="$(run_profile "$p" "$(contract Review ", \"review_ranges\": $TWO, \"walkthrough_current\": true")" "{$approved, $idle}")"
    [ "$(pick "o.calls.filter((c) => c.label === 'walkthrough').length" <<<"$out")" = 0 ] || { echo "profile-$p: a writer ran over a current file"; return 1; }
    grep -qF 'so its writer was not run' <<<"$(pick 'o.result.notes' <<<"$out")" || { echo "profile-$p: the skip is not noted"; return 1; }
    [ "$(pick 'o.result.next_recommended_action' <<<"$out")" = stop ] || { echo "profile-$p: $(pick 'o.result' <<<"$out")"; return 1; }
    [ "$(pick "JSON.stringify(o.calls.find((c) => c.label === 'done').schema.required.includes('committed_outside_tasks'))" <<<"$out")" = true ] \
      || { echo "profile-$p: Done need not say whether it committed"; return 1; }
    for why in "$approved, $busy" "$handed"; do
      out="$(run_profile "$p" "$(contract Review ", \"review_ranges\": $TWO, \"walkthrough_current\": true")" "{$why}")"
      [ "$(pick "o.calls.filter((c) => c.label === 'walkthrough').length" <<<"$out")" = 1 ] || { echo "profile-$p: no writer for {$why}"; return 1; }
    done
    out="$(run_profile "$p" "$(contract Review ", \"review_ranges\": $TWO")" "{$approved, $idle}")"
    [ "$(pick "o.calls.filter((c) => c.label === 'walkthrough').length" <<<"$out")" = 1 ] || { echo "profile-$p: no writer without the orchestrator's measure"; return 1; }
  done
}

@test "a writer earlier in the run makes the file current for Done, unless its lint left lines" {
  idle='"done": {"ok": true, "artifact_path": "d", "summary": "s", "closed_findings": [], "committed_outside_tasks": false}'
  rest="\"edit\": {\"ok\": true, \"artifact_path\": \"e\", \"summary\": \"s\", \"committed\": true}, \"review\": {\"review_status\": \"APPROVED\", \"artifact_path\": \"r\", \"summary\": \"s\"}, $PASSED, $idle"
  for p in $RANGED quick; do
    case "$p" in bug) code=Fix ;; feature) code=Execute ;; refactor) code=Refactor ;; test) code=Write ;; quick) code=Edit ;; esac
    out="$(run_profile "$p" "$(contract "$code" ", \"review_ranges\": $TWO")" "{$rest}")"
    [ "$(pick "o.calls.filter((c) => c.label === 'walkthrough').length" <<<"$out")" = 1 ] || { echo "profile-$p: $(pick "o.calls.map((c) => c.label)" <<<"$out")"; return 1; }
    out="$(run_profile "$p" "$(contract "$code" ", \"review_ranges\": $TWO, \"walkthrough_current\": true")" "{$rest, \"walkthrough\": {\"ok\": true, \"artifact_path\": \"w\", \"summary\": \"s\", \"changed\": true, \"lint\": \"Walkthrough.md: count: x\"}}")"
    [ "$(pick "o.calls.filter((c) => c.label === 'walkthrough').length" <<<"$out")" = 2 ] || { echo "profile-$p: a writer that left lint lines stood for current"; return 1; }
  done
}

@test "an item about the walkthrough goes to its writer and is closed by it" {
  item='name the third commit in ## Commits'
  replies="{\"review\": {\"review_status\": \"APPROVED\", \"artifact_path\": \"r\", \"summary\": \"s\", \"done_findings\": [\"$item\"]}, \"done\": {\"ok\": true, \"artifact_path\": \"d\", \"summary\": \"s\", \"closed_findings\": [], \"walkthrough_findings\": [\"$item\"]}, \"walkthrough\": {\"ok\": true, \"artifact_path\": \"w\", \"summary\": \"s\", \"changed\": true}}"
  for p in $RANGED quick; do
    out="$(run_profile "$p" "$(contract Review ", \"review_ranges\": $TWO")" "$replies")"
    [ "$(pick 'o.result.next_recommended_action' <<<"$out")" = stop ] || { echo "profile-$p: $(pick 'o.result' <<<"$out")"; return 1; }
    grep -qF "Close these Review findings in the file, even when [COVERS] already ends at the last commit: $item" <<<"$(prompt_of walkthrough <<<"$out")" \
      || { echo "profile-$p: the writer was not handed the item"; return 1; }
  done
}

@test "an item handed to a writer that returned nothing stays open" {
  item='name the third commit in ## Commits'
  replies="{\"review\": {\"review_status\": \"APPROVED\", \"artifact_path\": \"r\", \"summary\": \"s\", \"done_findings\": [\"$item\"]}, \"done\": {\"ok\": true, \"artifact_path\": \"d\", \"summary\": \"s\", \"closed_findings\": [], \"walkthrough_findings\": [\"$item\"]}, \"walkthrough\": {\"ok\": false, \"summary\": \"s\"}}"
  for p in $RANGED quick; do
    out="$(run_profile "$p" "$(contract Review ", \"review_ranges\": $TWO")" "$replies")"
    [ "$(pick 'o.result.next_recommended_action' <<<"$out")" = ask_user ] || { echo "profile-$p: $(pick 'o.result' <<<"$out")"; return 1; }
    grep -qF "$item" <<<"$(pick 'o.result.notes' <<<"$out")" || { echo "profile-$p: the note does not name the item"; return 1; }
  done
}

@test "an item handed to a writer that changed nothing stays open" {
  item='name the third commit in ## Commits'
  replies="{\"review\": {\"review_status\": \"APPROVED\", \"artifact_path\": \"r\", \"summary\": \"s\", \"done_findings\": [\"$item\"]}, \"done\": {\"ok\": true, \"artifact_path\": \"d\", \"summary\": \"s\", \"closed_findings\": [], \"walkthrough_findings\": [\"$item\"]}, \"walkthrough\": {\"ok\": true, \"artifact_path\": \"w\", \"summary\": \"s\", \"changed\": false}}"
  for p in $RANGED quick; do
    out="$(run_profile "$p" "$(contract Review ", \"review_ranges\": $TWO")" "$replies")"
    [ "$(pick 'o.result.next_recommended_action' <<<"$out")" = ask_user ] || { echo "profile-$p: $(pick 'o.result' <<<"$out")"; return 1; }
    grep -qF 'even when [COVERS] already ends at the last commit' <<<"$(prompt_of walkthrough <<<"$out")" \
      || { echo "profile-$p: the writer may still take the change-nothing shortcut"; return 1; }
  done
}

@test "with no walkthrough written, Done closes the items about it itself" {
  replies='{"review": {"review_status": "APPROVED", "artifact_path": "r", "summary": "s"}}'
  for p in $RANGED quick; do
    out="$(run_profile "$p" "$(contract Review ", \"review_ranges\": $TWO, \"walkthrough\": \"off\"")" "$replies")"
    d="$(prompt_of done <<<"$out")"
    [ -n "$d" ] || { echo "profile-$p: Done did not run"; return 1; }
    if grep -qF 'Never edit' <<<"$d"; then echo "profile-$p: Done is told to hand items to a writer that will not run"; return 1; fi
  done
}
