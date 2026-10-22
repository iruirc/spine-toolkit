#!/usr/bin/env bats
# In Codex CLI's workspace-write sandbox the project's .git is read-only and Spine's questions come
# as text. setup offers two things, each behind a question: a Codex rule for git add/commit in the
# project, and the question menu in the user's Codex config (spec: multi-llm milestone 3, sections 2-3).

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

@test "the git rule step names its file and asks nothing when it is already there" {
  for s in '.codex/rules/spine.rules' 'templates/codex-rules/spine.rules' 'auq_codex_git_rule' 'does not commit'; do
    grep -qF -- "$s" <<<"$SECTION" || { echo "missing: $s"; false; }
  done
  grep -F '.codex/rules/spine.rules` exists' <<<"$SECTION" | grep -qF 'no question'
}

@test "the menu step names the line, the file and the restart, and asks nothing when it is on" {
  for s in 'default_mode_request_user_input = true' '${CODEX_HOME:-~/.codex}/config.toml' 'codex app-server daemon restart' 'auq_codex_menu'; do
    grep -qF -- "$s" <<<"$SECTION" || { echo "missing: $s"; false; }
  done
  grep -F 'already has `default_mode_request_user_input = true`' <<<"$SECTION" | grep -qF 'no question'
}

@test "the Codex permission keys exist in both locales and say what the user needs" {
  for l in en ru; do
    f="$ROOT/skills/setup/locales/$l.md"
    for k in auq_codex_git_rule auq_codex_git_rule_options auq_codex_menu auq_codex_menu_options \
             report_codex_git_rule_written report_codex_git_rule_declined report_codex_menu_enabled report_codex_menu_declined; do
      grep -qx "## $k" "$f" || { echo "no $k in $l"; false; }
    done
    menu="$(awk '/^## auq_codex_menu$/{on=1; next} on && /^## /{exit} on' "$f")"
    for s in default_mode_request_user_input '[features]' 'under development' 'codex app-server daemon restart' '{config_path}'; do
      grep -qF -- "$s" <<<"$menu" || { echo "$l auq_codex_menu lacks $s"; false; }
    done
    awk '/^## auq_codex_git_rule$/{on=1; next} on && /^## /{exit} on' "$f" | grep -qF '.codex/rules/spine.rules' \
      || { echo "$l auq_codex_git_rule lacks the file"; false; }
  done
}

# Review of milestone 3: Codex protects .codex/ like .git (protocol/src/permissions.rs) and loads
# rules once per session (core/src/session/mod.rs), so the write asks and the rule waits for a restart.
@test "writing the git rule asks for approval and takes effect after a restart" {
  grep -F '.codex/' <<<"$SECTION" | grep -qiF 'protected' || { echo "no protected-path note"; false; }
  for l in en ru; do
    awk '/^## report_codex_git_rule_written$/{on=1; next} on && /^## /{exit} on' "$ROOT/skills/setup/locales/$l.md" \
      | grep -qF 'codex app-server daemon restart' || { echo "$l report lacks the restart"; false; }
  done
}

@test "the menu step creates a config.toml that does not exist" {
  grep -qF 'does not exist' <<<"$SECTION"
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
