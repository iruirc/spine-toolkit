#!/usr/bin/env bats
# changed: sweep workflows
# What Validation is told about the task's commits and the regression set, and what Review reads
# before it re-runs anything — driven through the scripts with stubbed agents, so a prompt that
# loses a range or a rule fails here.

load "$(dirname "$BATS_TEST_FILENAME")/../helpers/run-profile-read"

setup() {
  ROOT="$(cd -- "$(dirname -- "$BATS_TEST_FILENAME")/../../.." && pwd)"
  RANGED="bug feature refactor test quick"
  AGENTS='{"architect":"a","developer":"d","tester":"t","reviewer":"r","refactorer":"f","validator":"v","security":"—","diagnostics":"g","init":"—"}'
  TWO='{"since": "base", "repos": {".": {"range": "a1..HEAD", "commits": 3, "state": "ok"}, "Packages/Core": {"range": "b2..HEAD", "commits": 1, "state": "ok"}}}'
  RERUN='{"since": "validated", "repos": {".": {"range": "c3..HEAD", "commits": 2, "state": "ok"}, "Packages/Core": {"range": "d4..HEAD", "commits": 0, "state": "ok"}}}'
  # Built here: bash 3.2 mis-parses a quoted brace inside "$( ... )" in the test bodies.
  FIRST=", \"validation_ranges\": {\"task\": $TWO, \"rerun\": null}"
  AGAIN=", \"validation_ranges\": {\"task\": $TWO, \"rerun\": $RERUN}"
}

contract() { # $1 start stage, $2 extra JSON members (leading comma)
  printf '{"task_id": "001", "task_dir": "/p/Tasks/ACTIVE/001-x", "plugin_root": "/core", "lang": "en", "agents": %s, "start_stage": "%s", "stage_scope": "forward"%s}' "$AGENTS" "$1" "$2"
}

prompt_js() { printf '(o.calls.find((c) => c.label === "%s") || {}).prompt || ""' "$1"; }

@test "Validation reads the task's ranges and builds the regression set" {
  for p in $RANGED; do
    rp "$p" "$(contract Validation "$FIRST")" '{}' "$(prompt_js validation)"
    v="${V[0]}"
    for f in "The task's commits, per repository: .: a1..HEAD (3 commits); Packages/Core: b2..HEAD (1 commit)." \
             "the project root's own diff never shows another repository" \
             "the spine-toolkit:phase-verification skill, its ## Validation's regression section" \
             'Run every other module of the set.' '## Regression set' \
             '"/core/scripts/task-ranges.sh" tips /p/Tasks/ACTIVE/001-x --kind validated' \
             '"/core/scripts/lint-validation-scope.sh" /p/Tasks/ACTIVE/001-x'; do
      grep -qF -- "$f" <<<"$v" || { echo "profile-$p: validation prompt lost: $f"; return 1; }
    done
    if grep -qF 'The last green Validation stood at' <<<"$v"; then echo "profile-$p: a first Validation is told of a green one"; return 1; fi
  done
}

@test "after a green Validation only what its commits reach re-runs" {
  for p in $RANGED; do
    rp "$p" "$(contract Validation "$AGAIN")" '{}' "$(prompt_js validation)"
    v="${V[0]}"
    for f in 'The last green Validation stood at: .: c3..HEAD (2 commits); Packages/Core: d4..HEAD (0 commits).' \
             'Re-run only the modules these commits reach, the uncommitted edits of every root included' 'carried' \
             'drive the app again only when these commits reach the UI layer or the path the scenario walks'; do
      grep -qF -- "$f" <<<"$v" || { echo "profile-$p: re-run prompt lost: $f"; return 1; }
    done
    if grep -qF 'Run every module of the set.' <<<"$v"; then echo "profile-$p: a re-run is told to run the whole set"; return 1; fi
  done
}

@test "without validation_ranges the validator takes the ranges itself" {
  for p in $RANGED; do
    rp "$p" "$(contract Validation '')" '{}' "$(prompt_js validation)"
    f='run "/core/scripts/task-ranges.sh" ranges /p/Tasks/ACTIVE/001-x --since base yourself'
    grep -qF -- "$f" <<<"${V[0]}" || { echo "profile-$p: validation prompt lost: $f"; return 1; }
    if grep -qF 'The task'"'"'s commits, per repository' <<<"${V[0]}"; then echo "profile-$p: ranges invented"; return 1; fi
  done
}

@test "a fix-review round validates from the last green Validation" {
  for p in $RANGED; do
    case "$p" in bug) code=Fix ;; feature) code=Execute ;; refactor) code=Refactor ;; test) code=Write ;; quick) code=Edit ;; esac
    l="$(tr '[:upper:]' '[:lower:]' <<<"$code")"
    rp "$p" "$(contract "$code" ", \"action\": \"fix-review\", \"fix_findings\": [\"x\"]$AGAIN")" \
      "{\"$l:R1\": {\"ok\": true, \"phase_id\": \"R1\", \"committed\": true, \"summary\": \"s\"}}" "$(prompt_js validation)"
    v="${V[0]}"
    [ -n "$v" ] || { echo "profile-$p: Validation did not run"; return 1; }
    grep -qF 'The last green Validation stood at:' <<<"$v" || { echo "profile-$p: no re-run point"; return 1; }
    grep -qF 'c3..HEAD' <<<"$v" || { echo "profile-$p: lost the range"; return 1; }
    if grep -qF ' (1 commit)' <<<"$v"; then echo "profile-$p: a count that predates the fix commits"; return 1; fi
  done
}

@test "a catch-up says so, and the re-run covers the delta" {
  for p in $RANGED; do
    rp "$p" "$(contract Validation ", \"action\": \"catch-up\"$AGAIN")" '{}' "$(prompt_js validation)"
    grep -qF "This run catches up commits that landed after the task's Done" <<<"${V[0]}" || { echo "profile-$p: not told it catches up"; return 1; }
    grep -qF 'Packages/Core: d4..HEAD (0 commits)' <<<"${V[0]}" || { echo "profile-$p: the delta range is gone"; return 1; }
    if grep -qF 'Run every module of the set.' <<<"${V[0]}"; then echo "profile-$p: a catch-up is told to run the whole set"; return 1; fi
  done
}

@test "no Validation brief asks for a full test run" {
  line_feature='For FEATURE a build and a test run of the regression set are both mandatory'
  line_bug='For BUG a build and a test run of the regression set are both mandatory'
  line_quick='For QUICK a build and a test run of the regression set are both mandatory'
  line_refactor='For REFACTOR a test run of the regression set is mandatory as a regression check'
  line_test='For TEST a test run of the regression set is mandatory'
  for p in $RANGED; do
    rp "$p" "$(contract Validation '')" '{}' "$(prompt_js validation)"
    if grep -qF 'full test run' <<<"${V[0]}"; then echo "profile-$p: the Validation prompt asks for a full test run"; return 1; fi
    line="line_$p"
    grep -qF -- "${!line}" <<<"${V[0]}" || { echo "profile-$p: lost: ${!line}"; return 1; }
  done
  grep -qF "'build and the regression set'" "$ROOT/workflows/profile-quick.js" || { echo "the QUICK meta detail still says full"; return 1; }
}

@test "Review reads Validation's record before it re-runs anything" {
  for p in $RANGED; do
    rp "$p" "$(contract Review ", \"review_ranges\": $TWO")" '{}' "$(prompt_js review)"
    for f in 'run "/core/scripts/lint-validation-scope.sh" /p/Tasks/ACTIVE/001-x' 'run no suite yourself' \
             'a module of the set Validation did not run' 'blocking_findings, even when your re-run is green' 'outside the set'; do
      grep -qF -- "$f" <<<"${V[0]}" || { echo "profile-$p: review prompt lost: $f"; return 1; }
    done
  done
}

@test "the profiles without Validation carry none of it" {
  for p in research review epic; do
    if grep -qE 'VALIDATION_SCOPE|REVIEW_VALIDATION' <<<"$(sed -n '/── end prelude/,$p' "$ROOT/workflows/profile-$p.js")"; then
      echo "profile-$p.js uses a Validation helper"; return 1
    fi
  done
}

@test "a repository with no known base is counted as changed, never skipped" {
  blind='{"since": "base", "repos": {".": {"range": "a1..HEAD", "commits": 3, "state": "ok"}, "Packages/Core": {"range": null, "commits": null, "state": "unknown"}}}'
  member=", \"validation_ranges\": {\"task\": $blind, \"rerun\": null}"
  for p in $RANGED; do
    rp "$p" "$(contract Validation "$member")" '{}' "$(prompt_js validation)"
    grep -qF 'Packages/Core: no known base — count that repository as changed and say so under ## Scope' <<<"${V[0]}" || { echo "profile-$p: no clause for the unknown repository"; return 1; }
  done
}

@test "a re-run says where the last green Validation's counts are" {
  for p in $RANGED; do
    rp "$p" "$(contract Validation "$AGAIN")" '{}' "$(prompt_js validation)"
    grep -qF '/p/Tasks/ACTIVE/001-x/Validation.md holds — read it before you overwrite it' <<<"${V[0]}" || { echo "profile-$p: no pointer to the last Validation.md"; return 1; }
    rp "$p" "$(contract Validation "$AGAIN, \"archive_paths\": [\"/p/Tasks/ACTIVE/001-x/_archive/Validation-2026-11-19T100000.md\"]")" '{}' "$(prompt_js validation)"
    grep -qF '_archive/Validation-2026-11-19T100000.md holds' <<<"${V[0]}" || { echo "profile-$p: the archived Validation is not named"; return 1; }
  done
}

@test "a BUG re-run carries the replay when its commits miss the scenario's path" {
  rp bug "$(contract Validation "$AGAIN")" '{}' "$(prompt_js validation)"
  for f in 'the replay is carried' 'return reproduction_status as it was in the last green Validation' '(fixed only if that Validation replayed, otherwise deferred-manual)' 'name that Validation with its HEAD under ## Scope'; do
    grep -qF -- "$f" <<<"${V[0]}" || { echo "the re-run BUG prompt lost: $f"; return 1; }
  done
  for c in "$FIRST" ''; do
    rp bug "$(contract Validation "$c")" '{}' "$(prompt_js validation)"
    if grep -qF 'the replay is carried' <<<"${V[0]}"; then echo "a first BUG Validation may carry its replay"; return 1; fi
  done
}

@test "a carried replay passes on the statement of the Validation it is carried from" {
  stmt='or, on a re-run that carries the replay, the statement of the Validation it is carried from, named under ## Scope'
  keep="a carried deferred-manual keeps that Validation's replay case in"
  rp bug "$(contract Validation "$AGAIN")" '{}' "$(prompt_js validation)"
  for f in "$stmt" "$keep" 'and writes no new one'; do
    grep -qF -- "$f" <<<"${V[0]}" || { echo "the re-run BUG prompt lost: $f"; return 1; }
  done
  for c in "$FIRST" ''; do
    rp bug "$(contract Validation "$c")" '{}' "$(prompt_js validation)"
    for f in "$stmt" "$keep"; do
      if grep -qF -- "$f" <<<"${V[0]}"; then echo "a first BUG Validation is told: $f"; return 1; fi
    done
  done
}

@test "Validation classifies failures against the registry from the contract" {
  for p in $RANGED; do
    rp "$p" "$(contract Validation ', "known_failures": "/p/Tasks/KnownFailures.md"')" '{}' "$(prompt_js validation)"
    for f in "The project's known failures registry is /p/Tasks/KnownFailures.md; a missing file is an empty registry." \
             'Failures outside the task' '## Outside the task'; do
      grep -qF -- "$f" <<<"${V[0]}" || { echo "profile-$p: validation prompt lost: $f"; return 1; }
    done
    rp "$p" "$(contract Validation '')" '{}' "$(prompt_js validation)"
    grep -qF 'The project keeps no known failures registry.' <<<"${V[0]}" || { echo "profile-$p: no word that there is no registry"; return 1; }
    if grep -qF 'known failures registry is' <<<"${V[0]}"; then echo "profile-$p: a registry invented"; return 1; fi
  done
}

@test "Validation carries green whole-module runs from phases and earlier Validations" {
  for c in "$FIRST" "$AGAIN" ''; do
    for p in $RANGED; do
      rp "$p" "$(contract Validation "$c")" '{}' "$(prompt_js validation)"
      for f in 'a ran: line under a phase checkbox in /p/Tasks/ACTIVE/001-x/Plan.md' 'carried <sha> (phase <N>)' 'carried <sha> (validation)' \
               'A module that failed in an earlier Validation runs again.'; do
        grep -qF -- "$f" <<<"${V[0]}" || { echo "profile-$p: validation prompt lost: $f"; return 1; }
      done
    done
  done
}

@test "Validation records where it stood on PASSED_WITH_FLAKES too" {
  for p in $RANGED; do
    rp "$p" "$(contract Validation "$FIRST")" '{}' "$(prompt_js validation)"
    grep -qF 'On PASSED or PASSED_WITH_FLAKES, run' <<<"${V[0]}" || { echo "profile-$p: PASSED_WITH_FLAKES writes no record"; return 1; }
    if grep -qF 'On PASSED, run' <<<"${V[0]}"; then echo "profile-$p: only PASSED writes the record"; return 1; fi
  done
  grep -qF 'every Validation that ends PASSED or PASSED_WITH_FLAKES' "$ROOT/conventions/task-ranges.md" || { echo "task-ranges.md: the Records row"; return 1; }
}

@test "Review confirms reach lines and the failures outside the task" {
  for p in $RANGED; do
    rp "$p" "$(contract Review ", \"review_ranges\": $TWO")" '{}' "$(prompt_js review)"
    for f in 'Lines of class reach are not findings' '## Outside the task' 'blocking_findings' 'When it prints no finding, run no suite yourself'; do
      grep -qF -- "$f" <<<"${V[0]}" || { echo "profile-$p: review prompt lost: $f"; return 1; }
    done
  done
}
