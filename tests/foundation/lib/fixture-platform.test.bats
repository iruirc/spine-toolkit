#!/usr/bin/env bats
# The fixture platform (core/tests/fixtures/fixture-platform) is the reference
# implementation of the platform manifest contract: these tests are the contract's
# executable spec, not just coverage for the fixture itself.

setup() {
  # BATS_TEST_FILENAME, not BASH_SOURCE[0]: bats sources a preprocessed copy of
  # the test file from a tmp dir, so BASH_SOURCE[0] there resolves to the copy.
  ROOT="$(cd -- "$(dirname -- "$BATS_TEST_FILENAME")/../../.." && pwd)"
  FIX="$ROOT/tests/fixtures/fixture-platform"
}

@test "fixture platform declares all five manifest tables" {
  for section in Roles Axes Heuristics Topics Entrypoints; do
    grep -q "^## $section\$" "$FIX/skills/manifest/SKILL.md"
  done
}

@test "fixture platform declares the setup entrypoint absent" {
  # Core resolves the platform half of installation through this row. The
  # fixture ships no setup skill, so its em dash is what exercises core's
  # `## Stack` left unset -> per-axis AUQ fallback; a row that silently went
  # missing would leave that branch untested and unspecified.
  grep -qE '^setup[[:space:]]*=[[:space:]]*—$' "$FIX/skills/manifest/SKILL.md"
}

@test "fixture platform maps every core role or declares it absent" {
  for role in architect developer tester reviewer refactorer validator security diagnostics init; do
    grep -qE "^${role}(\[[^]]+\])? *=" "$FIX/skills/manifest/SKILL.md"
  done
}

@test "every agent the fixture manifest names exists as a file" {
  while read -r agent; do
    name="${agent#fixture-platform:}"
    [ -f "$FIX/agents/${name}.md" ]
  done < <(grep -oE 'fixture-platform:[a-z-]+' "$FIX/skills/manifest/SKILL.md" | sort -u)
}
