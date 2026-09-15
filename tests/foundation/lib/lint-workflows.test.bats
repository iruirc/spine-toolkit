#!/usr/bin/env bats
# lint-workflows.sh holds the dispatch rules nobody catches by reading: every agent() call carries
# one tuning() beside its agentType, on the role that agentType reads, of the kind
# conventions/stage-dispatch.md → Model and effort gives its label. Each test breaks one rule in a
# copy of the tree and expects that rule's message.

setup() {
  ROOT="$(cd -- "$(dirname -- "$BATS_TEST_FILENAME")/../../.." && pwd)"
  T="$BATS_TEST_TMPDIR/tree"
  mkdir -p "$T/scripts"
  cp "$ROOT/scripts/lint-workflows.sh" "$T/scripts/"
  cp -R "$ROOT/workflows" "$ROOT/skills" "$T/"
}

# Replaces one exact string in one script and fails when it is not there exactly once, so no test
# passes by mutating nothing.
mutate() { # $1 = script under workflows/, $2 = old, $3 = new
  python3 - "$T/workflows/$1" "$2" "$3" <<'PY'
import sys
path, old, new = sys.argv[1:4]
src = open(path, encoding='utf-8').read()
if src.count(old) != 1:
    sys.exit('expected exactly one %r in %s, found %d' % (old, path, src.count(old)))
open(path, 'w', encoding='utf-8').write(src.replace(old, new))
PY
}

expect_violation() { # $1 = substring of the message
  run "$T/scripts/lint-workflows.sh"
  [ "$status" -eq 1 ] || { echo "lint passed: $output"; return 1; }
  case "$output" in *"$1"*) ;; *) echo "no '$1' in: $output"; return 1 ;; esac
}

REVIEW_LINE="{ label: 'review', phase: 'Review', agentType: A.agents.reviewer, schema: REVIEW, ...tuning('reviewer', 'stage') },"

@test "the unmodified tree passes" {
  run "$T/scripts/lint-workflows.sh"
  [ "$status" -eq 0 ] || { echo "$output"; return 1; }
}

@test "a dispatch with no tuning fails" {
  mutate profile-review.js "$REVIEW_LINE" "{ label: 'review', phase: 'Review', agentType: A.agents.reviewer, schema: REVIEW },"
  expect_violation "dispatch 'review' carries 0 tuning() call(s)"
}

@test "a literal model in a dispatch's options fails" {
  mutate profile-review.js "$REVIEW_LINE" "{ label: 'review', phase: 'Review', agentType: A.agents.reviewer, schema: REVIEW, ...tuning('reviewer', 'stage'), model: 'opus' },"
  expect_violation 'literal `model:`'
}

@test "a tuning role other than the one agentType reads fails" {
  mutate profile-review.js "$REVIEW_LINE" "{ label: 'review', phase: 'Review', agentType: A.agents.reviewer, schema: REVIEW, ...tuning('architect', 'stage') },"
  expect_violation "dispatch 'review' reads role reviewer in agentType but tunes for 'architect'"
}

@test "a stage dispatch tuned mechanical fails" {
  mutate profile-review.js "$REVIEW_LINE" "{ label: 'review', phase: 'Review', agentType: A.agents.reviewer, schema: REVIEW, ...tuning('reviewer', 'mechanical') },"
  expect_violation "dispatch 'review' is tuned mechanical; conventions/stage-dispatch.md → Model and effort makes it stage"
}

@test "a mechanical dispatch tuned light fails" {
  mutate profile-review.js "agentType: A.agents.reviewer, ...tuning('reviewer', 'mechanical')," "agentType: A.agents.reviewer, ...tuning('reviewer', 'light'),"
  expect_violation "dispatch 'auto-move' is tuned light; conventions/stage-dispatch.md → Model and effort makes it mechanical"
}

@test "a variable role the lint does not list fails" {
  mutate profile-bug.js "...tuning(l.role, 'stage')" "...tuning(l.name, 'stage')"
  expect_violation "pairs agentType l.agentType with tuning role l.name, a variable form lint-workflows.sh does not list"
}

@test "a role named in the runPhases map is a dispatch the stage has to gate" {
  mutate profile-bug.js "need('Fix', 'developer', 'tester')" "need('Fix', 'developer')"
  expect_violation 'role "tester" dispatched in stage "Fix" is not gated'
}

@test "a dispatch violation reports the line in the file, not in the comment-stripped copy" {
  mutate profile-review.js "$REVIEW_LINE" "{ label: 'review', phase: 'Review', agentType: A.agents.reviewer, schema: REVIEW },"
  n="$(grep -n "label: 'review', phase: 'Review'" "$T/workflows/profile-review.js" | cut -d: -f1)"
  expect_violation "workflows/profile-review.js:$n: dispatch 'review'"
}
