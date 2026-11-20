#!/usr/bin/env bats
# changed: sweep conventions skills
# A failure outside the task that the owner has accepted lives in one registry per project, so the
# next task does not ask again. The convention holds its form; only the orchestrator writes it, and
# only with the owner's consent.

setup() {
  ROOT="$(cd -- "$(dirname -- "$BATS_TEST_FILENAME")/../../.." && pwd)"
  CONV="$ROOT/conventions/known-failures.md"
}

@test "the convention holds the registry's columns, kinds and Removed section" {
  [ -f "$CONV" ] || { echo "no conventions/known-failures.md"; return 1; }
  grep -qxF '| ID | Repository | Module | Tests | Kind | Cause | Passes where | Accepted | Remove when |' "$CONV" \
    || { echo "the registry header changed"; return 1; }
  for t in '`permanent`' '`flaky`' '`KF-<N>`' '## Removed' 'never reused' '`known_failures`' '`- Known failures:' 'Tasks/KnownFailures.md' 'A missing registry is an empty one'; do
    grep -qF -- "$t" "$CONV" || { echo "the convention lost: $t"; return 1; }
  done
}

@test "only the orchestrator writes the registry, with the owner's consent, in manual" {
  for t in 'Only the orchestrator writes the registry' "owner's consent" '`manual`' 'a commit of its own' '`auto`' '`known_failures_cleared`'; do
    grep -qF -- "$t" "$CONV" || { echo "the convention lost: $t"; return 1; }
  done
  grep -qF 'conventions/known-failures.md' "$ROOT/skills/phase-verification/SKILL.md" \
    || { echo "phase-verification does not point at the convention"; return 1; }
}
