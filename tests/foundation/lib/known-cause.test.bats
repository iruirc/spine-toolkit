#!/usr/bin/env bats
# A BUG task whose Task.md already proved the cause spent 21 of its 46 minutes in Reproduce
# finding it again. These tests hold the rule in every place a BUG run reads it.

setup() {
  ROOT="$(cd -- "$(dirname -- "$BATS_TEST_FILENAME")/../../.." && pwd)"
  BUG="$ROOT/workflows/profile-bug.js"
}

# A stage's block in a profile script, from its banner to the next one.
stage_block() { # $1 = file, $2 = stage
  awk -v s="// ── $2 " 'index($0,s)==1{p=1;next} p&&/^\/\/ ── /{exit} p' "$1"
}

@test "Reproduce checks a cause Task.md names instead of rediscovering it" {
  r="$(stage_block "$BUG" Reproduce)"
  for f in 'When Task.md already names the root cause at file:line' 'make the red run' \
           'Investigate further only if the check does not match' \
           'the one confirmed from Task.md, where it named one'; do
    grep -qF "$f" <<<"$r" || { echo "Reproduce lost: $f"; return 1; }
  done
}

@test "the Diagnose lens does not trace a confirmed cause again" {
  d="$(stage_block "$BUG" Diagnose)"
  grep -qF 'When Reproduce.md records a root cause confirmed from Task.md, do not trace it again' <<<"$d" \
    || { echo "the diagnostics lens re-traces a confirmed cause"; return 1; }
  grep -qF 'the same defect at other call sites' <<<"$d" \
    || { echo "the lens has nothing left to look for"; return 1; }
}

@test "Method B and the orchestrator say the same" {
  w="$ROOT/skills/workflow-bug/SKILL.md"
  grep -qF 'Reproduce checks it rather than rediscovering it' "$w" || { echo "workflow-bug: Reproduce"; return 1; }
  grep -qF 'is not traced again' "$w" || { echo "workflow-bug: Diagnose"; return 1; }
  grep -qF 'rather than rediscovering it' "$ROOT/skills/orchestrator/SKILL.md" \
    || { echo "orchestrator: the inline-content note"; return 1; }
}
