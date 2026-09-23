#!/usr/bin/env bats
# A stage agent searched the whole disk for conventions/i18n.md: the brief named it relative to a
# root the agent was never told. The contract carries the root; the prelude names it once.

setup() {
  ROOT="$(cd -- "$(dirname -- "$BATS_TEST_FILENAME")/../../.." && pwd)"
}

@test "the prelude names the core root and the long-run budget" {
  for f in "$ROOT"/workflows/profile-*.js; do
    for s in "const CORE = A.plugin_root" \
             'const core = (p) => `${CORE}/${p}`' \
             'const LONG_RUN = { stall: 5, max: 30, ...(A.long_run || {}) }' \
             'Core root: ${CORE} — every conventions/… or scripts/… path named in this brief or in your agent definition is relative to it.' \
             "Long-running commands: follow \${core('conventions/agent-tooling.md')} → Long-running commands, with --stall \${60 * LONG_RUN.stall} --max \${60 * LONG_RUN.max}."; do
      grep -qF -- "$s" "$f" || { echo "$(basename "$f"): missing: $s"; return 1; }
    done
  done
}

@test "no prompt names a core file relative to a root it does not give" {
  for f in "$ROOT"/workflows/profile-*.js; do
    bare="$(grep -vE '^[[:space:]]*//|description:' "$f" | sed "s/core('conventions\/[a-z0-9-]*\.md')//g" \
            | grep -oE 'conventions/[a-z0-9-]+\.md' || true)"
    [ -z "$bare" ] || { echo "$(basename "$f"): bare reference: $bare"; return 1; }
    if grep -qF '<core root>' "$f"; then echo "$(basename "$f"): names <core root> instead of CORE"; return 1; fi
  done
}

# Runs the script body up to its first stage with a contract that lacks a usable plugin_root.
refusal() {
  node -e '
    const fs = require("fs")
    const body = fs.readFileSync(process.argv[1], "utf8").replace(/^export const meta/m, "const meta")
    const run = new (Object.getPrototypeOf(async function () {}).constructor)("args", "log", body)
    run(JSON.parse(process.argv[2]), () => {}).then((r) => console.log(r && r.reason))
  ' "$1" "$2"
}

@test "without an absolute, expanded plugin_root the script refuses" {
  base='"task_id": "001", "task_dir": "/p/Tasks/ACTIVE/001-x", "agents": {"developer": "d"}'
  for f in "$ROOT"/workflows/profile-*.js; do
    for root in '' ', "plugin_root": ""' ', "plugin_root": "spine-toolkit"' ', "plugin_root": "${CLAUDE_PLUGIN_ROOT}"'; do
      [ "$(refusal "$f" "{$base$root}")" = no-plugin-root ] || { echo "$(basename "$f"): accepted {$root}"; return 1; }
    done
  done
  for f in "$ROOT"/workflows/profile-*.js; do
    ! grep -qF -e "A.plugin_root || ''" -e "\${CORE ? " "$f" || { echo "$(basename "$f"): still falls back without CORE"; return 1; }
  done
  return 0
}

section() { awk -v h="## $2" '$0==h{f=1;next} f&&/^## /{exit} f' "$1"; }

@test "the orchestrator passes plugin_root to every profile under Method A" {
  S="$ROOT/skills/orchestrator/SKILL.md"
  grep -qF '**`plugin_root` — every profile, Method A.**' "$S" || { echo "plugin_root is still EPIC-only"; return 1; }
  grep -qF '**EPIC-only optional field — `epic_dispatch_mode`.**' "$S" || { echo "epic_dispatch_mode lost its paragraph"; return 1; }
  if grep -qF 'EPIC-specific, Method A only' "$ROOT/skills/workflow-epic/SKILL.md"; then
    echo "workflow-epic still calls plugin_root EPIC-specific"; return 1
  fi
}

@test "the contract carries long_run for every profile" {
  S="$ROOT/skills/orchestrator/SKILL.md"
  grep -qxF 'long_run={stall: 5, max: 30}' "$S" || { echo "no long_run in the example contract"; return 1; }
  p="$(grep -F '`long_run` — ' "$S")"
  for t in 'resolve-settings.sh json' 'Always filled' 'scripts/long-run.sh' 'in seconds'; do
    grep -qF -- "$t" <<<"$p" || { echo "the long_run paragraph lost: $t"; return 1; }
  done
}

@test "Method B names the core root in a subagent's prompt" {
  s="$(section "$ROOT/conventions/stage-dispatch.md" 'Standing authorization')"
  for t in 'absolute path' '`Core root:`' '`Long-running commands:`'; do
    grep -qF -- "$t" <<<"$s" || { echo "stage-dispatch lost: $t"; return 1; }
  done
}
