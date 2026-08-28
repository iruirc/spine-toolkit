#!/usr/bin/env bats
# stack-detect keeps the resolution algorithm; every axis name, every value and
# every repo signal comes from the platform manifest. A platform word here means
# the catalog crept back in and core silently detects one ecosystem again.
#
# The last two guard the other half of that move: core's prose may only point at
# conventions core actually owns — the file this task deletes was referenced from
# core by a bare relative path the cross-plugin greps cannot see — and a profile's
# envelope may only say `all` or `[]`, since naming axes there re-hardcodes one
# platform's catalog and resolves nothing on every other one.

setup() {
  ROOT="$(cd -- "$(dirname -- "$BATS_TEST_FILENAME")/../../.." && pwd)"
  SD="$ROOT/skills/stack-detect/SKILL.md"
}

@test "stack-detect carries no platform vocabulary" {
  # word-anchored: bare `ios` also matches "scenarios", reddening the suite for
  # a word that has nothing to do with the catalog.
  run grep -icE '\b(swift|swiftui|uikit|appkit|combine|rxswift|swinject|xctest|ios|macos|xcdatamodeld)\b' "$SD"
  [ "$output" = "0" ]
}

@test "stack-detect declares ecosystem as the one mandatory axis" {
  grep -q 'ecosystem' "$SD"
}

@test "core references no conventions file it does not own" {
  missing=""
  for ref in $(grep -rhoE 'conventions/[A-Za-z0-9._-]+\.md' \
                 "$ROOT/skills" "$ROOT/conventions" "$ROOT/hooks" \
                 "$ROOT/workflows" "$ROOT/commands" "$ROOT/templates" | sort -u); do
    [ -f "$ROOT/$ref" ] || missing="$missing $ref"
  done
  [ -z "$missing" ] || { echo "dangling convention reference(s):$missing"; return 1; }
}

@test "no workflow envelope enumerates axes core does not own" {
  offenders="$(grep -h '^stack_axes_envelope:' "$ROOT/skills"/*/SKILL.md \
    | grep -vE '^stack_axes_envelope: \{ may: (all|\[\]), never: (all|\[\]) \}$' || true)"
  [ -z "$offenders" ] || { echo "envelope names an axis: $offenders"; return 1; }
}
