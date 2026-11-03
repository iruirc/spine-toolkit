#!/usr/bin/env bats
# The Russian AGENTS.md stub shipped with milestone 2 failed this lint, and nothing ran the lint, so
# it failed unseen until 2.29.0 was out. Running it here is what makes a new failure visible.

setup() {
  ROOT="$(cd -- "$(dirname -- "$BATS_TEST_FILENAME")/../../.." && pwd)"
  LINT="$ROOT/scripts/lint-i18n.sh"
}

@test "the toolkit tree passes the i18n lint" {
  run "$LINT"
  [ "$status" -eq 0 ] || { echo "$output"; return 1; }
}

@test "the Russian AGENTS.md stub is an allowed location" {
  grep -qF './templates/agents-md-stub/ru.md) continue' "$LINT"
}
