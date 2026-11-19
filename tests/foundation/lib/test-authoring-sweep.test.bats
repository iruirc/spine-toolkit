#!/usr/bin/env bats
# changed: sweep skills workflows
# Split from test-authoring.test.bats: the tests that walk the source trees.

setup() {
  ROOT="$(cd -- "$(dirname -- "$BATS_TEST_FILENAME")/../../.." && pwd)"
  SKILL="$ROOT/skills/test-authoring/SKILL.md"
}

# A section's body, heading excluded, up to the next H2.
section() { # $1 = file, $2 = heading text without "## "
  awk -v h="## $2" '$0==h{f=1;next} f&&/^## /{exit} f' "$1"
}

# The Review brief's text only, stopping at the agent() options object — the same
# extractor phase-verification.test.bats uses.
review_brief() {
  awk -v stop="label: .review." '/^\/\/ ── Review ─/{p=1;next} p&&$0~stop{exit} p' "$1"
}

@test "every profile with a Review judges the tests by the skill, and the first two findings block" {
  for p in feature bug refactor test quick; do
    b="$(review_brief "$ROOT/workflows/profile-$p.js")"
    grep -qF "the way the test-authoring skill's ## Review section does" <<<"$b" \
      || { echo "profile-$p.js: Review never judges test quality"; return 1; }
    # The brief once listed the findings itself and dropped half of the fifth; it
    # now names the one it lost and leaves the list to the skill.
    grep -qF 'a name that does not say what broke included' <<<"$b" \
      || { echo "profile-$p.js: the brief still carries a partial copy of the list"; return 1; }
    grep -qF 'always go into blocking_findings' <<<"$b" \
      || { echo "profile-$p.js: a test that cannot fail may still go out as non-blocking"; return 1; }
  done
}

@test "every workflow skill's Review sends the tests to the skill as well" {
  # Method B had the clause in QUICK only; FEATURE, BUG and REFACTOR never named the
  # skill, and TEST carried a list of its own.
  for s in feature bug refactor test quick; do
    f="$ROOT/skills/workflow-$s/SKILL.md"
    r="$(grep -E '^- \*\*Review\*\* — `\[reviewer\]`' "$f")"
    grep -qF "the \`test-authoring\` skill's \`## Review\` section" <<<"$r" \
      || { echo "workflow-$s: Review does not judge tests by the skill"; return 1; }
    grep -qF 'its first two findings always block' <<<"$r" \
      || { echo "workflow-$s: Review does not say which findings block"; return 1; }
  done
  if grep -qF 'edge-case coverage, meaningful assertions' "$ROOT/skills/workflow-test/SKILL.md"; then
    echo "workflow-test still lists its own criteria"
    return 1
  fi
}
