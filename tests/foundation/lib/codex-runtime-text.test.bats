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

# Codex's workspace-write sandbox refuses the simulator over XPC and keeps .git read-only
# (spec: multi-llm milestone 3, section 1 and 2). The map says what runs outside it and how.
codex_section() { awk -v h="$1" '$0==h{on=1; next} on && /^## /{exit} on' "$ROOT/runtimes/codex-cli.md"; }

@test "the Codex map says which build steps leave the sandbox" {
  sec="$(codex_section '## Builds and the simulator')"
  [ -n "$sec" ] || { echo "no ## Builds and the simulator"; false; }
  for s in 'require_escalated' 'long-run.sh start' 'ManualChecks.md' 'no escalation'; do
    grep -qF -- "$s" <<<"$sec" || { echo "missing: $s"; false; }
  done
}

# Milestone 5: Codex matches a rule by the program's file name (execpolicy/src/policy.rs), and an
# allow rule runs the command outside the sandbox without a question — but only when the first
# word is the program: a shell wrapper with variables or redirections is matched whole and misses.
@test "the Codex map calls Spine's scripts and the platform's build tools by rule, escalating only on refusal" {
  sec="$(codex_section '## Builds and the simulator')"
  for s in '.codex/rules/' 'long-run.sh' 'stage-leftovers.sh' 'without escalation' 'first word' 'bash -lc' '`cd … &&`' 'asks or refuses'; do
    grep -qF -- "$s" <<<"$sec" || { echo "missing: $s"; false; }
  done
  grep -F 'long-run.sh wait' <<<"$sec" | grep -qF 'not permitted' || { echo "wait inside the sandbox is no longer explained"; false; }
}

@test "the Codex map keeps the leftovers skip only for a run without the rules" {
  sec="$(codex_section '## Known limits')"
  grep -F 'ps is not permitted here' <<<"$sec" | grep -qF 'rule' || { echo "skip is not tied to the missing rule"; false; }
}

@test "outside the Codex map no brief tells a stage to escalate" {
  hits="$(grep -rlF 'require_escalated' "$ROOT/conventions" "$ROOT/skills" "$ROOT/workflows" | grep -v '/skills/setup/' || true)"
  [ -z "$hits" ] || { echo "$hits"; false; }
}

@test "the orchestrator checks Spine's Codex settings at the start of a task in Codex only" {
  ORCH="$ROOT/skills/orchestrator/SKILL.md"
  para="$(grep -F 'codex-permissions.sh check' "$ORCH")"
  [ -n "$para" ] || { echo "no check in the orchestrator"; false; }
  for s in 'codex-cli' 'codex_permissions_outdated' 'carries on'; do
    grep -qF -- "$s" <<<"$para" || { echo "missing: $s"; false; }
  done
  for l in en ru; do
    grep -qx '## codex_permissions_outdated' "$ROOT/skills/orchestrator/locales/$l.md" || { echo "no key in $l"; false; }
  done
  grep -qF 'codex-permissions.sh check' "$ROOT/runtimes/codex-cli.md" || { echo "the map does not name the check"; false; }
}

@test "the SPINE.md template says External packages are writable in Codex and Roots are not" {
  T="$ROOT/templates/spine-md/en.md"
  awk '/^`External packages` may repeat/{on=1} on && /^$/{exit} on' "$T" | grep -qF 'writable_roots' || { echo "External packages paragraph lacks writable_roots"; false; }
  awk '/^`Roots` may repeat/{on=1} on && /^$/{exit} on' "$T" | grep -qF 'read-only in Codex CLI' || { echo "Roots paragraph lacks read-only"; false; }
}

@test "the Codex map says how commits pass the read-only .git" {
  sec="$(codex_section '## Git')"
  [ -n "$sec" ] || { echo "no ## Git"; false; }
  for s in '.codex/rules/spine.rules' 'without `-C`' '`Tasks/`'; do
    grep -qF -- "$s" <<<"$sec" || { echo "missing: $s"; false; }
  done
}

@test "the Codex map's tool table routes long-run.sh" {
  grep -E '^\| [^|]*long-run\.sh' "$ROOT/runtimes/codex-cli.md" | grep -qF 'Builds and the simulator'
}

@test "the Codex map keeps a commit in the plain words the rule matches" {
  sec="$(codex_section '## Git')"
  for s in "-m '<subject>'" 'no `$(…)`' 'heredoc' '`cd … &&`' 'working directory'; do
    grep -qF -- "$s" <<<"$sec" || { echo "missing: $s"; false; }
  done
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

# Acceptance of milestone 3, QUICK 534: Codex's Default-mode request_user_input auto-resolves after
# two minutes with an empty answer (tui request_user_input/mod.rs, is_blocking = mode == Plan); a
# stage waiting for the user's sandbox approval looked hung, and the orchestrator ran its build itself.
@test "the Codex map reads an empty menu answer as no answer" {
  row="$(grep -F '`AskUserQuestion`' "$ROOT/runtimes/codex-cli.md")"
  for s in 'empty answer' 'two minutes' 'numbered text' 'end your turn'; do
    grep -qF -- "$s" <<<"$row" || { echo "missing: $s"; false; }
  done
}

@test "the Codex map never takes over a stage that waits for the user" {
  row="$(grep -F 'collaboration.spawn_agent' "$ROOT/runtimes/codex-cli.md" | head -1)"
  for s in 'waiting for the user' 'never interrupt' 'never run its commands yourself'; do
    grep -qF -- "$s" <<<"$row" || { echo "missing: $s"; false; }
  done
}

@test "the Codex map reads a driver's manifest from its plugin cache" {
  row="$(grep -F 'invoke / load a skill' "$ROOT/runtimes/codex-cli.md")"
  grep -qF '<driver>:manifest' <<<"$row" || { echo "no driver manifest in the load row"; false; }
}

@test "the orchestrator says only REVIEW moves a task folder" {
  grep -qF 'Only the REVIEW profile moves a task folder' "$ROOT/skills/orchestrator/SKILL.md"
}

@test "the Codex map sanitizes a driver prefix" {
  M="$ROOT/runtimes/codex-cli.md"
  grep -qF 'mcp__agent_device__' "$M"
  grep -qF '[A-Za-z0-9_]' "$M"
}
