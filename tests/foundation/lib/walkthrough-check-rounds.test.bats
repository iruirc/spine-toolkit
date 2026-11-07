#!/usr/bin/env bats
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

contract() {
  printf '{"task_id": "001", "task_dir": "/p/Tasks/ACTIVE/001-x", "plugin_root": "/core", "lang": "en", "agents": %s, "start_stage": "Review", "stage_scope": "forward", "review_ranges": %s, "walkthrough": "deep", "walkthrough_check": "on"}' "$AGENTS" "$TWO"
}

run_profile() { node "$ROOT/tests/foundation/helpers/run-profile.js" "$ROOT/workflows/profile-$1.js" "$(contract)" "$2"; }

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
    grep -qF 'when that first read named more than three places, once more from a second fresh read, never a third' "$S" \
      || { echo "$s: the second round is not stated"; return 1; }
    ! grep -qF 'the writer revises once from what that reader could not follow' "$S" || { echo "$s: still one round"; return 1; }
  done
  C="$ROOT/docs/configuration.md"
  ck="$(awk '/^### \[WALKTHROUGH_CHECK\]$/{f=1;next} /^### /{f=0} f' "$C")"
  grep -qF 'when the first read named more than three places' <<<"$ck" || { echo "configuration.md: the second round is not stated"; return 1; }
  ! grep -qF 'One round,' <<<"$ck" || { echo "configuration.md: still one round"; return 1; }
}
