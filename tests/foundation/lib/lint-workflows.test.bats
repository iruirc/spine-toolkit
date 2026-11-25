#!/usr/bin/env bats
# changed: sweep skills workflows
# lint-workflows.sh holds the dispatch rules nobody catches by reading: every agent() call carries
# one tuning() beside its agentType, on the role that agentType reads, of the kind
# conventions/stage-dispatch.md → Model and effort gives its label. Each test breaks one rule in a
# copy of the tree and expects that rule's message.

setup() {
  ROOT="$(cd -- "$(dirname -- "$BATS_TEST_FILENAME")/../../.." && pwd)"
  T="$BATS_TEST_TMPDIR/tree"
  mkdir -p "$T/scripts"
  cp "$ROOT/scripts/lint-workflows.sh" "$T/scripts/"
  cp -R "$ROOT/workflows" "$ROOT/workflow-src" "$ROOT/skills" "$T/"
}

# Replaces one exact string in one script and fails when it is not there exactly once, so no test
# passes by mutating nothing.
mutate() { # $1 = script under workflows/, $2 = old, $3 = new
  mutate_at "workflows/$1" "$2" "$3"
}

mutate_at() { # $1 = path under the tree, $2 = old, $3 = new
  python3 - "$T/$1" "$2" "$3" <<'PY'
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
  case "$output" in *"every schema under 4096 characters"*) ;; *) echo "$output"; return 1 ;; esac
  case "$output" in *warning:*) echo "$output"; return 1 ;; esac
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

@test "the security triage tuned as a stage fails" {
  mutate profile-review.js "schema: TRIAGE, ...tuning(role, 'light') }" "schema: TRIAGE, ...tuning(role, 'stage') }"
  expect_violation "dispatch 'security:triage' is tuned stage; conventions/stage-dispatch.md → Model and effort makes it light"
}

@test "the ManualChecks.md walk tuned as a stage fails" {
  mutate profile-review.js "schema: MANUAL_CHECKS_READ, ...tuning(role, 'light') }" "schema: MANUAL_CHECKS_READ, ...tuning(role, 'stage') }"
  expect_violation "dispatch 'manual-checks:check' is tuned stage; conventions/stage-dispatch.md → Model and effort makes it light"
}

@test "a walk that drifts in one profile fails the prelude check" {
  mutate profile-feature.js "ManualChecks.md check: nothing unclear." "ManualChecks.md check: all clear."
  expect_violation 'workflows/profile-feature.js: prelude differs from workflow-src/prelude.js — run scripts/sync-workflow-prelude.sh'
}

@test "the source drifting from the copies fails every copy" {
  mutate_at workflow-src/prelude.js "ManualChecks.md check: nothing unclear." "ManualChecks.md check: all clear."
  expect_violation 'workflows/profile-bug.js: prelude differs from workflow-src/prelude.js — run scripts/sync-workflow-prelude.sh'
  expect_violation 'workflows/profile-test.js: prelude differs from workflow-src/prelude.js — run scripts/sync-workflow-prelude.sh'
}

@test "a missing source fails" {
  rm "$T/workflow-src/prelude.js"
  expect_violation 'workflow-src/prelude.js: missing — the source every workflows/profile-*.js prelude is generated from'
}

@test "a source without the Task id line fails" {
  python3 - "$T/workflow-src/prelude.js" <<'PY'
import re, sys
p = sys.argv[1]
s = open(p, encoding='utf-8').read()
s, n = re.subn(r'^.*Task id: \$\{[^}]*\} — profile \$\{[^}]*\}, stage \$\{[^}]*\}\..*\n', '', s, flags=re.M)
assert n == 1, n
open(p, 'w', encoding='utf-8').write(s)
PY
  expect_violation 'workflow-src/prelude.js: prelude lost the'
}

@test "the artifact read tuned as a stage fails" {
  mutate profile-quick.js "schema: ARTIFACT_READ, ...tuning(role, 'light') }" "schema: ARTIFACT_READ, ...tuning(role, 'stage') }"
  expect_violation "dispatch 'artifact:check' is tuned stage; conventions/stage-dispatch.md → Model and effort makes it light"
}

@test "an artifact revision tuned by a literal kind fails" {
  mutate profile-quick.js "schema: ARTIFACT_REVISED, ...tuning(role, kind) }" "schema: ARTIFACT_REVISED, ...tuning(role, 'stage') }"
  expect_violation "dispatch 'artifact:revise' is tuned stage; conventions/stage-dispatch.md → Model and effort makes it the writing stage's kind"
}

@test "an artifact revision whose kind no longer follows the writing stage fails" {
  mutate profile-quick.js "const kind = stage === 'Done' ? 'done' : 'stage'" "const kind = 'stage'"
  expect_violation "dispatch 'artifact:revise' takes its kind from"
}

@test "the artifact read tuned by a bare identifier fails" {
  mutate profile-quick.js "schema: ARTIFACT_READ, ...tuning(role, 'light') }" "schema: ARTIFACT_READ, ...tuning(role, stage) }"
  expect_violation "dispatch 'artifact:check' is tuned by the identifier stage; its kind has to be a quoted literal"
}

@test "an ordinary dispatch tuned by a bare identifier fails" {
  mutate profile-quick.js "schema: DONE_ARTIFACT, ...tuning('developer', 'done') }" "schema: DONE_ARTIFACT, ...tuning('developer', stage) }"
  expect_violation "dispatch 'done' is tuned by the identifier stage; its kind has to be a quoted literal"
}

@test "a half-quoted tuning kind fails" {
  mutate profile-quick.js "schema: DONE_ARTIFACT, ...tuning('developer', 'done') }" "schema: DONE_ARTIFACT, ...tuning('developer', 'done) }"
  expect_violation "dispatch 'done' carries 0 tuning() call(s)"
}

# ── schema size ──────────────────────────────────────────────────────────────
# Claude Code in auto permission mode does not start an agent whose output schema is over 4096
# characters. The lint runs each script with every stage skipped and measures every schema: in the
# script's own scope, so a schema built from the prelude's functions is measured as it is sent.

STACK_FIELD="stack: { type: 'string', description: 'only when the step declares its own ## 4. [Stack]' }"

pad() { printf 'x%.0s' $(seq "$1"); }

# Grows the epic's STEP, which only STEPS carries, by $1 characters.
grow_step() {
  mutate profile-epic.js "$STACK_FIELD" "stack: { type: 'string', description: 'only when the step declares its own ## 4. [Stack]$(pad "$1")' }"
}

expect_warning() { # $1 = substring of the warning
  run "$T/scripts/lint-workflows.sh"
  [ "$status" -eq 0 ] || { echo "lint failed: $output"; return 1; }
  case "$output" in *"$1"*) ;; *) echo "no '$1' in: $output"; return 1 ;; esac
}

@test "a schema over the host's limit fails" {
  grow_step 1000
  expect_violation "dispatch 'execute:read-steps' has a"
  case "$output" in *"over the 4096 Claude Code starts unreviewed in auto mode"*) ;; *) echo "$output"; return 1 ;; esac
}

@test "a schema close to the limit warns and passes" {
  grow_step 1000
  run "$T/scripts/lint-workflows.sh"
  n="$(sed -n "s/.*dispatch 'execute:read-steps' has a \([0-9]*\)-character schema.*/\1/p" <<<"$output" | head -1)"
  [ -n "$n" ] || { echo "$output"; return 1; }
  rm -rf "$T/workflows" && cp -R "$ROOT/workflows" "$T/"
  grow_step $(( 3800 - (n - 1000) ))
  expect_warning "dispatch 'execute:read-steps' has a 3800-character schema, 296 under the 4096 auto-mode limit"
  case "$output" in *"warning: workflows/profile-epic.js:"*) ;; *) echo "$output"; return 1 ;; esac
}

@test "a schema the lint cannot evaluate fails" {
  mutate profile-review.js "schema: REVIEW," "schema: notDefinedHere,"
  expect_violation "dispatch 'review' has a schema lint-workflows.sh cannot measure"
}

@test "a lost runs() anchor fails" {
  mutate profile-review.js "return i >= startAt && i <= endAt" "return startAt <= i && i <= endAt"
  expect_violation "workflows/profile-review.js: lint-workflows.sh cannot find runs() in the prelude"
}

@test "a schema that grows with the contract fails" {
  mutate profile-research.js "status: { type: 'string', enum: ['done', 'partial', 'not_run', 'blocked'] }," "status: { type: 'string', enum: ['done', 'partial', 'not_run', 'blocked'], description: '$(pad 3000)' },"
  expect_violation 'dispatch '"'"'research:${picked}'"'"' has a'
  case "$output" in *"over the 4096"*) ;; *) echo "$output"; return 1 ;; esac
}

@test "a schema violation is reported beside a dispatch violation" {
  grow_step 1000
  mutate profile-review.js "$REVIEW_LINE" "{ label: 'review', phase: 'Review', agentType: A.agents.reviewer, schema: REVIEW },"
  expect_violation "dispatch 'review' carries 0 tuning() call(s)"
  case "$output" in *"dispatch 'execute:read-steps' has a"*) ;; *) echo "$output"; return 1 ;; esac
}
