#!/usr/bin/env bats
# lint-manifest.sh validates a platform manifest against the spine-toolkit
# contract: the five tables present, every core role mapped or declared absent,
# roles stay inside the core vocabulary, every named agent has a file, and an
# Entrypoints skill other than '—' resolves. Topics content is deliberately not
# checked (see the script's header comment).

setup() {
  # BATS_TEST_FILENAME, not BASH_SOURCE[0]: bats sources a preprocessed copy of
  # the test file from a tmp dir, so BASH_SOURCE[0] there resolves to the copy.
  ROOT="$(cd -- "$(dirname -- "$BATS_TEST_FILENAME")/../../.." && pwd)"
  LINT="$ROOT/scripts/lint-manifest.sh"
  TMP="$(mktemp -d)"
  cp -R "$ROOT/tests/fixtures/fixture-platform" "$TMP/p"
}

teardown() { rm -rf "$TMP"; }

@test "passes on the fixture platform" {
  run "$LINT" "$TMP/p"
  [ "$status" -eq 0 ]
}

@test "passes on the real swift-platform manifest" {
  run "$LINT" "$ROOT/../platform"
  [ "$status" -eq 0 ]
}

@test "fails when a table is missing" {
  sed -i.bak '/^## Topics$/d' "$TMP/p/skills/manifest/SKILL.md" && rm -f "$TMP/p/skills/manifest/SKILL.md.bak"
  run "$LINT" "$TMP/p"
  [ "$status" -eq 1 ]
  [[ "$output" == *"Topics"* ]]
}

@test "fails when a role is outside the core vocabulary" {
  # Insert inside the Roles table, not at EOF: the lint only scans the
  # "## Roles" .. "## Axes" window, so a line appended past "## Topics"
  # would never be seen — this would test nothing.
  awk '{ print } /^architect /{ print "plumber = fixture-platform:fixture-developer" }' \
    "$TMP/p/skills/manifest/SKILL.md" > "$TMP/p/skills/manifest/SKILL.md.new"
  mv "$TMP/p/skills/manifest/SKILL.md.new" "$TMP/p/skills/manifest/SKILL.md"
  run "$LINT" "$TMP/p"
  [ "$status" -eq 1 ]
  [[ "$output" == *"plumber"* ]]
}

@test "fails when a named agent has no file" {
  sed -i.bak 's|fixture-platform:fixture-architect|fixture-platform:ghost|' "$TMP/p/skills/manifest/SKILL.md" && rm -f "$TMP/p/skills/manifest/SKILL.md.bak"
  run "$LINT" "$TMP/p"
  [ "$status" -eq 1 ]
  [[ "$output" == *"ghost"* ]]
}

@test "fails when a required role is not declared at all" {
  sed -i.bak '/^validator /d' "$TMP/p/skills/manifest/SKILL.md" && rm -f "$TMP/p/skills/manifest/SKILL.md.bak"
  run "$LINT" "$TMP/p"
  [ "$status" -eq 1 ]
  [[ "$output" == *"validator"* ]]
}

@test "no manifest skill fails with a clear message" {
  rm -rf "$TMP/p/skills/manifest"
  run "$LINT" "$TMP/p"
  [ "$status" -eq 1 ]
  [[ "$output" == *"no manifest skill"* ]]
}

@test "fails when a role is mapped to an empty value" {
  # "role =" with nothing after it is neither a mapping nor an explicit '—':
  # core can't tell it apart from either at runtime, so the lint must.
  sed -i.bak 's|^validator               = —|validator               = |' "$TMP/p/skills/manifest/SKILL.md" \
    && rm -f "$TMP/p/skills/manifest/SKILL.md.bak"
  run "$LINT" "$TMP/p"
  [ "$status" -eq 1 ]
  [[ "$output" == *"validator"* ]]
}

@test "fails per role, not silently, when the Roles table has no assignment lines" {
  # Emptying the table (heading and prose intact, every role line gone) must
  # not abort the script before it reports anything — each missing role
  # should still surface as its own violation.
  sed -i.bak '/^architect /,/^init /d' "$TMP/p/skills/manifest/SKILL.md" \
    && rm -f "$TMP/p/skills/manifest/SKILL.md.bak"
  run "$LINT" "$TMP/p"
  [ "$status" -eq 1 ]
  [ -n "$output" ]
  [[ "$output" == *"architect"* ]]
  [[ "$output" == *"init"* ]]
}

@test "passes when the Roles table is tab-aligned instead of space-aligned" {
  perl -i -pe 's/^architect\s+=/architect\t=\t/' "$TMP/p/skills/manifest/SKILL.md"
  run "$LINT" "$TMP/p"
  [ "$status" -eq 0 ]
}

@test "fails when an entrypoint names a skill with no SKILL.md" {
  # Core calls this one by name at install time, after the config is on disk:
  # a typo there is indistinguishable from the legitimate '—' at runtime, so
  # conformance is the only place it can be caught.
  sed -i.bak 's|^setup = —|setup = `fixture-setpu`|' "$TMP/p/skills/manifest/SKILL.md" \
    && rm -f "$TMP/p/skills/manifest/SKILL.md.bak"
  run "$LINT" "$TMP/p"
  [ "$status" -eq 1 ]
  [[ "$output" == *"fixture-setpu"* ]]
}

@test "fails when an entrypoint is mapped to an empty value" {
  sed -i.bak 's|^setup = —|setup = |' "$TMP/p/skills/manifest/SKILL.md" \
    && rm -f "$TMP/p/skills/manifest/SKILL.md.bak"
  run "$LINT" "$TMP/p"
  [ "$status" -eq 1 ]
  [[ "$output" == *"setup"* ]]
}
