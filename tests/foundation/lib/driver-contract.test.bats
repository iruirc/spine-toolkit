#!/usr/bin/env bats
# The driver contract is prose, and prose drifts from the lint that enforces it.
# These tests bind the two: the vocabulary the convention prints is the vocabulary
# the lint accepts, and the fixture is a document that obeys both. Without this the
# three copies diverge silently and the first symptom is a legal driver rejected.

setup() {
  ROOT="$(cd -- "$(dirname -- "$BATS_TEST_FILENAME")/../../.." && pwd)"
  DOC="$ROOT/conventions/driver-contract.md"
}

# The 32 capabilities, in the six groups the convention declares. Written out here
# rather than parsed from the doc: a test that reads its subject cannot catch the
# subject losing a line.
ALL_CAPS="launch stop install reset_state
ui_tree find assert screenshot video logs
tap type swipe gesture key
deeplink background permissions alerts push biometrics camera location network_conditions viewport locale webview
a11y_audit visual_baseline performance
record_replay multi_device"

@test "the convention exists" {
  [ -f "$DOC" ]
}

@test "the convention names every capability of the vocabulary" {
  missing=""
  for cap in $ALL_CAPS; do
    grep -qF "\`$cap\`" "$DOC" || missing="$missing $cap"
  done
  [ -z "$missing" ] || { echo "capabilities the convention does not name:$missing"; return 1; }
}

@test "the convention declares exactly 32 capabilities and no more" {
  # Counted from the vocabulary block alone, not the whole document: the prose
  # below it legitimately mentions capability names while explaining them.
  n="$(sed -n '/^<!-- vocabulary:start -->$/,/^<!-- vocabulary:end -->$/p' "$DOC" \
       | grep -oE '`[a-z][a-z0-9_]*`' | sort -u | wc -l | tr -d ' ')"
  [ "$n" -eq 32 ] || { echo "vocabulary block holds $n capabilities, expected 32"; return 1; }
}

@test "the convention names all four blocks of a driver manifest" {
  for block in "## Driver" "## Targets" "## Capabilities:" "## Procedure"; do
    grep -qF "$block" "$DOC" || { echo "block not documented: $block"; return 1; }
  done
}

@test "the convention names all four driver states" {
  for state in ok none unavailable incompatible; do
    grep -qF "\`$state\`" "$DOC" || { echo "state not documented: $state"; return 1; }
  done
}

@test "the convention names no real MCP server" {
  # dispatch-vocabulary.test.bats scans conventions/*.md for the retired tool name
  # already; this catches the two servers that motivated the contract, which that
  # guard does not know about.
  hits="$(grep -ioE 'agent-device|claude-in-mobile|mcp__[a-z_]+' "$DOC" | sort -u | tr '\n' ' ')"
  [ -z "$hits" ] || { echo "the convention names a concrete server: $hits"; return 1; }
}
