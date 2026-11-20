#!/usr/bin/env bats
# changed: sweep skills workflows
# The walkthrough check reads, revises, and reads once more only when the first read found more than
# three places — never a third round. Driven through the scripts with stubbed agents, so a loop that
# drifts from task-walkthrough's ## Check fails here. The shared writer block is pinned byte-equal
# across all eight scripts, so a hand edit to one copy goes red.

setup() {
  ROOT="$(cd -- "$(dirname -- "$BATS_TEST_FILENAME")/../../.." && pwd)"
  WRITERS="bug feature refactor test quick"
  AGENTS='{"architect":"a","developer":"d","tester":"t","reviewer":"r","refactorer":"f","validator":"v","security":"—","diagnostics":"g","init":"—"}'
  TWO='{"since": "base", "repos": {".": {"range": "a1..HEAD", "commits": 3, "state": "ok"}}}'
  BASE='"review": {"review_status": "APPROVED", "artifact_path": "r", "summary": "s"}, "walkthrough": {"ok": true, "artifact_path": "w", "summary": "s", "changed": true}, "walkthrough:revise": {"ok": true, "artifact_path": "w", "summary": "s", "changed": true}'
}

# The shared block of one script: from WALKTHROUGH_ARTIFACT to the brace that closes writeWalkthrough.
block() {
  awk '/^const WALKTHROUGH_ARTIFACT = \{$/ { f = 1 } f { print } f && /^  return w$/ { getline; print; exit }' "$1"
}

# The check value is $1, `on` unless a test says otherwise.
# $1 is the value of the check, `on` unless a test names another.
contract() {
  printf '{"task_id": "001", "task_dir": "/p/Tasks/ACTIVE/001-x", "plugin_root": "/core", "lang": "en", "agents": %s, "start_stage": "Review", "stage_scope": "forward", "review_ranges": %s, "walkthrough": "deep", "walkthrough_check": "%s"}' "$AGENTS" "$TWO" "${1:-on}"
}

# $3 is the value of the check, `on` unless a test names another.
run_profile() { node "$ROOT/tests/foundation/helpers/run-profile.js" "$ROOT/workflows/profile-$1.js" "$(contract "${3:-on}")" "$2"; }

pick() { node -e 'const o = JSON.parse(require("fs").readFileSync(0, "utf8")); const v = eval(process.argv[1]); console.log(typeof v === "string" ? v : JSON.stringify(v))' "$1"; }

# A check reply with $1 unclear places.
read_with() {
  node -e 'const n = +process.argv[1]; console.log(JSON.stringify({ retelling: ["r"], unclear: Array.from({ length: n }, (_, i) => ({ quote: "q" + i, missing: "m" + i })) }))' "$1"
}

order() { pick "o.calls.map((c) => c.label).filter((l) => l.startsWith('walkthrough')).join(' ')"; }

@test "the shared writer block is byte-identical in all eight scripts" {
  ref="$(block "$ROOT/workflows/profile-feature.js")"
  [ "$(wc -l <<<"$ref")" -gt 100 ] || { echo "the block was not found in profile-feature.js"; return 1; }
  n=0
  for p in feature bug refactor test quick epic review research; do
    n=$((n + 1))
    [ "$(block "$ROOT/workflows/profile-$p.js")" = "$ref" ] \
      || { echo "profile-$p.js: the shared block drifted"; diff <(block "$ROOT/workflows/profile-$p.js") <(printf '%s\n' "$ref") | head -20; return 1; }
  done
  [ "$n" -eq 8 ]
}

@test "nothing unclear ends the check without a revision" {
  for p in $WRITERS; do
    out="$(run_profile "$p" "{$BASE, \"walkthrough:check\": $(read_with 0)}")"
    [ "$(order <<<"$out")" = 'walkthrough walkthrough:check' ] || { echo "profile-$p: dispatched $(order <<<"$out")"; return 1; }
  done
}

@test "exactly three unclear places get one revision and no second read" {
  for p in $WRITERS; do
    out="$(run_profile "$p" "{$BASE, \"walkthrough:check\": $(read_with 3)}")"
    [ "$(order <<<"$out")" = 'walkthrough walkthrough:check walkthrough:revise' ] || { echo "profile-$p: dispatched $(order <<<"$out")"; return 1; }
  done
}

@test "four unclear places get a second read and a second revision" {
  for p in $WRITERS; do
    out="$(run_profile "$p" "{$BASE, \"walkthrough:check\": $(read_with 4)}")"
    [ "$(order <<<"$out")" = 'walkthrough walkthrough:check walkthrough:revise walkthrough:check walkthrough:revise' ] \
      || { echo "profile-$p: dispatched $(order <<<"$out")"; return 1; }
    notes="$(pick 'o.result.notes' <<<"$out")"
    grep -qF 'Walkthrough.md check: 4 unclear place(s), revised.' <<<"$notes" || { echo "profile-$p: no note for the first round: $notes"; return 1; }
    grep -qF 'Walkthrough.md second check: 4 unclear place(s), revised.' <<<"$notes" || { echo "profile-$p: no note for the second round: $notes"; return 1; }
  done
}

@test "a second read that lists more still ends after the second revision" {
  for p in $WRITERS; do
    out="$(run_profile "$p" "{$BASE, \"walkthrough:check#1\": $(read_with 4), \"walkthrough:check\": $(read_with 5)}")"
    [ "$(order <<<"$out")" = 'walkthrough walkthrough:check walkthrough:revise walkthrough:check walkthrough:revise' ] \
      || { echo "profile-$p: dispatched $(order <<<"$out")"; return 1; }
    grep -qF 'Walkthrough.md second check: 5 unclear place(s), revised.' <<<"$(pick 'o.result.notes' <<<"$out")" \
      || { echo "profile-$p: the second round is not noted"; return 1; }
  done
}

@test "a second read that finds nothing ends the check without a second revision" {
  for p in $WRITERS; do
    out="$(run_profile "$p" "{$BASE, \"walkthrough:check#1\": $(read_with 4), \"walkthrough:check#2\": $(read_with 0)}")"
    [ "$(order <<<"$out")" = 'walkthrough walkthrough:check walkthrough:revise walkthrough:check' ] \
      || { echo "profile-$p: dispatched $(order <<<"$out")"; return 1; }
  done
}

@test "a first revision that changed nothing is not read again" {
  for p in $WRITERS; do
    out="$(run_profile "$p" "{$BASE, \"walkthrough:check\": $(read_with 4), \"walkthrough:revise\": {\"ok\": true, \"artifact_path\": \"w\", \"summary\": \"s\", \"changed\": false}}")"
    [ "$(order <<<"$out")" = 'walkthrough walkthrough:check walkthrough:revise' ] || { echo "profile-$p: dispatched $(order <<<"$out")"; return 1; }
  done
}

@test "a first revision that returned nothing is not read again" {
  for p in $WRITERS; do
    out="$(run_profile "$p" "{$BASE, \"walkthrough:check\": $(read_with 4), \"walkthrough:revise\": null}")"
    [ "$(order <<<"$out")" = 'walkthrough walkthrough:check walkthrough:revise' ] || { echo "profile-$p: dispatched $(order <<<"$out")"; return 1; }
  done
}

@test "once: twelve unclear places get one revision and no second read" {
  for p in $WRITERS; do
    out="$(run_profile "$p" "{$BASE, \"walkthrough:check\": $(read_with 12)}" once)"
    [ "$(order <<<"$out")" = 'walkthrough walkthrough:check walkthrough:revise' ] || { echo "profile-$p: dispatched $(order <<<"$out")"; return 1; }
    ! grep -qF 'second check' <<<"$(pick 'o.result.notes' <<<"$out")" || { echo "profile-$p: a second round is noted"; return 1; }
  done
}

@test "once with nothing unclear ends after the read" {
  for p in $WRITERS; do
    out="$(run_profile "$p" "{$BASE, \"walkthrough:check\": $(read_with 0)}" once)"
    [ "$(order <<<"$out")" = 'walkthrough walkthrough:check' ] || { echo "profile-$p: dispatched $(order <<<"$out")"; return 1; }
  done
}

@test "off dispatches no check at all" {
  for p in $WRITERS; do
    out="$(run_profile "$p" "{$BASE, \"walkthrough:check\": $(read_with 12)}" off)"
    [ "$(order <<<"$out")" = 'walkthrough' ] || { echo "profile-$p: dispatched $(order <<<"$out")"; return 1; }
  done
}

@test "the skill says a first revision that changed nothing or returned nothing ends the check" {
  S="$ROOT/skills/task-walkthrough/SKILL.md"
  ck="$(awk '/^## Check$/{f=1;next} f&&/^## /{exit} f' "$S" | tr '\n' ' ')"
  grep -qF 'When the first revision changed nothing or returned nothing, there is no second read' <<<"$ck" \
    || { echo "## Check does not say an idle first revision ends the check"; return 1; }
}

@test "the check prompt names the four classes of unclear" {
  out="$(run_profile quick "{$BASE, \"walkthrough:check\": $(read_with 0)}")"
  c="$(pick "o.calls.find((c) => c.label === 'walkthrough:check').prompt" <<<"$out")"
  for token in 'a sentence you had to read twice' 'a term used without a definition' \
               'an identifier as the subject of a sentence' 'a commit without its reason or its verification'; do
    grep -qF "$token" <<<"$c" || { echo "the check prompt does not name: $token"; return 1; }
  done
}

@test "the skills and the configuration reference describe two bounded rounds, not one" {
  for s in workflow-bug workflow-feature workflow-epic workflow-refactor workflow-test orchestrator; do
    S="$ROOT/skills/$s/SKILL.md"
    grep -qF 'that first read named more than three places, once more from a second fresh read, never a third' "$S" \
      || { echo "$s: the second round is not stated"; return 1; }
    ! grep -qF 'the writer revises once from what that reader could not follow' "$S" || { echo "$s: still one round"; return 1; }
  done
  C="$ROOT/docs/configuration.md"
  ck="$(awk '/^### \[WALKTHROUGH_CHECK\]$/{f=1;next} /^### /{f=0} f' "$C")"
  grep -qF 'when the first read named more than three places' <<<"$ck" || { echo "configuration.md: the second round is not stated"; return 1; }
  ! grep -qF 'One round,' <<<"$ck" || { echo "configuration.md: still one round"; return 1; }
  grep -qF 'at `on`' <<<"$ck" || { echo "configuration.md: the second round is not tied to on"; return 1; }
  grep -qF '`once`' <<<"$ck" || { echo "configuration.md: once is not named"; return 1; }
  ck="$(awk '/^## Check$/{f=1;next} f&&/^## /{exit} f' "$ROOT/skills/task-walkthrough/SKILL.md" | tr '\n' ' ')"
  grep -qF '**At `on`, at most two rounds.**' <<<"$ck" || { echo "task-walkthrough: the second round is not tied to on"; return 1; }
  grep -qF '**At `once`, one read and one revision.**' <<<"$ck" || { echo "task-walkthrough: once is not described"; return 1; }
  for s in workflow-bug workflow-feature workflow-epic workflow-refactor workflow-test orchestrator; do
    grep -qF 'when `walkthrough_check` is `on`' "$ROOT/skills/$s/SKILL.md" || { echo "$s: the second round is not tied to on"; return 1; }
    grep -qF '`once`' "$ROOT/skills/$s/SKILL.md" || { echo "$s: once is not named"; return 1; }
  done
}

# A run from the implementing stage to Done; $2 is extra contract members, with a leading comma, and
# $3 whether Done committed outside the Tasks folder, false unless a test says otherwise.
from_stage() {
  local code
  case "$1" in bug) code=Fix ;; feature) code=Execute ;; refactor) code=Refactor ;; test) code=Write ;; quick) code=Edit ;; esac
  local c rest
  c="$(printf '{"task_id": "001", "task_dir": "/p/Tasks/ACTIVE/001-x", "plugin_root": "/core", "lang": "en", "agents": %s, "start_stage": "%s", "stage_scope": "forward", "review_ranges": %s, "walkthrough": "deep"%s}' "$AGENTS" "$code" "$TWO" "$2")"
  rest='"edit": {"ok": true, "artifact_path": "e", "summary": "s", "committed": true}, "review": {"review_status": "APPROVED", "artifact_path": "r", "summary": "s"}, "validation": {"validation_status": "PASSED", "reproduction_status": "fixed", "artifact_path": "v", "summary": "s", "driver_status": "ok"}, "done": {"ok": true, "artifact_path": "d", "summary": "s", "closed_findings": [], "committed_outside_tasks": '"${3:-false}"'}'
  node "$ROOT/tests/foundation/helpers/run-profile.js" "$ROOT/workflows/profile-$1.js" "$c" "{$rest}"
}

# The dispatches that write Walkthrough.md, with review and done around them.
landmarks() { pick "o.calls.map((c) => c.label).filter((l) => ['walkthrough', 'review', 'done'].includes(l)).join(' ')"; }

@test "by default the implementing stage leaves Walkthrough.md to Done, which writes it once" {
  for p in $WRITERS; do
    out="$(from_stage "$p" '')"
    [ "$(landmarks <<<"$out")" = 'review done walkthrough' ] || { echo "profile-$p: dispatched $(landmarks <<<"$out")"; return 1; }
    grep -qF 'Walkthrough.md is written at Done ([WALKTHROUGH_WHEN] = done).' <<<"$(pick 'o.result.notes' <<<"$out")" \
      || { echo "profile-$p: the deferral is not noted"; return 1; }
  done
}

@test "walkthrough_when stage writes the file at the implementing stage and again at Done" {
  for p in $WRITERS; do
    out="$(from_stage "$p" ', "walkthrough_when": "stage"' true)"
    [ "$(landmarks <<<"$out")" = 'walkthrough review done walkthrough' ] || { echo "profile-$p: dispatched $(landmarks <<<"$out")"; return 1; }
    ! grep -qF 'is written at Done' <<<"$(pick 'o.result.notes' <<<"$out")" || { echo "profile-$p: a deferral is noted"; return 1; }
  done
}

@test "a file current before the run is still written at Done when the implementing stage was skipped" {
  # The implementing stage commits after the orchestrator measured the file; Done must not trust that measure.
  for p in $WRITERS; do
    out="$(from_stage "$p" ', "walkthrough_current": true')"
    [ "$(landmarks <<<"$out")" = 'review done walkthrough' ] || { echo "profile-$p: dispatched $(landmarks <<<"$out")"; return 1; }
  done
}

@test "a run from Review over a stale file writes it once, at Done" {
  for p in $WRITERS; do
    out="$(run_profile "$p" '{"review": {"review_status": "APPROVED", "artifact_path": "r", "summary": "s"}, "done": {"ok": true, "artifact_path": "d", "summary": "s", "closed_findings": [], "committed_outside_tasks": false}}' off)"
    [ "$(landmarks <<<"$out")" = 'review done walkthrough' ] || { echo "profile-$p: dispatched $(landmarks <<<"$out")"; return 1; }
  done
}

@test "the skills say when the file is written: at Done by default, at the stage only under stage" {
  S="$ROOT/skills/task-walkthrough/SKILL.md"
  for sec in 'When to use' 'The switch' 'EPIC'; do
    body="$(awk -v h="## $sec" '$0 == h {f=1;next} f&&/^## /{exit} f' "$S")"
    grep -qF '[WALKTHROUGH_WHEN]' <<<"$body" || { echo "task-walkthrough ## $sec does not name [WALKTHROUGH_WHEN]"; return 1; }
  done
  for p in $WRITERS; do
    S="$ROOT/skills/workflow-$p/SKILL.md"
    grep -qF 'when the contract'"'"'s `walkthrough_when` is `stage`' "$S" || { echo "workflow-$p: the stage writes regardless of walkthrough_when"; return 1; }
    grep -qF 'At `walkthrough_when` = `done`, the default, this is the first write, over the task'"'"'s whole range.' "$S" \
      || { echo "workflow-$p: Done is not said to write the whole range"; return 1; }
  done
}
