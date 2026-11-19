#!/usr/bin/env bats
# changed: sweep skills conventions workflows
# Split from codex-runtime-text.test.bats: the tests that walk the source trees.

setup() {
  ROOT="$(cd -- "$(dirname -- "$BATS_TEST_FILENAME")/../../.." && pwd)"
  ORCH="$ROOT/skills/orchestrator/SKILL.md"
}

@test "every workflow skill allows a contract as text" {
  for f in "$ROOT"/skills/workflow-*/SKILL.md; do
    grep -qF 'runtimes/<runtime>.md' "$f" || { echo "no runtime map in $f"; false; }
  done
}

@test "dispatch conventions point outside Claude Code to the runtime map" {
  for f in conventions/stage-dispatch.md conventions/agent-tooling.md; do
    grep -qF 'runtimes/<runtime>.md' "$ROOT/$f" || { echo "no runtime map in $f"; false; }
  done
}

@test "outside the Codex map no brief tells a stage to escalate" {
  hits="$(grep -rlF 'require_escalated' "$ROOT/conventions" "$ROOT/skills" "$ROOT/workflows" | grep -v '/skills/setup/' || true)"
  [ -z "$hits" ] || { echo "$hits"; false; }
}

# Codex hides every platform's manifest from its skill list (allow_implicit_invocation: false), so
# setup's Platform Discovery found no platform in state C (milestone 3 acceptance, first run).
@test "the Codex map finds installed platforms by their manifest files" {
  row="$(grep -F 'installed skills named `manifest`' "$ROOT/runtimes/codex-cli.md")"
  [ -n "$row" ] || { echo "no row for Platform Discovery"; false; }
  for s in 'plugins/cache/' 'skills/manifest/SKILL.md' 'CODEX_HOME' '`## Roles`' 'driver'; do
    grep -qF -- "$s" <<<"$row" || { echo "missing: $s"; false; }
  done
  grep -m1 '^\*\*Runtime\.\*\*' "$ROOT/skills/setup/SKILL.md" | grep -qF 'finding the installed platforms'
}
