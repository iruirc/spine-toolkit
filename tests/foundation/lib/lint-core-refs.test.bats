#!/usr/bin/env bats
# lint-core-refs.sh checks that every core skill a platform names exists in the
# oldest core its dependency range admits, and that hyphenated core skill names
# are written in the namespaced form. The version floor comes from the
# platform's own plugin.json; the reference fixture is the only platform core's
# own suite runs this against.

setup() {
  ROOT="$(cd -- "$(dirname -- "$BATS_TEST_FILENAME")/../../.." && pwd)"
  LINT="$ROOT/scripts/lint-core-refs.sh"
  TMP="$(mktemp -d)"
  cp -R "$ROOT/tests/fixtures/fixture-platform" "$TMP/p"
}

teardown() { rm -rf "$TMP"; }

@test "passes on the fixture platform" {
  run "$LINT" "$TMP/p" --core "$ROOT"
  [ "$status" -eq 0 ]
}

@test "exits 2 without --core" {
  run "$LINT" "$TMP/p"
  [ "$status" -eq 2 ]
  [[ "$output" == *"--core is required"* ]]
}

@test "exits 2 on an unknown option" {
  run "$LINT" "$TMP/p" --core "$ROOT" --frobnicate
  [ "$status" -eq 2 ]
}

@test "names the exact floor tag when core is a checkout" {
  run "$LINT" "$TMP/p" --core "$ROOT"
  [ "$status" -eq 0 ]
  [[ "$output" == *"spine-toolkit 1.3.0"* ]]
}

@test "degrades to the directory as it sits when core is not a checkout" {
  # A platform author holding the installed plugin and no checkout still gets a
  # check — just not one against the floor, and the output says so rather than
  # letting the run read as a clean pass against the right version.
  mkdir -p "$TMP/core/.claude-plugin"
  cp -R "$ROOT/skills" "$TMP/core/skills"
  cp "$ROOT/.claude-plugin/plugin.json" "$TMP/core/.claude-plugin/plugin.json"
  run "$LINT" "$TMP/p" --core "$TMP/core"
  [ "$status" -eq 0 ]
  [[ "$output" == *"NOT the declared floor"* ]]
}

@test "fails when the dependency is declared as a bare string" {
  cat > "$TMP/p/.claude-plugin/plugin.json" <<'JSON'
{
  "name": "fixture-platform",
  "description": "Test double.",
  "version": "0.1.0",
  "dependencies": ["spine-toolkit"]
}
JSON
  run "$LINT" "$TMP/p" --core "$ROOT"
  [ "$status" -eq 1 ]
  [[ "$output" == *"no version floor"* ]]
}

@test "fails when there is no dependency on core at all" {
  cat > "$TMP/p/.claude-plugin/plugin.json" <<'JSON'
{
  "name": "fixture-platform",
  "description": "Test double.",
  "version": "0.1.0"
}
JSON
  run "$LINT" "$TMP/p" --core "$ROOT"
  [ "$status" -eq 1 ]
  [[ "$output" == *"no version floor"* ]]
}
