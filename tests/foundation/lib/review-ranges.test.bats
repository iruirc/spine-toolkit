#!/usr/bin/env bats
# changed: sweep workflows
# What Review reads, what it may hand to Done, and how a catch-up runs — driven through the
# scripts themselves with stubbed agents, so a prompt that loses a range fails here.

load "$(dirname "$BATS_TEST_FILENAME")/../helpers/run-profile-read"

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

prompt_js() { printf '(o.calls.find((c) => c.label === "%s") || {}).prompt || ""' "$1"; }
count_js() { printf 'o.calls.filter((c) => c.label === "%s").length' "$1"; }

@test "Review counts its ranges first, with the command the contract's since names" {
  for p in $RANGED quick; do
    rp "$p" "$(contract Review ', "review_since": "base"')" '{}' "$(prompt_js review)"
    r="${V[0]}"
    for f in 'Before you read anything else, and before you overwrite Review.md, run "/core/scripts/task-ranges.sh" ranges /p/Tasks/ACTIVE/001-x --since base and keep what it prints' \
             'Review exactly those ranges, one per repository, and nothing outside them' 'under ### Scope' 'ranges_fallback'; do
      grep -qF "$f" <<<"$r" || { echo "profile-$p: review prompt lost: $f"; return 1; }
    done
    for f in '--fallback' 'Your previous review'; do
      if grep -qF -- "$f" <<<"$r"; then echo "profile-$p: a first pass got: $f"; return 1; fi
    done
    if grep -qE '[0-9]+ commits?\)' <<<"$r"; then echo "profile-$p: a count reached the brief"; return 1; fi
  done
}

@test "a re-review counts since its record, falls back per repository, and reads no approved commit again" {
  for p in $RANGED quick; do
    rp "$p" "$(contract Review ', "review_since": "reviewed", "archive_paths": ["/p/Tasks/ACTIVE/001-x/_archive/Review-2026-09-24T100000.md"]')" '{}' "$(prompt_js review)"
    r="${V[0]}"
    for f in 'ranges /p/Tasks/ACTIVE/001-x --since reviewed --fallback base and keep what it prints' '_archive/Review-2026-09-24T100000.md' \
             'Resolved, Still open or Regressed' 'do not read those commits again' 'raise no new finding on commits outside them' \
             'the owner runs restart from Review' 'When every repository it printed has 0 commits, do not rescan the tree'; do
      grep -qF -- "$f" <<<"$r" || { echo "profile-$p: re-review prompt lost: $f"; return 1; }
    done
  done
}

@test "a repository printed with no range is reviewed by its own commits" {
  for p in $RANGED; do
    rp "$p" "$(contract Review ', "review_since": "reviewed"')" '{}' "$(prompt_js review)"
    grep -qF "A repository it prints with no range: review this task's own commits there and say so under ### Scope" <<<"${V[0]}" \
      || { echo "profile-$p: no clause for a repository with no range"; return 1; }
  done
}

@test "a review_since outside the three keeps the old wording" {
  for x in '' ', "review_since": "everything"' ', "review_since": ""'; do
    for p in bug feature refactor; do
      rp "$p" "$(contract Review "$x")" '{}' "$(prompt_js review)"
      r="${V[0]}"
      grep -qF 'Review the diff this task produced' <<<"$r" || { echo "profile-$p [$x]: the old wording is gone"; return 1; }
      if grep -qF 'task-ranges.sh" ranges' <<<"$r"; then echo "profile-$p [$x]: a ranges command with a bogus since"; return 1; fi
    done
    rp test "$(contract Review "$x")" '{}' "$(prompt_js review)"
    grep -qF 'Review the TESTS this task added — not the production code' <<<"${V[0]}" || { echo "profile-test [$x]: the old wording is gone"; return 1; }
  done
}

@test "ranges_fallback reaches the profile result" {
  for p in $RANGED; do
    rp "$p" "$(contract Review ', "review_since": "reviewed"')" '{}' \
      "JSON.stringify(Object.keys(o.calls.find((c) => c.label === 'review').schema.properties).includes('ranges_fallback'))"
    [ "${V[0]}" = true ] || { echo "profile-$p: REVIEW schema has no ranges_fallback"; return 1; }
    for st in APPROVED CHANGES_REQUESTED; do
      replies='{"review": {"review_status": "'"$st"'", "artifact_path": "r", "summary": "s", "ranges_fallback": ["Packages/Core"]}, "done": {"ok": true, "artifact_path": "d", "summary": "s", "closed_findings": []}}'
      rp "$p" "$(contract Review ', "review_since": "reviewed"')" "$replies" 'JSON.stringify(o.result.ranges_fallback)'
      [ "${V[0]}" = '["Packages/Core"]' ] || { echo "profile-$p $st: ${V[0]}"; return 1; }
    done
    replies='{"review": {"review_status": "APPROVED", "artifact_path": "r", "summary": "s", "ranges_fallback": []}, "done": {"ok": true, "artifact_path": "d", "summary": "s", "closed_findings": []}}'
    rp "$p" "$(contract Review ', "review_since": "reviewed"')" "$replies" 'String("ranges_fallback" in o.result)'
    [ "${V[0]}" = false ] || { echo "profile-$p: an empty ranges_fallback reached the result"; return 1; }
  done
}

@test "Review records its tips and knows what goes to Done" {
  for p in $RANGED; do
    rp "$p" "$(contract Review ", \"review_since\": \"base\"")" '{}' "$(prompt_js review)" \
      "JSON.stringify(Object.keys(o.calls.find((c) => c.label === 'review').schema.properties).includes('done_findings'))"
    r="${V[0]}"
    for f in '/core/scripts/task-ranges.sh" tips /p/Tasks/ACTIVE/001-x --kind reviewed' 'done_findings' '## For Done' 'without a single code commit'; do
      grep -qF "$f" <<<"$r" || { echo "profile-$p: review prompt lost: $f"; return 1; }
    done
    [ "${V[1]}" = true ] \
      || { echo "profile-$p: REVIEW schema has no done_findings"; return 1; }
  done
}

@test "an APPROVED review with done_findings runs Done, which is handed them" {
  replies='{"review": {"review_status": "APPROVED", "artifact_path": "r", "summary": "s", "done_findings": ["swap the package commit in ## Release"]}, "done": {"ok": true, "artifact_path": "d", "summary": "s", "closed_findings": ["swap the package commit in ## Release"]}}'
  for p in $RANGED; do
    rp "$p" "$(contract Review ", \"review_since\": \"base\"")" "$replies" 'o.result.next_recommended_action' "$(prompt_js done)" 'o.result'
    [ "${V[0]}" = stop ] || { echo "profile-$p: ${V[2]}"; return 1; }
    d="${V[1]}"
    for f in 'swap the package commit in ## Release' '## Review findings closed' 'closed_findings' '--kind done'; do
      grep -qF -- "$f" <<<"$d" || { echo "profile-$p: done prompt lost: $f"; return 1; }
    done
  done
}

@test "Done that leaves an item open stops the run" {
  replies='{"review": {"review_status": "APPROVED", "artifact_path": "r", "summary": "s", "done_findings": ["swap the package commit"]}, "done": {"ok": true, "artifact_path": "d", "summary": "s", "closed_findings": []}}'
  for p in $RANGED; do
    rp "$p" "$(contract Review ", \"review_since\": \"base\"")" "$replies" 'o.result.next_recommended_action' 'o.result' 'o.result.notes'
    [ "${V[0]}" = ask_user ] || { echo "profile-$p: ${V[1]}"; return 1; }
    grep -qF 'swap the package commit' <<<"${V[2]}" || { echo "profile-$p: the note does not name the item"; return 1; }
  done
}

@test "CHANGES_REQUESTED still stops before Done" {
  replies='{"review": {"review_status": "CHANGES_REQUESTED", "artifact_path": "r", "summary": "s", "blocking_findings": ["a race"], "done_findings": ["x"]}}'
  for p in $RANGED; do
    rp "$p" "$(contract Review ", \"review_since\": \"base\"")" "$replies" "$(prompt_js done)"
    [ -z "${V[0]}" ] || { echo "profile-$p: Done ran after CHANGES_REQUESTED"; return 1; }
  done
}

@test "catch-up validates, reviews and closes only the delta" {
  delta='{"since": "done", "repos": {".": {"range": "d1..HEAD", "commits": 2, "state": "ok"}, "Packages/Core": {"range": "d2..HEAD", "commits": 1, "state": "ok"}}}'
  replies="{$PASSED, \"review\": {\"review_status\": \"APPROVED\", \"artifact_path\": \"r\", \"summary\": \"s\"}}"
  vr="\"validation_ranges\": {\"task\": $TWO, \"rerun\": $delta}"
  for p in $RANGED; do
    rp "$p" "$(contract Validation ", \"action\": \"catch-up\", $vr, \"review_since\": \"done\"")" "$replies" "$(prompt_js validation)" "$(prompt_js review)" "$(prompt_js done)"
    v="${V[0]}"
    grep -qF 'catches up commits that landed after' <<<"$v" || { echo "profile-$p: validation is not told it catches up"; return 1; }
    grep -qF 'Packages/Core: d2..HEAD (1 commit)' <<<"$v" || { echo "profile-$p: validation lost a range"; return 1; }
    grep -qF -- '--since done --fallback base' <<<"${V[1]}" || { echo "profile-$p: review is not ranged since Done"; return 1; }
    grep -qF 'ranges /p/Tasks/ACTIVE/001-x --since done' <<<"${V[2]}" || { echo "profile-$p: Done does not count its own ranges"; return 1; }
    grep -qF 'Catch-up: commits after Done' <<<"${V[2]}" || { echo "profile-$p: Done adds no catch-up phase"; return 1; }
  done
}

@test "the profiles without Review-then-Done code carry none of it" {
  for f in "$ROOT"/workflows/profile-*.js; do
    grep -qF "const RANGED = ['FEATURE', 'BUG', 'REFACTOR', 'TEST', 'QUICK'].includes(PROFILE)" "$f" \
      || { echo "$(basename "$f"): no RANGED gate"; return 1; }
  done
  for p in research review epic; do
    if grep -qE 'DONE_ARTIFACT|reviewScope\(|VALIDATION_SCOPE|REVIEW_VALIDATION' <<<"$(sed -n '/── end prelude/,$p' "$ROOT/workflows/profile-$p.js")"; then
      echo "profile-$p.js uses a ranged helper"; return 1
    fi
  done
}

@test "the walkthrough is refreshed after Done, which is told to keep out of it" {
  replies='{"review": {"review_status": "APPROVED", "artifact_path": "r", "summary": "s"}}'
  for p in $RANGED quick; do
    rp "$p" "$(contract Review ", \"review_since\": \"base\"")" "$replies" \
      "o.calls.map((c) => c.label).filter((l) => l === 'done' || l === 'walkthrough').join(' ')" "$(prompt_js done)" \
      "JSON.stringify(Object.keys(o.calls.find((c) => c.label === 'done').schema.properties).includes('walkthrough_findings'))"
    order="${V[0]}"
    [ "$order" = 'done walkthrough' ] || { echo "profile-$p: dispatched $order"; return 1; }
    d="${V[1]}"
    grep -qF 'Never edit /p/Tasks/ACTIVE/001-x/Walkthrough.md' <<<"$d" || { echo "profile-$p: Done is not kept out of the file"; return 1; }
    [ "${V[2]}" = true ] \
      || { echo "profile-$p: DONE schema has no walkthrough_findings"; return 1; }
  done
}

@test "an epic writes its walkthrough after Done, which is told to keep out of it" {
  rp epic "$(contract Done ", \"walkthrough\": \"deep\"")" '{"done:read-branch": {"branch": "decomposition"}}' \
    "o.calls.map((c) => c.label).filter((l) => l === 'done' || l === 'walkthrough').join(' ')" "$(prompt_js done)"
  order="${V[0]}"
  [ "$order" = 'done walkthrough' ] || { echo "dispatched $order"; return 1; }
  grep -qF 'Never edit /p/Tasks/ACTIVE/001-x/Walkthrough.md' <<<"${V[1]}" || { echo "Done is not kept out of the file"; return 1; }
  rp epic "$(contract Done ", \"walkthrough\": \"off\"")" '{"done:read-branch": {"branch": "decomposition"}}' "$(prompt_js done)"
  if grep -qF 'Walkthrough.md' <<<"${V[0]}"; then echo "Done names a file no writer takes"; return 1; fi
}

@test "a current walkthrough is not rewritten after a Done that committed nothing outside the tasks" {
  idle='"done": {"ok": true, "artifact_path": "d", "summary": "s", "closed_findings": [], "committed_outside_tasks": false}'
  busy='"done": {"ok": true, "artifact_path": "d", "summary": "s", "closed_findings": [], "committed_outside_tasks": true}'
  handed='"done": {"ok": true, "artifact_path": "d", "summary": "s", "closed_findings": [], "committed_outside_tasks": false, "walkthrough_findings": ["name the third commit"]}, "review": {"review_status": "APPROVED", "artifact_path": "r", "summary": "s", "done_findings": ["name the third commit"]}, "walkthrough": {"ok": true, "artifact_path": "w", "summary": "s", "changed": true}'
  approved='"review": {"review_status": "APPROVED", "artifact_path": "r", "summary": "s"}'
  for p in $RANGED quick; do
    rp "$p" "$(contract Review ", \"review_since\": \"base\", \"walkthrough_current\": true")" "{$approved, $idle}" \
      "$(count_js walkthrough)" 'o.result.notes' 'o.result.next_recommended_action' 'o.result' \
      "JSON.stringify(o.calls.find((c) => c.label === 'done').schema.required.includes('committed_outside_tasks'))"
    [ "${V[0]}" = 0 ] || { echo "profile-$p: a writer ran over a current file"; return 1; }
    grep -qF 'so its writer was not run' <<<"${V[1]}" || { echo "profile-$p: the skip is not noted"; return 1; }
    [ "${V[2]}" = stop ] || { echo "profile-$p: ${V[3]}"; return 1; }
    [ "${V[4]}" = true ] \
      || { echo "profile-$p: Done need not say whether it committed"; return 1; }
    rp "$p" "$(contract Review ", \"review_since\": \"base\", \"walkthrough_current\": true")" "{$approved, $busy}" "$(count_js walkthrough)"
    [ "${V[0]}" = 1 ] || { echo "profile-$p: no writer after a Done that committed outside the tasks"; return 1; }
    rp "$p" "$(contract Review ", \"review_since\": \"base\", \"walkthrough_current\": true")" "{$handed}" "$(count_js walkthrough)" "$(count_js walkthrough:patch)"
    [ "${V[0]}" = 0 ] || { echo "profile-$p: a current file was rewritten for a Review finding"; return 1; }
    [ "${V[1]}" = 1 ] || { echo "profile-$p: the finding was not patched"; return 1; }
    rp "$p" "$(contract Review ", \"review_since\": \"base\"")" "{$approved, $idle}" "$(count_js walkthrough)"
    [ "${V[0]}" = 1 ] || { echo "profile-$p: no writer without the orchestrator's measure"; return 1; }
  done
}

# A Done that committed nothing outside the tasks, over a current file, with Review findings for it.
patch_replies() { # $1 the findings as a JSON array, $2 the walkthrough:patch reply
  printf '{"review": {"review_status": "APPROVED", "artifact_path": "r", "summary": "s", "done_findings": %s}, "done": {"ok": true, "artifact_path": "d", "summary": "s", "closed_findings": [], "committed_outside_tasks": false, "walkthrough_findings": %s}, "walkthrough:patch": %s}' "$1" "$1" "$2"
}

@test "a patch that closed every finding leaves nothing unclosed" {
  item='name the third commit in ## Commits'
  patched="{\"ok\": true, \"artifact_path\": \"w\", \"summary\": \"s\", \"changed\": true, \"closed_findings\": [\"$item\"]}"
  replies="$(patch_replies "[\"$item\"]" "$patched")"
  for p in $RANGED quick; do
    rp "$p" "$(contract Review ", \"review_since\": \"base\", \"walkthrough_current\": true")" "$replies" \
      'o.result.next_recommended_action' 'o.result' 'o.result.notes'
    [ "${V[0]}" = stop ] || { echo "profile-$p: ${V[1]}"; return 1; }
    grep -qF 'Walkthrough.md patched: 1 of 1 Review finding(s) closed.' <<<"${V[2]}" \
      || { echo "profile-$p: the patch is not noted"; return 1; }
  done
}

@test "a patch that closed fewer findings leaves the rest unclosed" {
  # [RF 4]: what the patch did not close goes to unclosed() and stops the run as Done's own would.
  one='name the third commit in ## Commits'
  two='define the cache key in ## Glossary'
  patched="{\"ok\": true, \"artifact_path\": \"w\", \"summary\": \"s\", \"changed\": true, \"closed_findings\": [\"$one\"]}"
  replies="$(patch_replies "[\"$one\", \"$two\"]" "$patched")"
  for p in $RANGED quick; do
    rp "$p" "$(contract Review ", \"review_since\": \"base\", \"walkthrough_current\": true")" "$replies" \
      'o.result.next_recommended_action' 'o.result' 'o.result.notes'
    [ "${V[0]}" = ask_user ] || { echo "profile-$p: ${V[1]}"; return 1; }
    grep -qF "$two" <<<"${V[2]}" || { echo "profile-$p: the note does not name the open finding"; return 1; }
    grep -qF 'Walkthrough.md patched: 1 of 2 Review finding(s) closed.' <<<"${V[2]}" \
      || { echo "profile-$p: the patch is not noted"; return 1; }
  done
}

@test "a patch that reports findings it was not handed closes only its own" {
  # [RF 4]: an extra or repeated entry must not stand for a finding Done left open.
  mine='name the third commit in ## Commits'
  done_own='swap the package commit in ## Release'
  replies="{\"review\": {\"review_status\": \"APPROVED\", \"artifact_path\": \"r\", \"summary\": \"s\", \"done_findings\": [\"$mine\", \"$done_own\"]}, \"done\": {\"ok\": true, \"artifact_path\": \"d\", \"summary\": \"s\", \"closed_findings\": [], \"committed_outside_tasks\": false, \"walkthrough_findings\": [\"$mine\"]}, \"walkthrough:patch\": {\"ok\": true, \"artifact_path\": \"w\", \"summary\": \"s\", \"changed\": true, \"closed_findings\": [\"$mine\", \"$mine\", \"$done_own\", \"an entry of its own\"]}}"
  for p in $RANGED quick; do
    rp "$p" "$(contract Review ", \"review_since\": \"base\", \"walkthrough_current\": true")" "$replies" \
      'o.result.next_recommended_action' 'o.result' 'o.result.notes'
    [ "${V[0]}" = ask_user ] || { echo "profile-$p: ${V[1]}"; return 1; }
    grep -qF "$done_own" <<<"${V[2]}" || { echo "profile-$p: the note does not name Done's open finding"; return 1; }
    grep -qF 'Walkthrough.md patched: 1 of 1 Review finding(s) closed.' <<<"${V[2]}" \
      || { echo "profile-$p: the patch's count is not its own: ${V[2]}"; return 1; }
  done
}

@test "a patch that returned nothing is noted and stops nothing" {
  # The patch itself never ends the run, as a writer that returned nothing does not; its findings stay
  # open, so unclosed() asks, as for that writer.
  item='name the third commit in ## Commits'
  for p in $RANGED quick; do
    rp "$p" "$(contract Review ", \"review_since\": \"base\", \"walkthrough_current\": true")" "$(patch_replies "[\"$item\"]" null)" \
      'o.result.next_recommended_action' 'o.result' 'o.result.notes' 'o.result.status || ""'
    [ "${V[0]}" = ask_user ] || { echo "profile-$p: ${V[1]}"; return 1; }
    [ "${V[3]}" != error ] || { echo "profile-$p: an empty patch ended the run in an error"; return 1; }
    grep -qF 'The walkthrough patch returned nothing' <<<"${V[2]}" || { echo "profile-$p: the empty patch is not noted"; return 1; }
    grep -qF "$item" <<<"${V[2]}" || { echo "profile-$p: the note does not name the open finding"; return 1; }
  done
}

@test "a writer earlier in the run makes the file current for Done, unless its lint left lines" {
  idle='"done": {"ok": true, "artifact_path": "d", "summary": "s", "closed_findings": [], "committed_outside_tasks": false}'
  rest="\"edit\": {\"ok\": true, \"artifact_path\": \"e\", \"summary\": \"s\", \"committed\": true}, \"review\": {\"review_status\": \"APPROVED\", \"artifact_path\": \"r\", \"summary\": \"s\"}, $PASSED, $idle"
  for p in $RANGED quick; do
    case "$p" in bug) code=Fix ;; feature) code=Execute ;; refactor) code=Refactor ;; test) code=Write ;; quick) code=Edit ;; esac
    rp "$p" "$(contract "$code" ", \"walkthrough_when\": \"stage\", \"review_since\": \"base\"")" "{$rest}" "$(count_js walkthrough)" 'o.calls.map((c) => c.label)'
    [ "${V[0]}" = 1 ] || { echo "profile-$p: ${V[1]}"; return 1; }
    rp "$p" "$(contract "$code" ", \"walkthrough_when\": \"stage\", \"review_since\": \"base\", \"walkthrough_current\": true")" "{$rest, \"walkthrough\": {\"ok\": true, \"artifact_path\": \"w\", \"summary\": \"s\", \"changed\": true, \"lint\": \"Walkthrough.md: count: x\"}}" "$(count_js walkthrough)"
    [ "${V[0]}" = 2 ] || { echo "profile-$p: a writer that left lint lines stood for current"; return 1; }
  done
}

@test "a writer whose lint left only style lines still makes the file current for Done" {
  # Style findings reach the writer once (spec D-7): the writer already had them.
  idle='"done": {"ok": true, "artifact_path": "d", "summary": "s", "closed_findings": [], "committed_outside_tasks": false}'
  rest="\"edit\": {\"ok\": true, \"artifact_path\": \"e\", \"summary\": \"s\", \"committed\": true}, \"review\": {\"review_status\": \"APPROVED\", \"artifact_path\": \"r\", \"summary\": \"s\"}, $PASSED, $idle"
  style='Walkthrough.md: style: sentence of 31 words (## Summary)\nWalkthrough.md: style: missing **In short:** (### 1)'
  for p in $RANGED quick; do
    case "$p" in bug) code=Fix ;; feature) code=Execute ;; refactor) code=Refactor ;; test) code=Write ;; quick) code=Edit ;; esac
    rp "$p" "$(contract "$code" ", \"walkthrough_when\": \"stage\", \"review_since\": \"base\"")" "{$rest, \"walkthrough\": {\"ok\": true, \"artifact_path\": \"w\", \"summary\": \"s\", \"changed\": true, \"lint\": \"$style\"}}" \
      "$(count_js walkthrough)" 'o.result.notes'
    [ "${V[0]}" = 1 ] || { echo "profile-$p: a style line sent the writer back at Done"; return 1; }
    grep -qF 'Walkthrough.md lint: Walkthrough.md: style: sentence of 31 words' <<<"${V[1]}" \
      || { echo "profile-$p: the style lines left the report"; return 1; }
  done
}

@test "a writer whose lint left a style line beside a line of another class is still sent back at Done" {
  # Only style is reported without a send-back; every other class keeps it, even next to a style line.
  idle='"done": {"ok": true, "artifact_path": "d", "summary": "s", "closed_findings": [], "committed_outside_tasks": false}'
  rest="\"edit\": {\"ok\": true, \"artifact_path\": \"e\", \"summary\": \"s\", \"committed\": true}, \"review\": {\"review_status\": \"APPROVED\", \"artifact_path\": \"r\", \"summary\": \"s\"}, $PASSED, $idle"
  mixed='Walkthrough.md: style: sentence of 31 words (## Summary)\nWalkthrough.md: unreachable: abc1234 (## Commits)'
  for p in $RANGED quick; do
    case "$p" in bug) code=Fix ;; feature) code=Execute ;; refactor) code=Refactor ;; test) code=Write ;; quick) code=Edit ;; esac
    rp "$p" "$(contract "$code" ", \"walkthrough_when\": \"stage\", \"review_since\": \"base\"")" "{$rest, \"walkthrough\": {\"ok\": true, \"artifact_path\": \"w\", \"summary\": \"s\", \"changed\": true, \"lint\": \"$mixed\"}}" \
      "$(count_js walkthrough)" 'o.result.notes'
    [ "${V[0]}" = 2 ] || { echo "profile-$p: a non-style line beside a style one did not send the writer back"; return 1; }
    grep -qF 'Walkthrough.md: unreachable: abc1234' <<<"${V[1]}" \
      || { echo "profile-$p: the non-style line left the report"; return 1; }
  done
}

@test "an item about the walkthrough goes to its writer and is closed by it" {
  item='name the third commit in ## Commits'
  replies="{\"review\": {\"review_status\": \"APPROVED\", \"artifact_path\": \"r\", \"summary\": \"s\", \"done_findings\": [\"$item\"]}, \"done\": {\"ok\": true, \"artifact_path\": \"d\", \"summary\": \"s\", \"closed_findings\": [], \"walkthrough_findings\": [\"$item\"]}, \"walkthrough\": {\"ok\": true, \"artifact_path\": \"w\", \"summary\": \"s\", \"changed\": true}}"
  for p in $RANGED quick; do
    rp "$p" "$(contract Review ", \"review_since\": \"base\"")" "$replies" 'o.result.next_recommended_action' 'o.result' "$(prompt_js walkthrough)"
    [ "${V[0]}" = stop ] || { echo "profile-$p: ${V[1]}"; return 1; }
    grep -qF "Close these Review findings in the file, even when [COVERS] already ends at the last commit: $item" <<<"${V[2]}" \
      || { echo "profile-$p: the writer was not handed the item"; return 1; }
  done
}

@test "an item handed to a writer that returned nothing stays open" {
  item='name the third commit in ## Commits'
  replies="{\"review\": {\"review_status\": \"APPROVED\", \"artifact_path\": \"r\", \"summary\": \"s\", \"done_findings\": [\"$item\"]}, \"done\": {\"ok\": true, \"artifact_path\": \"d\", \"summary\": \"s\", \"closed_findings\": [], \"walkthrough_findings\": [\"$item\"]}, \"walkthrough\": {\"ok\": false, \"summary\": \"s\"}}"
  for p in $RANGED quick; do
    rp "$p" "$(contract Review ", \"review_since\": \"base\"")" "$replies" 'o.result.next_recommended_action' 'o.result' 'o.result.notes'
    [ "${V[0]}" = ask_user ] || { echo "profile-$p: ${V[1]}"; return 1; }
    grep -qF "$item" <<<"${V[2]}" || { echo "profile-$p: the note does not name the item"; return 1; }
  done
}

@test "an item handed to a writer that changed nothing stays open" {
  item='name the third commit in ## Commits'
  replies="{\"review\": {\"review_status\": \"APPROVED\", \"artifact_path\": \"r\", \"summary\": \"s\", \"done_findings\": [\"$item\"]}, \"done\": {\"ok\": true, \"artifact_path\": \"d\", \"summary\": \"s\", \"closed_findings\": [], \"walkthrough_findings\": [\"$item\"]}, \"walkthrough\": {\"ok\": true, \"artifact_path\": \"w\", \"summary\": \"s\", \"changed\": false}}"
  for p in $RANGED quick; do
    rp "$p" "$(contract Review ", \"review_since\": \"base\"")" "$replies" 'o.result.next_recommended_action' 'o.result' "$(prompt_js walkthrough)"
    [ "${V[0]}" = ask_user ] || { echo "profile-$p: ${V[1]}"; return 1; }
    grep -qF 'even when [COVERS] already ends at the last commit' <<<"${V[2]}" \
      || { echo "profile-$p: the writer may still take the change-nothing shortcut"; return 1; }
  done
}

@test "with no walkthrough written, Done closes the items about it itself" {
  replies='{"review": {"review_status": "APPROVED", "artifact_path": "r", "summary": "s"}}'
  for p in $RANGED quick; do
    rp "$p" "$(contract Review ", \"review_since\": \"base\", \"walkthrough\": \"off\"")" "$replies" "$(prompt_js done)"
    d="${V[0]}"
    [ -n "$d" ] || { echo "profile-$p: Done did not run"; return 1; }
    if grep -qF 'Never edit' <<<"$d"; then echo "profile-$p: Done is told to hand items to a writer that will not run"; return 1; fi
  done
}

@test "Review and Done write their record lines in the closing block, in all eight scripts" {
  for p in bug feature refactor test quick research review epic; do
    f="$ROOT/workflows/profile-$p.js"
    grep -qF 'at the end, write those lines in the closing block of Review.md, exactly as printed; the first line stays the status line' "$f" || { echo "profile-$p: Review sentence"; return 1; }
    grep -qF 'The closing block of Done.md holds the lines "${core('"'"'scripts/task-ranges.sh'"'"')}" tips ${DIR} --kind done prints, run right before you finish.' "$f" || { echo "profile-$p: Done sentence"; return 1; }
    ! grep -qE 'directly under the first line|The first lines of Done.md' "$f" || { echo "profile-$p: an old position is left"; return 1; }
  done
  for p in $RANGED; do
    rp "$p" "$(contract Review ", \"review_since\": \"base\"")" '{}' "$(prompt_js review)"
    grep -qF 'write those lines in the closing block of Review.md, exactly as printed; the first line stays the status line' <<<"${V[0]}" || { echo "profile-$p: review prompt"; return 1; }
  done
}
