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

@test "fails when a namespaced reference names a skill core does not have" {
  sed -i.bak 's|spine-toolkit:ops-checklist|spine-toolkit:ops-checklists|' \
    "$TMP/p/agents/fixture-architect.md" && rm -f "$TMP/p/agents/fixture-architect.md.bak"
  run "$LINT" "$TMP/p" --core "$ROOT"
  [ "$status" -eq 1 ]
  [[ "$output" == *"ops-checklists"* ]]
  [[ "$output" == *"does not exist"* ]]
}

@test "the violation names the file and the line" {
  sed -i.bak 's|spine-toolkit:ops-checklist|spine-toolkit:ghost-skill|' \
    "$TMP/p/agents/fixture-architect.md" && rm -f "$TMP/p/agents/fixture-architect.md.bak"
  run "$LINT" "$TMP/p" --core "$ROOT"
  [ "$status" -eq 1 ]
  [[ "$output" == *"agents/fixture-architect.md:"* ]]
}

@test "reads a reference outside backticks too" {
  # Frontmatter descriptions carry real references: swift-setup names
  # spine-toolkit:setup there, and it has to resolve like any other.
  printf '\nPlain prose naming spine-toolkit:ghost-skill without backticks.\n' \
    >> "$TMP/p/agents/fixture-architect.md"
  run "$LINT" "$TMP/p" --core "$ROOT"
  [ "$status" -eq 1 ]
  [[ "$output" == *"ghost-skill"* ]]
}

@test "a skill that exists only after the floor is a violation" {
  # The failure this whole check exists for: the platform starts using a skill
  # core gained later and leaves the floor where it was.
  sed -i.bak 's|">=1.3.0 <2"|">=1.0.0 <2"|' "$TMP/p/.claude-plugin/plugin.json" \
    && rm -f "$TMP/p/.claude-plugin/plugin.json.bak"
  sed -i.bak 's|spine-toolkit:ops-checklist|spine-toolkit:manual-checks|' \
    "$TMP/p/agents/fixture-architect.md" && rm -f "$TMP/p/agents/fixture-architect.md.bak"
  run "$LINT" "$TMP/p" --core "$ROOT" --ref 1.0.0
  [ "$status" -eq 1 ]
  [[ "$output" == *"manual-checks"* ]]
}

@test "the declared floor alone, with no --ref, is what a violation is measured against" {
  # The failure D-3 names outright: the platform starts using a skill core
  # gained later and leaves its own floor where it was. Nothing passes --ref
  # here, so the floor in plugin.json is the only thing driving the check.
  sed -i.bak 's|">=1.3.0 <2"|">=1.0.0 <2"|' "$TMP/p/.claude-plugin/plugin.json" \
    && rm -f "$TMP/p/.claude-plugin/plugin.json.bak"
  sed -i.bak 's|spine-toolkit:ops-checklist|spine-toolkit:manual-checks|' \
    "$TMP/p/agents/fixture-architect.md" && rm -f "$TMP/p/agents/fixture-architect.md.bak"
  run "$LINT" "$TMP/p" --core "$ROOT"
  [ "$status" -eq 1 ]
  [[ "$output" == *"manual-checks"* ]]
  [[ "$output" == *"spine-toolkit 1.0.0"* ]]
}

@test "fails when a hyphenated core skill is named bare in backticks" {
  sed -i.bak 's|`spine-toolkit:ops-checklist`|`ops-checklist`|' \
    "$TMP/p/agents/fixture-architect.md" && rm -f "$TMP/p/agents/fixture-architect.md.bak"
  run "$LINT" "$TMP/p" --core "$ROOT"
  [ "$status" -eq 1 ]
  [[ "$output" == *"bare"* ]]
  [[ "$output" == *"ops-checklist"* ]]
}

@test "a single-word core skill name stays legal bare" {
  # `lang` is a dispatch-contract field and `setup` an Entrypoints row name.
  # Core's own vocabulary is single-word and legitimately bare; flagging it
  # would make the lint wrong 11 times over on the real platform.
  printf '\nThe `lang` field and the `setup` row are core vocabulary, not references.\n' \
    >> "$TMP/p/agents/fixture-architect.md"
  run "$LINT" "$TMP/p" --core "$ROOT"
  [ "$status" -eq 0 ]
}

@test "the namespaced form is not mistaken for a bare one" {
  run "$LINT" "$TMP/p" --core "$ROOT"
  [ "$status" -eq 0 ]
  [[ "$output" != *"bare"* ]]
}

@test "a hyphenated name that is not a core skill is left alone" {
  printf '\nThe package `swift-openapi-generator` is not a core skill.\n' \
    >> "$TMP/p/agents/fixture-architect.md"
  run "$LINT" "$TMP/p" --core "$ROOT"
  [ "$status" -eq 0 ]
}

@test "an explicitly passed --ref that resolves nowhere is exit 2" {
  # A caller who asked for an exact check and typo'd the ref must not be handed
  # a degraded one under a success exit code.
  run "$LINT" "$TMP/p" --core "$ROOT" --ref no-such-thing
  [ "$status" -eq 2 ]
  [[ "$output" == *"no-such-thing does not resolve"* ]]
}

@test "--ref takes any committish, not only a tag" {
  run "$LINT" "$TMP/p" --core "$ROOT" --ref HEAD
  [ "$status" -eq 0 ]
  [[ "$output" == *"spine-toolkit HEAD"* ]]
}
