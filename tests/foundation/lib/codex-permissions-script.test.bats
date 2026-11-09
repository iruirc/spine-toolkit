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

# --- the platform's MCP server ---------------------------------------------------------------------

# Only the MCP and root lines of check, the rule files and the menu being in place.
chk_rest() { rules_in_place; [ -f "$CH/config.toml" ] || menu_on; chk; }

@test "a server is found by its command's file name" {
  menu_on; printf '\n[mcp_servers.mobilebuildmcp]\ncommand = "/opt/x/mobilebuildmcp"\nargs = ["mcp"]\n' >>"$CH/config.toml"
  chk_rest
  [ "$status" -eq 1 ]
  [ "$output" = 'mcp mobilebuildmcp prompts' ] || { echo "$output"; false; }
}

@test "a server is found by the npx package" {
  menu_on; printf '\n[mcp_servers."XcodeBuildMCP"]\ncommand = "npx"\nargs = ["-y", "xcodebuildmcp@1.2.3", "mcp"]\n' >>"$CH/config.toml"
  chk_rest
  [ "$output" = 'mcp XcodeBuildMCP prompts' ] || { echo "$output"; false; }
}

@test "any approval mode the user set is left alone" {
  menu_on; printf '\n[mcp_servers.mobilebuildmcp]\ncommand = "mobilebuildmcp"\ndefault_tools_approval_mode = "prompt"\n' >>"$CH/config.toml"
  chk_rest
  [ "$status" -eq 0 ] || { echo "$output"; false; }
}

@test "a server the platform does not list is not named" {
  menu_on; printf '\n[mcp_servers.other]\ncommand = "other"\n' >>"$CH/config.toml"
  chk_rest
  [ "$status" -eq 0 ] || { echo "$output"; false; }
}

@test "apply puts approve under the server's own header, not a subtable" {
  menu_on
  printf '\n[mcp_servers.mobilebuildmcp]\ncommand = "mobilebuildmcp"\n\n[mcp_servers.mobilebuildmcp.env]\nA = "1"\n\n[tui]\nx = 1\n' >>"$CH/config.toml"
  rules_in_place
  app 'mcp mobilebuildmcp prompts'
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ "$(cat "$CH/config.toml")" = $'[features]\ndefault_mode_request_user_input = true\n\n[mcp_servers.mobilebuildmcp]\ndefault_tools_approval_mode = "approve"\ncommand = "mobilebuildmcp"\n\n[mcp_servers.mobilebuildmcp.env]\nA = "1"\n\n[tui]\nx = 1' ] \
    || { cat "$CH/config.toml"; false; }
  chk; [ "$status" -eq 0 ] || { echo "$output"; false; }
}

@test "apply finds a quoted server header" {
  menu_on; printf '\n[mcp_servers."XcodeBuildMCP"]\ncommand = "npx"\nargs = ["xcodebuildmcp@1.2.3"]\n' >>"$CH/config.toml"
  rules_in_place
  app 'mcp XcodeBuildMCP prompts'
  grep -A1 -F '[mcp_servers."XcodeBuildMCP"]' "$CH/config.toml" | grep -qx 'default_tools_approval_mode = "approve"'
}

@test "apply refuses a server check does not name" {
  menu_on
  app 'mcp nosuch prompts'
  [ "$status" -eq 2 ]
}

# --- writable roots ------------------------------------------------------------------------------

spine_md() { printf '# SPINE.md\n\n## Paths\n\n%s\n' "$1" >"$PROJ/${2:-SPINE.md}"; }

@test "External packages become writable roots, the folder before the glob" {
  spine_md '- External packages: /../pkgs/*'
  chk_rest
  [ "$output" = "root $(cd "$PROJ/.." && pwd)/pkgs unlisted" ] || { echo "$output"; false; }
}

@test "each External packages line is its own root" {
  spine_md $'- External packages: /../pkgs/*\n- External packages: /vendor/Kit'
  chk_rest
  [ "$output" = "root $(cd "$PROJ/.." && pwd)/pkgs unlisted"$'\n'"root $PROJ/vendor/Kit unlisted" ] || { echo "$output"; false; }
}

@test "the template's example line is not a path" {
  spine_md '(optional: "- Sources: /Sources", "- External packages: /Packages/*", "- Roots: ../design-assets"'
  chk_rest
  [ "$status" -eq 0 ] || { echo "$output"; false; }
}

@test "Roots stay read-only" {
  spine_md '- Roots: ../design-assets'
  chk_rest
  [ "$status" -eq 0 ] || { echo "$output"; false; }
}

@test "CLAUDE-spine-toolkit.md is read when SPINE.md is absent" {
  spine_md '- External packages: /../pkgs/*' CLAUDE-spine-toolkit.md
  chk_rest
  [ "$output" = "root $(cd "$PROJ/.." && pwd)/pkgs unlisted" ] || { echo "$output"; false; }
}

@test "no .codex folder: apply creates config.toml with the root" {
  spine_md '- External packages: /../pkgs/*'
  root="$(cd "$PROJ/.." && pwd)/pkgs"
  app "root $root missing"
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ "$(cat "$PROJ/.codex/config.toml")" = $'[sandbox_workspace_write]\nwritable_roots = [\n  "'"$root"$'", # spine\n]' ] \
    || { cat "$PROJ/.codex/config.toml"; false; }
}

@test "apply writes writable_roots as a multi-line array and keeps the user's own" {
  spine_md '- External packages: /../pkgs/*'
  root="$(cd "$PROJ/.." && pwd)/pkgs"
  mkdir -p "$PROJ/.codex"
  printf 'model = "m"\n\n[sandbox_workspace_write]\nnetwork_access = true\nwritable_roots = ["/u/own"]\n' >"$PROJ/.codex/config.toml"
  app "root $root missing"
  [ "$(cat "$PROJ/.codex/config.toml")" = $'model = "m"\n\n[sandbox_workspace_write]\nnetwork_access = true\nwritable_roots = [\n  "/u/own",\n  "'"$root"$'", # spine\n]' ] \
    || { cat "$PROJ/.codex/config.toml"; false; }
  chk_rest; [ "$status" -eq 0 ] || { echo "$output"; false; }
}

@test "a marked root no longer in SPINE.md is stale and apply removes only it" {
  spine_md '- Sources: /Sources'
  mkdir -p "$PROJ/.codex"
  printf '[sandbox_workspace_write]\nwritable_roots = [\n  "/u/own",\n  "/old/pkgs", # spine\n]\n' >"$PROJ/.codex/config.toml"
  chk_rest
  [ "$output" = 'root /old/pkgs stale' ] || { echo "$output"; false; }
  app 'root /old/pkgs stale'
  [ "$(cat "$PROJ/.codex/config.toml")" = $'[sandbox_workspace_write]\nwritable_roots = [\n  "/u/own",\n]' ] \
    || { cat "$PROJ/.codex/config.toml"; false; }
}

@test "a root the user listed is never named" {
  spine_md '- External packages: /../pkgs/*'
  root="$(cd "$PROJ/.." && pwd)/pkgs"
  mkdir -p "$PROJ/.codex"
  printf '[sandbox_workspace_write]\nwritable_roots = ["/u/own", "%s"]\n' "$root" >"$PROJ/.codex/config.toml"
  chk_rest
  [ "$status" -eq 0 ] || { echo "$output"; false; }
}

# A field project: the session could write the whole project folder, packages inside it, yet check
# said the packages root was missing — it compared the exact path in one file and nothing else.
@test "a root under a folder the project's config lists is not named" {
  spine_md '- External packages: /../pkgs/*'
  mkdir -p "$PROJ/.codex"
  printf '[sandbox_workspace_write]\nwritable_roots = ["%s"]\n' "$(cd "$PROJ/.." && pwd)" >"$PROJ/.codex/config.toml"
  chk_rest
  [ "$status" -eq 0 ] || { echo "$output"; false; }
}

@test "a root the user's config.toml covers is not named" {
  spine_md '- External packages: /../pkgs/*'
  printf '[features]\ndefault_mode_request_user_input = true\n\n[sandbox_workspace_write]\nwritable_roots = ["%s/"]\n' \
    "$(cd "$PROJ/.." && pwd)" >"$CH/config.toml"
  chk_rest
  [ "$status" -eq 0 ] || { echo "$output"; false; }
}

@test "a sibling folder with a shared prefix does not cover a root" {
  spine_md '- External packages: /../pkgs/*'
  mkdir -p "$PROJ/.codex"
  printf '[sandbox_workspace_write]\nwritable_roots = ["%s/pk"]\n' "$(cd "$PROJ/.." && pwd)" >"$PROJ/.codex/config.toml"
  chk_rest
  [ "$output" = "root $(cd "$PROJ/.." && pwd)/pkgs unlisted" ] || { echo "$output"; false; }
}

@test "a root this run can write but no config lists is unlisted, and the probe leaves nothing" {
  spine_md '- External packages: /../pkgs/*'
  mkdir -p "$PROJ/../pkgs"
  chk_rest
  [ "$status" -eq 1 ]
  [ "$output" = "root $(cd "$PROJ/.." && pwd)/pkgs unlisted" ] || { echo "$output"; false; }
  [ -z "$(ls -A "$PROJ/../pkgs")" ] || { ls -A "$PROJ/../pkgs"; false; }
}

@test "a root that exists and this run cannot write is missing" {
  [ "$(id -u)" -ne 0 ] || skip "root writes anywhere"
  spine_md '- External packages: /../pkgs/*'
  mkdir -p "$PROJ/../pkgs"; chmod 555 "$PROJ/../pkgs"
  chk_rest
  chmod 755 "$PROJ/../pkgs"
  [ "$output" = "root $(cd "$PROJ/.." && pwd)/pkgs missing" ] || { echo "$output"; false; }
}

@test "a root not created yet under a folder this run can write is unlisted" {
  spine_md '- External packages: /../w/new/*'
  mkdir -p "$PROJ/../w"
  chk_rest
  [ "$output" = "root $(cd "$PROJ/.." && pwd)/w/new unlisted" ] || { echo "$output"; false; }
  [ -z "$(ls -A "$PROJ/../w")" ] || { ls -A "$PROJ/../w"; false; }
}

# Codex lays the project's config.toml over the user's, and an array replaces the one below it:
# a project that sets writable_roots at all makes the user's list void.
@test "the user's roots do not count once the project's config sets writable_roots" {
  [ "$(id -u)" -ne 0 ] || skip "root writes anywhere"
  spine_md '- External packages: /../pkgs/*'
  mkdir -p "$PROJ/../pkgs" "$PROJ/.codex"; chmod 555 "$PROJ/../pkgs"
  printf '[features]\ndefault_mode_request_user_input = true\n\n[sandbox_workspace_write]\nwritable_roots = ["%s"]\n' \
    "$(cd "$PROJ/.." && pwd)" >"$CH/config.toml"
  printf '[sandbox_workspace_write]\nwritable_roots = []\n' >"$PROJ/.codex/config.toml"
  chk_rest
  chmod 755 "$PROJ/../pkgs"
  [ "$output" = "root $(cd "$PROJ/.." && pwd)/pkgs missing" ] || { echo "$output"; false; }
}

@test "a ~/ root in the user's config covers what lies under it" {
  spine_md '- External packages: /../pkgs/*'
  mkdir -p "$BATS_TEST_TMPDIR/home"
  ln -s "$(cd "$PROJ/.." && pwd)" "$BATS_TEST_TMPDIR/home/work"
  printf '[features]\ndefault_mode_request_user_input = true\n\n[sandbox_workspace_write]\nwritable_roots = ["~/work"]\n' >"$CH/config.toml"
  rules_in_place
  HOME="$BATS_TEST_TMPDIR/home" run "$CP" check --project "$PROJ" --platform-root "$PLAT" --config-home "$CH"
  [ "$status" -eq 0 ] || { echo "$output"; false; }
}

@test "a relative entry in writable_roots covers nothing" {
  spine_md '- External packages: /../pkgs/*'
  mkdir -p "$PROJ/.codex"
  printf '[sandbox_workspace_write]\nwritable_roots = ["."]\n' >"$PROJ/.codex/config.toml"
  chk_rest
  [ "$output" = "root $(cd "$PROJ/.." && pwd)/pkgs unlisted" ] || { echo "$output"; false; }
}

@test "usage prints the whole usage block" {
  run "$CP"
  [ "$status" -eq 2 ]
  [[ "$output" == *'--config-home defaults to'* ]] || { echo "$output"; false; }
}

@test "apply writes an unlisted root like a missing one" {
  spine_md '- External packages: /../pkgs/*'
  mkdir -p "$PROJ/../pkgs"
  root="$(cd "$PROJ/.." && pwd)/pkgs"
  app "root $root unlisted"
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  grep -qF "\"$root\", # spine" "$PROJ/.codex/config.toml" || { cat "$PROJ/.codex/config.toml"; false; }
  chk_rest; [ "$status" -eq 0 ] || { echo "$output"; false; }
}

# --- final review of milestone 5 -----------------------------------------------------------------

# An unreadable or non-UTF-8 config is an error, not "items found": setup would ask with an empty
# list and the orchestrator would nag at every task start about something setup cannot fix.
@test "a config.toml that cannot be read is exit 2 with the reason, not exit 1" {
  printf 'model = "\xff"\n' >"$CH/config.toml"
  chk
  [ "$status" -eq 2 ] || { echo "status $status: $output"; false; }
  [[ "$output" == codex-permissions:* ]] || { echo "$output"; false; }
  [[ "$output" != *Traceback* ]] || { echo "$output"; false; }
}

@test "a project config that cannot be read is exit 2" {
  printf '## Paths\n- External packages: /\xff/*\n' >"$PROJ/SPINE.md"
  rules_in_place; menu_on
  chk
  [ "$status" -eq 2 ] || { echo "status $status: $output"; false; }
}

# A model may pass the path quoted, so the shell never expands the tilde.
@test "a --config-home with a literal tilde is read from the home folder" {
  rules_in_place
  mkdir -p "$BATS_TEST_TMPDIR/home/.codex"
  printf '[features]\ndefault_mode_request_user_input = true\n' >"$BATS_TEST_TMPDIR/home/.codex/config.toml"
  HOME="$BATS_TEST_TMPDIR/home" run "$CP" check --project "$PROJ" --platform-root "$PLAT" --config-home '~/.codex'
  [ "$status" -eq 0 ] || { echo "status $status: $output"; false; }
}

# features.x = … at the top level defines the table already: a [features] header after it makes
# config.toml invalid, and Codex then refuses the whole file.
@test "a top-level dotted key for a table apply would write is exit 2, and nothing is written" {
  printf 'model = "x"\nfeatures.other = true\n' >"$CH/config.toml"
  before="$(shasum "$CH/config.toml")"
  app 'menu off'
  [ "$status" -eq 2 ] || { echo "status $status: $output"; false; }
  [[ "$output" == *features* ]] || { echo "$output"; false; }
  [ "$(shasum "$CH/config.toml")" = "$before" ]
}

@test "a dotted key inside the [features] table does not block the menu" {
  printf '[features]\nx.y = true\n' >"$CH/config.toml"
  app 'menu off'
  [ "$status" -eq 0 ] || { echo "status $status: $output"; false; }
  grep -qx 'default_mode_request_user_input = true' "$CH/config.toml"
}

@test "apply keeps a CRLF config.toml CRLF and adds no final newline it did not have" {
  rules_in_place
  printf '[features]\r\nother = 1\r\n\r\n[x]\r\ny = 2' >"$CH/config.toml"
  app 'menu off'
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ "$(cat "$CH/config.toml")" = $'[features]\r\nother = 1\r\ndefault_mode_request_user_input = true\r\n\r\n[x]\r\ny = 2' ] \
    || { od -c "$CH/config.toml"; false; }
}

@test "a template apply cannot read leaves the project's rules file as it was" {
  rules_in_place; menu_on
  echo '# edited' >>"$PROJ/.codex/rules/spine-swift.rules"
  before="$(cat "$PROJ/.codex/rules/spine-swift.rules")"
  chmod 000 "$PLAT/runtimes/codex-cli/rules/swift.rules"
  app 'rules spine-swift.rules outdated'
  chmod 644 "$PLAT/runtimes/codex-cli/rules/swift.rules"
  [ "$status" -eq 2 ]
  [[ "$output" == *"cannot read"* ]] || { echo "$output"; false; }
  [ "$(cat "$PROJ/.codex/rules/spine-swift.rules")" = "$before" ]
}
