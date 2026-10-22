#!/usr/bin/env bats
# In Codex CLI's workspace-write sandbox the project's .git is read-only, the simulator and ps are
# refused, and Spine's questions come as text. setup offers Spine's Codex settings behind one
# question (spec: multi-llm milestone 3, sections 2-3; milestone 5).

setup() {
  ROOT="$(cd -- "$(dirname -- "$BATS_TEST_FILENAME")/../../.." && pwd)"
  SK="$ROOT/skills/setup/SKILL.md"
  TPL="$ROOT/templates/codex-rules/spine.rules"
  SECTION="$(awk '/^## Codex permissions \(Codex CLI\)/{on=1; print; next} on && /^## /{exit} on' "$SK")"
}

# Codex matches a rule by the program's file name too when the first word is a path
# (execpolicy/src/policy.rs; always on in a session), so one rule covers every installed version.
decision() { codex execpolicy check --resolve-host-executables --rules "$TPL" "$@"; }

@test "the rule template lets git add and commit through and nothing else" {
  command -v codex >/dev/null || skip "codex is not installed"
  grep -qF 'pattern=["git", ["add", "commit"]]' "$TPL"
  run decision git commit -m x
  [[ "$output" == *'"decision":"allow"'* ]] || { echo "$output"; false; }
  run decision git push
  [[ "$output" == *'"matchedRules":[]'* ]] || { echo "$output"; false; }
}

@test "the rule template lets Spine's scripts out of the sandbox at any installed version" {
  command -v codex >/dev/null || skip "codex is not installed"
  for cmd in "/c/plugins/cache/m/core/2.30.0/scripts/long-run.sh start -- make test" \
             "/c/scripts/long-run.sh wait /tmp/x.log --stall 60 --max 120" \
             "/c/scripts/long-run.sh stop /tmp/x.log" \
             "/c/scripts/stage-leftovers.sh snap --out /tmp/s" "/c/scripts/stage-leftovers.sh diff /tmp/s"; do
    run decision $cmd
    [[ "$output" == *'"decision":"allow"'* ]] || { echo "$cmd: $output"; false; }
  done
  run decision /c/scripts/codex-permissions.sh apply 'menu off'
  [[ "$output" == *'"matchedRules":[]'* ]] || { echo "codex-permissions.sh must ask: $output"; false; }
}

@test "the rule template says who writes it and the risk it takes" {
  for s in 'setup' 'any file named' 'delete'; do
    grep -qiF -- "$s" "$TPL" || { echo "header lacks: $s"; false; }
  done
}

@test "setup writes Codex permissions only in Codex CLI, after AGENTS.md" {
  [ -n "$SECTION" ] || { echo "no ## Codex permissions (Codex CLI)"; false; }
  grep -qF 'Claude Code' <<<"$SECTION"
  grep -qiF 'nothing' <<<"$SECTION"
  grep -qE '^6d\. ' "$SK"
  grep -A1 -- '- Keep the old name →' "$SK" | grep -qF 'step 6c and step 6d'
}

# Milestone 5: up to five settings (core rules, platform rules, the menu, approve for the platform's
# MCP server, writable roots) — one question for all of them, one escalated write.
@test "the step asks codex-permissions.sh what is missing and asks nothing when it is all there" {
  for s in 'scripts/codex-permissions.sh' 'check --project' '--platform-root' '--config-home' 'Plugin Roots'; do
    grep -qF -- "$s" <<<"$SECTION" || { echo "missing: $s"; false; }
  done
  grep -F 'Exit 0' <<<"$SECTION" | grep -qF 'no question' || { echo "exit 0 does not skip the question"; false; }
}

@test "one question lists every item and one escalated apply writes them" {
  for s in 'auq_codex_permissions' 'auq_codex_permissions_options' 'require_escalated' 'one approval' \
           'report_codex_permissions_written' 'report_codex_permissions_declined' 'does not commit'; do
    grep -qF -- "$s" <<<"$SECTION" || { echo "missing: $s"; false; }
  done
}

@test "choosing one by one asks per item and still applies once" {
  grep -F 'auq_codex_permission_item' <<<"$SECTION" | grep -qF 'auq_codex_permission_item_options' || { echo "no per-item question"; false; }
  grep -qiF 'then one `apply`' <<<"$SECTION" || { echo "per-item answers are not applied once"; false; }
}

@test "each item of check has its own wording" {
  for k in codex_item_rules_core codex_item_rules_platform codex_item_menu codex_item_mcp codex_item_root_missing codex_item_root_stale; do
    grep -qF -- "$k" <<<"$SECTION" || { echo "SKILL.md does not map $k"; false; }
  done
}

@test "a check that fails is reported and setup carries on" {
  grep -F 'Exit 2' <<<"$SECTION" | grep -qF 'report_codex_permissions_error' || { echo "exit 2 not reported"; false; }
}

@test "the Codex permission keys exist in both locales; the old ones are gone" {
  for l in en ru; do
    f="$ROOT/skills/setup/locales/$l.md"
    for k in auq_codex_permissions auq_codex_permissions_options auq_codex_permission_item auq_codex_permission_item_options \
             codex_item_rules_core codex_item_rules_platform codex_item_menu codex_item_mcp codex_item_root_missing \
             codex_item_root_stale report_codex_permissions_written report_codex_permissions_declined report_codex_permissions_error; do
      grep -qx "## $k" "$f" || { echo "no $k in $l"; false; }
    done
    ! grep -qE '^## (auq_codex_git_rule|auq_codex_menu|report_codex_git_rule|report_codex_menu)' "$f" || { echo "old key left in $l"; false; }
    awk '/^## report_codex_permissions_written$/{on=1; next} on && /^## /{exit} on' "$f" \
      | grep -qF 'codex app-server daemon restart' || { echo "$l report lacks the restart"; false; }
    awk '/^## codex_item_menu$/{on=1; next} on && /^## /{exit} on' "$f" | grep -qF '{config_path}' || { echo "$l menu item lacks the file"; false; }
    awk '/^## codex_item_mcp$/{on=1; next} on && /^## /{exit} on' "$f" | grep -qF '{server}' || { echo "$l mcp item lacks the server"; false; }
  done
  ! grep -qE 'auq_codex_git_rule|auq_codex_menu|report_codex_git_rule|report_codex_menu' "$SK" || { echo "SKILL.md still names an old key"; false; }
}

@test "writing into .codex/ is protected, so the apply runs escalated and takes effect after a restart" {
  grep -F '.codex/' <<<"$SECTION" | grep -qiF 'protected' || { echo "no protected-path note"; false; }
}

@test "state F leaves step 6d for the next run" {
  grep -E '^6d\. ' -A2 "$SK" | grep -qF 'state F'
}

# A project set up before reaches state C; its Cancel keeps the config, and must not keep the
# Codex questions from a user who only came for them.
@test "Cancel in state C keeps the config and still runs steps 6c and 6d" {
  awk '/STATE C \(already_configured\)/{on=1} on && /^ *b\. Ask qM/{exit} on' "$SK" | grep -F -- '- Cancel →' | grep -qF 'step 6c and step 6d'
  grep -F 'Cancel on the AUQ in state C' "$SK" | grep -qF 'step 6c and step 6d'
}
