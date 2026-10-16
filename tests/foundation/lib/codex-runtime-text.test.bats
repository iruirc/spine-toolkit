#!/usr/bin/env bats
# The orchestrator and the skills it loads name Claude Code tools. Outside Claude Code the host
# reads runtimes/<runtime>.md, which maps each of them (spec: multi-llm milestone 2). The runtime
# id is stated once, in the orchestrator's Runtime paragraph, and every place that names a Claude
# tool on the dispatch path points at the map — otherwise Codex reads an instruction it cannot
# follow and improvises.

setup() {
  ROOT="$(cd -- "$(dirname -- "$BATS_TEST_FILENAME")/../../.." && pwd)"
  ORCH="$ROOT/skills/orchestrator/SKILL.md"
}

@test "the orchestrator states the runtime once" {
  ! grep -q -- '--runtime claude-code' "$ORCH" || { grep -n -- '--runtime claude-code' "$ORCH"; false; }
  grep -qE 'resolve-settings\.sh"? json .*--runtime <runtime>' "$ORCH"
  para="$(grep -m1 '^\*\*Runtime\.\*\*' "$ORCH")"
  [ -n "$para" ]
  grep -qF '`claude-code` in Claude Code' <<<"$para"
  grep -qF '`codex-cli` in Codex CLI' <<<"$para"
  grep -qF 'runtimes/<runtime>.md' <<<"$para"
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

@test "the orchestrator loads skills by the runtime map outside Claude Code" {
  grep -qF 'elsewhere per `runtimes/<runtime>.md`' "$ORCH"
  ! grep -qE 'Then invoke the `Skill` tool with the name from the table' "$ORCH"
}

@test "the Codex map says Claude model names read as session" {
  grep -qF '`opus`, `sonnet`, `haiku`, `fable`' "$ROOT/runtimes/codex-cli.md"
  ! grep -qF 'any model name is accepted, and' "$ROOT/runtimes/codex-cli.md"
}

@test "the orchestrator announces a Claude model read as session" {
  ORCH="$ROOT/skills/orchestrator/SKILL.md"
  grep -F 'model, read as session' "$ORCH" | grep -qF 'warn_model_read_as_session'
  for l in en ru; do
    grep -qx '## warn_model_read_as_session' "$ROOT/skills/orchestrator/locales/$l.md" || { echo "no key in $l"; false; }
  done
}
