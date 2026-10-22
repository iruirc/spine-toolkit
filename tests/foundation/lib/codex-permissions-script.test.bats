#!/usr/bin/env bats
# In Codex CLI every build, test run and leftovers check asked the user, and so did every call of
# the user's XcodeBuildMCP and every write to an external package (multi-llm milestone 5).
# codex-permissions.sh says which of Spine's Codex settings are missing or stale, and writes the
# ones the user agreed to, touching nothing else in the files it edits.

setup() {
  ROOT="$(cd -- "$(dirname -- "$BATS_TEST_FILENAME")/../../.." && pwd)"
  CP="$ROOT/scripts/codex-permissions.sh"
  PROJ="$BATS_TEST_TMPDIR/proj"
  CH="$BATS_TEST_TMPDIR/codex-home"
  PLAT="$BATS_TEST_TMPDIR/spine-platform-swift"
  mkdir -p "$PROJ" "$CH" "$PLAT/runtimes/codex-cli/rules"
  printf 'prefix_rule(pattern=["xcodebuild"], decision="allow")\n' >"$PLAT/runtimes/codex-cli/rules/swift.rules"
  printf '{"servers": ["xcodebuildmcp", "mobilebuildmcp"]}\n' >"$PLAT/runtimes/codex-cli/mcp.json"
}

chk() { run "$CP" check --project "$PROJ" --platform-root "$PLAT" --config-home "$CH"; }
app() { run "$CP" apply --project "$PROJ" --platform-root "$PLAT" --config-home "$CH" "$@"; }
menu_on() { printf '[features]\ndefault_mode_request_user_input = true\n' >"$CH/config.toml"; }
rules_in_place() {
  mkdir -p "$PROJ/.codex/rules"
  cp "$ROOT/templates/codex-rules/spine.rules" "$PROJ/.codex/rules/spine.rules"
  cp "$PLAT/runtimes/codex-cli/rules/swift.rules" "$PROJ/.codex/rules/spine-swift.rules"
}

# --- rule files and the menu -------------------------------------------------------------------

@test "check on an empty project names both rule files and the menu" {
  chk
  [ "$status" -eq 1 ]
  [ "$output" = $'rules spine.rules missing\nrules spine-swift.rules missing\nmenu off' ] || { echo "$output"; false; }
}

@test "check without a platform root names only the core rules and the menu" {
  run "$CP" check --project "$PROJ" --config-home "$CH"
  [ "$status" -eq 1 ]
  [ "$output" = $'rules spine.rules missing\nmenu off' ] || { echo "$output"; false; }
}

@test "check with everything in place says nothing and exits 0" {
  rules_in_place; menu_on
  chk
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "a rules file that differs from its template is outdated" {
  rules_in_place; menu_on
  echo '# edited' >>"$PROJ/.codex/rules/spine.rules"
  chk
  [ "$output" = 'rules spine.rules outdated' ] || { echo "$output"; false; }
}

@test "the menu counts only under [features] and only when true" {
  rules_in_place
  printf '[other]\ndefault_mode_request_user_input = true\n' >"$CH/config.toml"
  chk; [ "$output" = 'menu off' ] || { echo "$output"; false; }
  printf '[features]\ndefault_mode_request_user_input = false\n' >"$CH/config.toml"
  chk; [ "$output" = 'menu off' ] || { echo "$output"; false; }
}

@test "apply writes the rule files byte for byte" {
  menu_on
  app 'rules spine.rules missing' 'rules spine-swift.rules missing'
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  cmp "$ROOT/templates/codex-rules/spine.rules" "$PROJ/.codex/rules/spine.rules"
  cmp "$PLAT/runtimes/codex-cli/rules/swift.rules" "$PROJ/.codex/rules/spine-swift.rules"
  chk; [ "$status" -eq 0 ] || { echo "$output"; false; }
}

@test "apply turns the menu on and keeps the rest of config.toml" {
  printf 'model = "x"\n\n[features]\nfoo = true\n\n[tui]\nbar = 1\n' >"$CH/config.toml"
  app 'menu off'
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ "$(cat "$CH/config.toml")" = $'model = "x"\n\n[features]\nfoo = true\ndefault_mode_request_user_input = true\n\n[tui]\nbar = 1' ] \
    || { cat "$CH/config.toml"; false; }
}

@test "apply replaces a false menu value in place" {
  printf '[features]\ndefault_mode_request_user_input = false\nfoo = true\n' >"$CH/config.toml"
  app 'menu off'
  [ "$(cat "$CH/config.toml")" = $'[features]\ndefault_mode_request_user_input = true\nfoo = true' ] || { cat "$CH/config.toml"; false; }
}

@test "apply adds a [features] table to a config without one" {
  printf 'model = "x"\n' >"$CH/config.toml"
  app 'menu off'
  [ "$(cat "$CH/config.toml")" = $'model = "x"\n\n[features]\ndefault_mode_request_user_input = true' ] || { cat "$CH/config.toml"; false; }
}

@test "apply creates a config.toml that does not exist" {
  rm -rf "$CH"
  app 'menu off'
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ "$(cat "$CH/config.toml")" = $'[features]\ndefault_mode_request_user_input = true' ] || { cat "$CH/config.toml"; false; }
}

@test "apply twice changes nothing the second time" {
  printf 'model = "x"\n' >"$CH/config.toml"
  app 'menu off' 'rules spine.rules missing'
  before="$(shasum "$CH/config.toml" "$PROJ/.codex/rules/spine.rules")"
  app 'menu off' 'rules spine.rules missing'
  [ "$status" -eq 0 ]
  [ "$(shasum "$CH/config.toml" "$PROJ/.codex/rules/spine.rules")" = "$before" ]
}

@test "apply refuses an unknown item and writes nothing" {
  app 'rules other.rules missing'
  [ "$status" -eq 2 ]
  [[ "$output" == *'unknown item: rules other.rules missing'* ]] || { echo "$output"; false; }
  [ ! -e "$PROJ/.codex" ]
}

@test "check without --project is a usage error" {
  run "$CP" check
  [ "$status" -eq 2 ]
}
