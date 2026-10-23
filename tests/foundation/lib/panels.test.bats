#!/usr/bin/env bats
# A panel stage's order is its profile's, and Method B states the order Method A already runs
# (workflows/profile-bug.js, profile-test.js): BUG's lenses in parallel, then an architect
# synthesis; TEST's architect lens, then the tester (spec: multi-llm milestone 6).

setup() {
  ROOT="$(cd -- "$(dirname -- "$BATS_TEST_FILENAME")/../../.." && pwd)"
  BUG="$ROOT/skills/workflow-bug/SKILL.md"
  TEST="$ROOT/skills/workflow-test/SKILL.md"
}

@test "no panel leaves its order to the orchestrator" {
  for f in skills/workflow-bug/SKILL.md skills/workflow-test/SKILL.md conventions/stage-dispatch.md docs/building-a-platform.md; do
    ! grep -qE "as the orchestrator decides|that choice is the orchestrator|in parallel or in sequence is the" "$ROOT/$f" || { echo "$f"; false; }
  done
}

@test "BUG Diagnose: lenses in parallel, write no file, an architect synthesis writes Research.md" {
  d="$(grep -m1 '^- \*\*Diagnose\*\*' "$BUG")"
  grep -qF 'in parallel' <<<"$d" || { echo "not parallel"; return 1; }
  grep -qF 'writes no file' <<<"$d" || { echo "lenses write"; return 1; }
  grep -qF 'a separate `[architect]` agent' <<<"$d" || { echo "no synthesis agent"; return 1; }
  grep -qF 'names every disagreement' <<<"$d" || { echo "disagreements"; return 1; }
}

@test "BUG Diagnose: an empty lens and an absent security lens" {
  d="$(grep -m1 '^- \*\*Diagnose\*\*' "$BUG")"
  grep -qF 'lenses returning nothing: the synthesis works from the other' <<<"$d" || { echo "one empty"; return 1; }
  grep -qF 'records the verdict line that stands in for them' <<<"$d" || { echo "absent lens"; return 1; }
}

@test "BUG lite still folds Diagnose into Reproduce" {
  sed -n '/^At `lite`:/,/^Unchanged at `lite`/p' "$BUG" | grep -qF 'Diagnose'
}

@test "TEST Analyze: the architect lens first, then the tester writes Research.md" {
  a="$(grep -m1 '^- \*\*Analyze\*\*' "$TEST")"
  grep -qF 'in sequence' <<<"$a" || { echo "not in sequence"; return 1; }
  grep -qE '`\[architect\]`.*testability.*then `\[tester\]` writes `Research.md`' <<<"$a"
}

@test "stage-dispatch: the profile sets a panel's order" {
  grep -qF "a panel's order is its profile's" "$ROOT/conventions/stage-dispatch.md"
}

# Final review: Method A errors only when both the diagnostics and the architect lens are empty;
# an empty security lens becomes its verdict line, like one that did not run.
@test "BUG Diagnose: emptiness counts the diagnostics and architect lenses, security has its verdict line" {
  d="$(grep -m1 '^- \*\*Diagnose\*\*' "$BUG")"
  grep -qF 'both the `[diagnostics]` and the `[architect]` lens returning nothing' <<<"$d" || { echo "both empty"; return 1; }
  grep -qF 'did not run or returned nothing' <<<"$d" || { echo "security empty"; return 1; }
}
