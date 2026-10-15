#!/usr/bin/env bats
# Codex CLI sees this plugin through .codex-plugin/plugin.json and loads only its skills/.
# A skill the orchestrator drives must not be picked by Codex on its own from its description:
# a workflow run that way skips the orchestrator's resolution and dispatch. Codex reads
# skills/<name>/agents/openai.yaml for that, as the platforms already do.

setup() {
  ROOT="$(cd -- "$(dirname -- "$BATS_TEST_FILENAME")/../../.." && pwd)"
  HIDDEN="docs-route manual-checks phase-verification security-lens task-documents task-walkthrough
          test-authoring ops-checklist feature-estimation feature-landscape feature-requirements
          stack-detect workflow-bug workflow-epic workflow-feature workflow-quick workflow-refactor
          workflow-research workflow-review workflow-test"
  VISIBLE="orchestrator setup task-new task-move task-status lang agent-status"
}

@test "the Codex manifest is valid and agrees with the Claude one" {
  run python3 - "$ROOT" <<'PY'
import json, os, sys
root = sys.argv[1]
codex = json.load(open(os.path.join(root, '.codex-plugin/plugin.json'), encoding='utf-8'))
claude = json.load(open(os.path.join(root, '.claude-plugin/plugin.json'), encoding='utf-8'))
assert codex.get('skills') == './skills/', codex.get('skills')
for key in ('name', 'version', 'repository'):
    assert codex.get(key) == claude.get(key), (key, codex.get(key), claude.get(key))
assert codex['author']['name'] == claude['author']['name']
PY
  [ "$status" -eq 0 ] || { echo "$output"; false; }
}

@test "a skill only the orchestrator drives is hidden from implicit invocation" {
  for name in $HIDDEN; do
    f="$ROOT/skills/$name/agents/openai.yaml"
    [ -f "$f" ] || { echo "missing: $f"; false; }
    grep -q 'allow_implicit_invocation: false' "$f" || { echo "not hidden: $name"; false; }
    ! grep -q 'default_prompt' "$f" || { echo "default_prompt left in: $name"; false; }
  done
}

@test "a skill the user invokes stays visible" {
  for name in $VISIBLE; do
    f="$ROOT/skills/$name/agents/openai.yaml"
    [ ! -f "$f" ] || ! grep -q 'allow_implicit_invocation: false' "$f" || { echo "hidden: $name"; false; }
  done
}

@test "every workflow skill is hidden" {
  for d in "$ROOT"/skills/workflow-*; do
    name="$(basename "$d")"
    case " $(echo $HIDDEN) " in *" $name "*) ;; *) echo "not in the hidden list: $name"; false ;; esac
  done
}
