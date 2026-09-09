#!/usr/bin/env bats
# lint-driver-manifest.sh validates a driver manifest against the driver contract:
# required blocks, one well-formed namespace, targets and capability blocks that
# cover each other exactly, capabilities inside the vocabulary, and an object-form
# dependency on core. The reference fixture is the only manifest core's own suite
# runs this against — a real driver runs it from its own suite.

setup() {
  ROOT="$(cd -- "$(dirname -- "$BATS_TEST_FILENAME")/../../.." && pwd)"
  LINT="$ROOT/scripts/lint-driver-manifest.sh"
  TMP="$(mktemp -d)"
  cp -R "$ROOT/tests/fixtures/fixture-driver" "$TMP/d"
  M="$TMP/d/skills/manifest/SKILL.md"
}

teardown() { rm -rf "$TMP"; }

@test "passes on the fixture driver" {
  run "$LINT" "$TMP/d"
  [ "$status" -eq 0 ]
  [[ "$output" == *"driver manifest OK"* ]]
}

@test "exits 2 without an argument" {
  run "$LINT"
  [ "$status" -eq 2 ]
}

@test "fails when the manifest is missing" {
  rm -f "$M"
  run "$LINT" "$TMP/d"
  [ "$status" -eq 1 ]
  [[ "$output" == *"no manifest skill"* ]]
}

@test "fails when the Driver block is missing" {
  sed -i.bak '/^## Driver$/d' "$M" && rm -f "$M.bak"
  run "$LINT" "$TMP/d"
  [ "$status" -eq 1 ]
  [[ "$output" == *"Driver"* ]]
}

@test "fails when namespace is absent" {
  sed -i.bak '/^namespace[[:space:]]*=/d' "$M" && rm -f "$M.bak"
  run "$LINT" "$TMP/d"
  [ "$status" -eq 1 ]
  [[ "$output" == *"namespace"* ]]
}

@test "fails when namespace is declared twice" {
  awk '{ print } /^namespace/{ print "namespace = second" }' "$M" > "$M.new" && mv "$M.new" "$M"
  run "$LINT" "$TMP/d"
  [ "$status" -eq 1 ]
  [[ "$output" == *"namespace"* ]]
}

@test "fails when namespace is malformed" {
  sed -i.bak 's/^namespace = neutral/namespace = 9Neutral!/' "$M" && rm -f "$M.bak"
  run "$LINT" "$TMP/d"
  [ "$status" -eq 1 ]
  [[ "$output" == *"malformed"* ]]
}

@test "prose inside a block is not read as a row" {
  # The fixture's ## Targets prose wraps onto a line that starts with a lowercase word.
  # An unanchored parser reports it as a malformed row, and the lint then rejects the
  # very manifest it is the copy of.
  grep -q '^what the device has in hardware' "$M" \
    || { echo "the fixture's wrapped prose line moved; this test guards nothing now"; return 1; }
  run "$LINT" "$TMP/d"
  [ "$status" -eq 0 ]
}

@test "fails when a capabilities block names an undeclared target" {
  sed -i.bak 's/^## Capabilities: android-device$/## Capabilities: gamma-tv/' "$M" && rm -f "$M.bak"
  run "$LINT" "$TMP/d"
  [ "$status" -eq 1 ]
  [[ "$output" == *"gamma-tv"* ]]
}

@test "fails when a declared target has no capabilities block" {
  # The target row stays; its block is what goes. A target that declares nothing
  # is indistinguishable at runtime from one that supports nothing.
  awk '/^## Capabilities: android-device$/{skip=1} /^## Procedure$/{skip=0} !skip' "$M" > "$M.new" && mv "$M.new" "$M"
  run "$LINT" "$TMP/d"
  [ "$status" -eq 1 ]
  [[ "$output" == *"android-device"* ]]
}

@test "fails when a capability is outside the vocabulary" {
  sed -i.bak 's/^launch stop install reset_state$/launch stop install teleport/' "$M" && rm -f "$M.bak"
  run "$LINT" "$TMP/d"
  [ "$status" -eq 1 ]
  [[ "$output" == *"teleport"* ]]
}

@test "fails when a target is declared twice" {
  awk '{ print } /^android-device$/{ print "android-device" }' "$M" > "$M.new" && mv "$M.new" "$M"
  run "$LINT" "$TMP/d"
  [ "$status" -eq 1 ]
  [[ "$output" == *"android-device"* ]]
}

@test "accepts a namespace list" {
  # The fixture ships a list; this asserts the grammar rather than the fixture.
  sed -i.bak 's/^namespace = .*/namespace = alpha, beta, gamma/' "$M" && rm -f "$M.bak"
  run "$LINT" "$TMP/d"
  [ "$status" -eq 0 ]
}

@test "fails when a namespace list repeats a name" {
  sed -i.bak 's/^namespace = .*/namespace = alpha, alpha/' "$M" && rm -f "$M.bak"
  run "$LINT" "$TMP/d"
  [ "$status" -eq 1 ]
  [[ "$output" == *"alpha"* ]]
}

@test "fails when a namespace list has an empty element" {
  sed -i.bak 's/^namespace = .*/namespace = alpha, , beta/' "$M" && rm -f "$M.bak"
  run "$LINT" "$TMP/d"
  [ "$status" -eq 1 ]
  [[ "$output" == *"namespace"* ]]
}

@test "fails when a target is not a known surface" {
  sed -i.bak 's/^android-emulator$/toaster/' "$M" && rm -f "$M.bak"
  run "$LINT" "$TMP/d"
  [ "$status" -eq 1 ]
  [[ "$output" == *"toaster"* ]]
}

@test "fails when a target row carries a right-hand side" {
  # The old grammar was `target = ecosystem`. A manifest written against it must be
  # rejected loudly rather than half-read, or its author debugs a silent mismatch.
  sed -i.bak 's/^android-emulator$/android-emulator = fixture/' "$M" && rm -f "$M.bak"
  run "$LINT" "$TMP/d"
  [ "$status" -eq 1 ]
  [[ "$output" == *"android-emulator"* ]]
}

@test "fails when the core dependency uses the string form" {
  python3 - "$TMP/d/.claude-plugin/plugin.json" <<'PY'
import json, sys
p = sys.argv[1]
d = json.load(open(p))
d["dependencies"] = ["spine-toolkit"]
json.dump(d, open(p, "w"), indent=2)
PY
  run "$LINT" "$TMP/d"
  [ "$status" -eq 1 ]
  [[ "$output" == *"dependenc"* ]]
}

@test "fails when plugin.json has no name" {
  python3 - "$TMP/d/.claude-plugin/plugin.json" <<'PY'
import json, sys
p = sys.argv[1]
d = json.load(open(p))
del d["name"]
json.dump(d, open(p, "w"), indent=2)
PY
  run "$LINT" "$TMP/d"
  [ "$status" -eq 1 ]
  [[ "$output" == *"name"* ]]
}
