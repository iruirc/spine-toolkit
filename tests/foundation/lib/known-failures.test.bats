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

# The gate's own paragraph in the orchestrator, from its bold title to the next bold paragraph.
outside_gate() {
  awk '/^\*\*After Validation: failures outside the task\.\*\*/{f=1; print; next} f&&/^\*\*/{exit} f' \
    "$ROOT/skills/orchestrator/SKILL.md"
}

@test "the orchestrator offers the registry only in manual and only on consent" {
  gate="$(outside_gate)"
  [ -n "$gate" ] || { echo "no **After Validation: failures outside the task.** paragraph"; return 1; }
  for key in known_failures_outside known_failures_add_flaky known_failures_add_permanent known_failures_cleared; do
    grep -qF -- "\`$key\`" <<<"$gate" || { echo "the gate does not name $key"; return 1; }
    for l in en ru; do
      grep -qx "## $key" "$ROOT/skills/orchestrator/locales/$l.md" || { echo "$l.md has no $key"; return 1; }
    done
  done
  for l in en ru; do
    awk '/^## known_failures_outside$/{f=1;next} f&&/^## /{exit} f' "$ROOT/skills/orchestrator/locales/$l.md" \
      | grep -qF '{list}' || { echo "$l.md: known_failures_outside has no {list}"; return 1; }
    awk '/^## known_failures_cleared$/{f=1;next} f&&/^## /{exit} f' "$ROOT/skills/orchestrator/locales/$l.md" \
      | grep -qF '{ids}' || { echo "$l.md: known_failures_cleared has no {ids}"; return 1; }
  done
  for t in '`PASSED_WITH_FLAKES`' '`FAILED`' '`outside_failures`' '`known_failures_cleared`' 'conventions/known-failures.md' \
    'consent' 'Questions.md' 'a commit of its own' '## Removed' 'Method B' 'In `auto` the registry does not change'; do
    grep -qF -- "$t" <<<"$gate" || { echo "the gate does not say: $t"; return 1; }
  done
}

@test "an epic with a step that passed with flakes goes to Acceptance" {
  rule="$(grep -F '**EPIC after its steps.**' "$ROOT/skills/orchestrator/SKILL.md")"
  grep -qF 'PASSED_WITH_FLAKES' <<<"$rule" || { echo "State Detection item 4 does not read PASSED_WITH_FLAKES as passed"; return 1; }
  walk="$(grep -F 'with a `validation_status` other than' "$ROOT/skills/workflow-epic/SKILL.md")"
  grep -qF 'PASSED_WITH_FLAKES' <<<"$walk" || { echo "the epic walk stops on a step that passed with flakes"; return 1; }
  grep -qF '[VALIDATION_STATUS] = PASSED_WITH_FLAKES' "$ROOT/skills/workflow-epic/SKILL.md" \
    || { echo "Acceptance does not take a PASSED_WITH_FLAKES Validation.md as already passed"; return 1; }
}

@test "every workflow skill names four Validation statuses" {
  for p in feature bug refactor test quick epic; do
    f="$ROOT/skills/workflow-$p/SKILL.md"
    grep -qF 'PASSED | PASSED_WITH_FLAKES | FAILED | FLAKY' "$f" || { echo "workflow-$p: no four-value status line"; return 1; }
    ! grep -qF '= PASSED | FAILED | FLAKY' "$f" || { echo "workflow-$p: a three-value status line is left"; return 1; }
  done
}

@test "a Method B Validation reads the registry and carries runs as Method A does" {
  for p in feature bug refactor test quick; do
    f="$ROOT/skills/workflow-$p/SKILL.md"
    for t in '`known_failures`' '### Failures outside the task' '## Outside the task' '`outside_failures`' \
      '`known_failures_cleared`' '`carried <sha> (phase <N>)`' '`carried <sha> (validation)`' \
      'ran: <repository> <module> HEAD <sha> tests <N> result "<result line>" log phase-evidence/phase-<id>/<module>.log' \
      'the log the excerpt `evidence.sh keep` writes in the task folder' \
      'On PASSED or PASSED_WITH_FLAKES' 'Validation passed with <n> flake(s) outside the task.' 'class `reach`'; do
      grep -qF -- "$t" "$f" || { echo "workflow-$p does not say: $t"; return 1; }
    done
  done
}

@test "the configuration doc names the fourth status and how an entry comes and goes" {
  doc="$ROOT/docs/configuration.md"
  for t in '`PASSED_WITH_FLAKES`' "owner's word" '`manual`' '## Removed' 'Questions.md'; do
    grep -qF -- "$t" "$doc" || { echo "docs/configuration.md does not say: $t"; return 1; }
  done
}

@test "the registry offers print only what is new, ask a removal on its own and never duplicate an entry" {
  gate="$(outside_gate)"
  for t in "whose outcome is \`flaky\` or \`red\`" "Items whose outcome is \`known\` are not printed" \
    'a question of its own' '`known_failures_remove`' '`known_failures_keep`' 'two answers, never one' \
    'replaces it — the `flaky` entry moves to `## Removed`' 'no two entries match the same repository, module and test' \
    '`Remove when` from `Validation.md` where it names' 'else `—`'; do
    grep -qF -- "$t" <<<"$gate" || { echo "the gate does not say: $t"; return 1; }
  done
  for key in known_failures_remove known_failures_keep; do
    for l in en ru; do
      grep -qx "## $key" "$ROOT/skills/orchestrator/locales/$l.md" || { echo "$l.md has no $key"; return 1; }
    done
  done
  for t in 'replaces it: the `flaky` entry moves to `## Removed`' 'no two' 'else `—`' 'a question of'; do
    grep -qF -- "$t" "$CONV" || { echo "the convention lost: $t"; return 1; }
  done
}

@test "a null rerun runs what no carried run covers, wherever the contract is described" {
  for f in skills/orchestrator/SKILL.md conventions/task-ranges.md conventions/stage-dispatch.md; do
    grep -qF 'no carried run covers' "$ROOT/$f" || { echo "$f does not say a null rerun keeps carried runs"; return 1; }
    ! grep -qE 'null means the whole set|runs the whole set' "$ROOT/$f" || { echo "$f still says the whole set"; return 1; }
  done
}

@test "a Method B Validation prompt names the registry as the Method A brief words it" {
  conv="$ROOT/conventions/stage-dispatch.md"
  for t in '`known_failures`' "The project's known failures registry is <path>; a missing file is an empty registry." \
    'The project keeps no known failures registry.'; do
    grep -qF -- "$t" "$conv" || { echo "stage-dispatch.md does not say: $t"; return 1; }
  done
  pre="$ROOT/workflow-src/prelude.js"
  grep -qF "The project's known failures registry is \${KNOWN_FAILURES}; a missing file is an empty registry." "$pre" \
    || { echo "the Method A brief no longer words the registry this way"; return 1; }
  grep -qF "'The project keeps no known failures registry.'" "$pre" || { echo "the Method A brief lost the empty wording"; return 1; }
}

@test "a Method B Review runs no suite when the scope lint prints no finding, as Method A" {
  for p in feature bug refactor test quick; do
    f="$ROOT/skills/workflow-$p/SKILL.md"
    grep -qF 'when it prints no finding the reviewer runs no suite' "$f" || { echo "workflow-$p: the Review rule"; return 1; }
    ! grep -qF 'when it prints nothing the reviewer runs no suite' "$f" || { echo "workflow-$p: still 'prints nothing'"; return 1; }
  done
}

@test "the registry's example row is a neutral one" {
  grep -qF '| KF-1 | Packages/Core | Core | HostedViewTests | permanent | needs an app host | under the app host, 0 failures |' "$CONV" \
    || { echo "the example row changed"; return 1; }
}
