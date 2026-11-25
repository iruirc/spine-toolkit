#!/usr/bin/env bats
# In Codex CLI's workspace-write sandbox the project's .git is read-only, the simulator and ps are
# refused, and Spine's questions come as text; in Claude Code a folder Spine writes outside the
# project asks every time. setup offers Spine's settings for the runtime it runs in behind one
# question (spec: multi-llm milestone 3, sections 2-3; milestone 5; runtime permissions).

setup() {
  ROOT="$(cd -- "$(dirname -- "$BATS_TEST_FILENAME")/../../.." && pwd)"
  SK="$ROOT/skills/setup/SKILL.md"
  TPL="$ROOT/templates/codex-rules/spine.rules"
  SECTION="$(awk '/^## Permissions$/{on=1; print; next} on && /^## /{exit} on' "$SK")"
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
  run decision /c/scripts/spine-permissions.sh apply 'menu off'
  [[ "$output" == *'"matchedRules":[]'* ]] || { echo "spine-permissions.sh must ask: $output"; false; }
}

@test "the rule template says who writes it and the risk it takes" {
  for s in 'setup' 'any file named' 'delete'; do
    grep -qiF -- "$s" "$TPL" || { echo "header lacks: $s"; false; }
  done
}

@test "setup runs Permissions in both runtimes" {
  [ -n "$SECTION" ] || { echo "no ## Permissions"; false; }
  for s in '--runtime <runtime>' 'claude-code' 'codex-cli'; do
    grep -qF -- "$s" <<<"$SECTION" || { echo "missing: $s"; false; }
  done
  ! grep -qF -- '{setting} = ``' <<<"$SECTION" || { echo "{setting} is still an English phrase in the body"; false; }
  grep -qE '^6d\. Permissions' "$SK" || { echo "step 6d is not Permissions"; false; }
  ! grep -E '^6d\. ' "$SK" | grep -qF 'Codex CLI only' || { echo "step 6d still says Codex CLI only"; false; }
  ! grep -qF 'Codex permissions (Codex CLI)' "$SK" || { echo "SKILL.md still names the old section"; false; }
  grep -A1 -- '- Keep the old name →' "$SK" | grep -qF 'step 6c and step 6d'
}

@test "the item table marks which runtime prints each item" {
  r="$(grep -F '`root <path> missing`' <<<"$SECTION" | grep -F '|')"
  grep -qF 'claude-code' <<<"$r" && grep -qF 'codex-cli' <<<"$r" || { echo "root missing row: $r"; false; }
  for item in '`rules spine.rules' '`rules spine-<name>.rules' '`menu off`' '`mcp <server> prompts`' '`root <path> unlisted`' '`root <path> stale`'; do
    r="$(grep -F -- "$item" <<<"$SECTION" | grep -F '|')"
    [ -n "$r" ] || { echo "no row for $item"; false; }
    grep -qF 'codex-cli' <<<"$r" || { echo "$item row lacks codex-cli"; false; }
    ! grep -qF 'claude-code' <<<"$r" || { echo "$item row names claude-code"; false; }
  done
}

@test "one item skips the one-by-one choice" {
  grep -qiF 'printed one item' <<<"$SECTION" || { echo "no one-item rule"; false; }
  grep -iF 'printed one item' <<<"$SECTION" | grep -qiF 'second option' || { echo "the rule does not drop the second option"; false; }
}

@test "Claude Code writes settings.local.json and says how to reach this session" {
  for s in '.claude/settings.local.json' 'perm_how_claude_code' 'perm_when_claude_code' 'perm_how_codex' 'perm_when_codex' \
           '{setting} = `perm_setting_codex`' '{setting} = `perm_setting_claude_code`' 'report_permissions_not_ignored'; do
    grep -qF -- "$s" <<<"$SECTION" || { echo "missing: $s"; false; }
  done
  for l in en ru; do
    awk '/^## perm_when_claude_code$/{on=1; next} on && /^## /{exit} on' "$ROOT/skills/setup/locales/$l.md" \
      | grep -qF '/add-dir' || { echo "$l perm_when_claude_code lacks /add-dir"; false; }
  done
}

@test "the file list names settings.local.json only in Claude Code and only with consent" {
  line="$(awk '/^## Input/{exit} 1' "$SK" | grep -F '.claude/settings.local.json')"
  [ -n "$line" ] || { echo "the file list does not name it"; false; }
  grep -qF 'Claude Code' <<<"$line" && grep -qF 'after the user agrees' <<<"$line" || { echo "$line"; false; }
}

# Milestone 5: up to five settings (core rules, platform rules, the menu, approve for the platform's
# MCP server, writable roots) — one question for all of them, one escalated write.
@test "the step asks spine-permissions.sh what is missing and asks nothing when it is all there" {
  for s in 'scripts/spine-permissions.sh' 'check --runtime <runtime> --project' '--platform-root' '--config-home' 'Plugin Roots'; do
    grep -qF -- "$s" <<<"$SECTION" || { echo "missing: $s"; false; }
  done
  grep -F 'Exit 0' <<<"$SECTION" | grep -qF 'no question' || { echo "exit 0 does not skip the question"; false; }
}

@test "one question lists every item and one escalated apply writes them" {
  for s in 'auq_permissions' 'auq_permissions_options' 'require_escalated' 'one approval' \
           'report_permissions_written' 'report_permissions_declined' 'does not commit'; do
    grep -qF -- "$s" <<<"$SECTION" || { echo "missing: $s"; false; }
  done
}

@test "choosing one by one asks per item and still applies once" {
  grep -F 'auq_permission_item' <<<"$SECTION" | grep -qF 'auq_permission_item_options' || { echo "no per-item question"; false; }
  grep -qiF 'then one `apply`' <<<"$SECTION" || { echo "per-item answers are not applied once"; false; }
}

@test "each item of check has its own wording" {
  for k in codex_item_rules_core codex_item_rules_platform codex_item_menu codex_item_mcp perm_item_root_missing codex_item_root_unlisted codex_item_root_stale; do
    grep -qF -- "$k" <<<"$SECTION" || { echo "SKILL.md does not map $k"; false; }
  done
}

@test "a check that fails is reported and setup carries on" {
  grep -F 'Exit 2' <<<"$SECTION" | grep -qF 'report_permissions_error' || { echo "exit 2 not reported"; false; }
}

@test "the new keys exist in both locales and the old ones are gone" {
  new='auq_permissions auq_permissions_options auq_permission_item auq_permission_item_options perm_item_root_missing
       report_permissions_written report_permissions_declined report_permissions_error
       perm_how_codex perm_how_claude_code perm_when_codex perm_when_claude_code
       perm_setting_codex perm_setting_claude_code report_permissions_not_ignored
       codex_item_rules_core codex_item_rules_platform codex_item_menu codex_item_mcp codex_item_root_unlisted codex_item_root_stale'
  gone='auq_codex_permissions auq_codex_permissions_options auq_codex_permission_item auq_codex_permission_item_options
        codex_item_root_missing report_codex_permissions_written report_codex_permissions_declined report_codex_permissions_error
        auq_codex_git_rule auq_codex_menu report_codex_git_rule report_codex_menu'
  for l in en ru; do
    f="$ROOT/skills/setup/locales/$l.md"
    for k in $new; do grep -qx "## $k" "$f" || { echo "no $k in $l"; false; }; done
    for k in $gone; do ! grep -qx "## $k" "$f" || { echo "old $k left in $l"; false; }; done
    body() { awk -v k="## $1" '$0==k{on=1; next} on && /^## /{exit} on' "$f"; }
    body perm_when_codex | grep -qF 'codex app-server daemon restart' || { echo "$l perm_when_codex lacks the restart"; false; }
    body perm_how_codex | grep -qF 'codex app-server daemon restart' || { echo "$l perm_how_codex lacks the restart"; false; }
    body perm_how_claude_code | grep -qF '.claude/settings.local.json' || { echo "$l perm_how_claude_code lacks the file"; false; }
    body perm_how_claude_code | grep -qF 'additionalDirectories' || { echo "$l perm_how_claude_code does not undo in additionalDirectories"; false; }
    body perm_setting_codex | grep -qF '`writable_roots`' && body perm_setting_codex | grep -qF '`.codex/config.toml`' \
      || { echo "$l perm_setting_codex"; false; }
    body perm_setting_claude_code | grep -qF '`permissions.additionalDirectories`' && body perm_setting_claude_code | grep -qF '`.claude/settings.local.json`' \
      || { echo "$l perm_setting_claude_code"; false; }
    body report_permissions_not_ignored | grep -qF '{path}' || { echo "$l report_permissions_not_ignored lacks {path}"; false; }
    body auq_permissions | grep -qF '{host}' && body auq_permissions | grep -qF '{items}' && body auq_permissions | grep -qF '{how}' \
      || { echo "$l auq_permissions lacks a placeholder"; false; }
    body report_permissions_written | grep -qF '{host}' && body report_permissions_written | grep -qF '{when}' \
      || { echo "$l report_permissions_written lacks a placeholder"; false; }
    body report_permissions_declined | grep -qF '{host}' || { echo "$l declined lacks {host}"; false; }
    body report_permissions_error | grep -qF '{error}' || { echo "$l error lacks {error}"; false; }
    body perm_item_root_missing | grep -qF '{path}' && body perm_item_root_missing | grep -qF '{setting}' \
      || { echo "$l perm_item_root_missing lacks a placeholder"; false; }
    for k in perm_item_root_missing codex_item_root_unlisted codex_item_root_stale; do
      ! body $k | grep -qF 'the external packages' || { echo "$l $k still says only the external packages"; false; }
    done
    body codex_item_menu | grep -qF '{config_path}' || { echo "$l menu item lacks the file"; false; }
    body codex_item_mcp | grep -qF '{server}' || { echo "$l mcp item lacks the server"; false; }
  done
  ! awk '/^## auq_permissions$/{on=1; next} on && /^## /{exit} on' "$ROOT/skills/setup/locales/en.md" | grep -qF 'many of its own steps' \
    || { echo "auq_permissions overstates for Claude Code"; false; }
  for k in $gone; do ! grep -qwF -- "$k" "$SK" || { echo "SKILL.md still names $k"; false; }; done
  for k in perm_item_root_missing codex_item_root_unlisted codex_item_root_stale; do
    grep -A1 -x "## $k" "$ROOT/skills/setup/locales/en.md" | grep -qF 'a folder Spine writes to' || { echo "en $k does not say it"; false; }
  done
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
  awk '/STATE C \(already_configured\)/{on=1} on && /^   STATE D /{exit} on' "$SK" | grep -F -- '- Cancel →' | grep -qF 'step 6c and step 6d'
  grep -F 'Cancel on the AUQ in state C' "$SK" | grep -qF 'step 6c and step 6d'
}

# Final review of milestone 6: a config naming a platform that was since removed ran 6d without
# --platform-root and said nothing.
@test "state C names a configured platform that is not installed, and runs on without it" {
  grep -qF 'is not installed: report `warn_config_platform_not_installed` once' "$SK" || { echo "setup does not say it"; false; }
  grep -qF 'step 6d without `--platform-root`' "$SK"
  for l in en ru; do
    grep -A1 -x '## warn_config_platform_not_installed' "$ROOT/skills/setup/locales/$l.md" | grep -qF '{platform}' \
      || { echo "$l lacks the key"; false; }
  done
}

# Final review of milestone 5: `long-run.sh start -- <command>` runs that command outside the
# sandbox whatever it is, and the user grants it with one answer — the wording has to say so.
@test "the rule header and the question say the rule runs any command outside the sandbox" {
  grep -qF 'whatever it is' "$TPL" || { echo "header does not say it"; false; }
  for l in en ru; do
    awk '/^## codex_item_rules_core$/{on=1; next} on && /^## /{exit} on' "$ROOT/skills/setup/locales/$l.md" \
      | grep -qF 'long-run.sh start -- <' || { echo "$l codex_item_rules_core does not say it"; false; }
  done
}

# Milestone 7: the Android setup asked about the platform's "simulator" commands; Kotlin drives an
# emulator, and the item is shared by every platform. The Russian word is "emulator" in its genitive,
# spelled as UTF-8 bytes: a test file is not a place the i18n lint lets Cyrillic in.
@test "the platform rules item names the emulator as well as the simulator" {
  awk '/^## codex_item_rules_platform$/{on=1; next} on && /^## /{exit} on' "$ROOT/skills/setup/locales/en.md" \
    | grep -qF 'simulator or emulator' || { echo "en does not name it"; false; }
  awk '/^## codex_item_rules_platform$/{on=1; next} on && /^## /{exit} on' "$ROOT/skills/setup/locales/ru.md" \
    | grep -qF "$(printf '\xd1\x8d\xd0\xbc\xd1\x83\xd0\xbb\xd1\x8f\xd1\x82\xd0\xbe\xd1\x80\xd0\xb0')" || { echo "ru does not name it"; false; }
}
