#!/usr/bin/env bats
# A 1.x config is migrated key by key. The mapping is the whole contract: a key that maps to the
# wrong field writes a project's own choice into the wrong setting, silently.

setup() { ROOT="$(cd -- "$(dirname -- "$BATS_TEST_FILENAME")/../../.." && pwd)"; SKILL="$ROOT/skills/setup/SKILL.md"; }

@test "the setup skill declares a state for a 1.x config" {
  grep -qF 'old_block_format' "$SKILL" || { echo "no state for the 1.x format"; return 1; }
  grep -qF 'without asking' "$SKILL" || { echo "the state does not say it asks nothing"; return 1; }
}

@test "the migration maps every moved key to its field" {
  for pair in 'Language:[LANG]' 'Mode:[WORKFLOW_MODE]' 'Progress:[PROGRESS]' 'settings:[SETTINGS_REPORT]' \
              'Scale:[SCALE]' 'walkthrough:[WALKTHROUGH]' 'drive_app:[DRIVE_APP]' 'manual_checks:[MANUAL_CHECKS]' \
              'driver:[DRIVER]' 'phase_verification:[PHASE_VERIFICATION]' 'enabled:[DOCS]' 'map:[DOCS_MAP]' \
              'strictness:[DOCS_STRICTNESS]' 'freshness:[DOCS_FRESHNESS]' 'Budgets:[BUDGETS]' \
              'Models:[MODELS]' 'Effort:[EFFORT]'; do
    old="${pair%%:*}"; new="${pair#*:}"
    command grep -qF "$old" "$SKILL" && command grep -qF "$new" "$SKILL" \
      || { echo "the mapping table lacks $old -> $new"; return 1; }
  done
}

# The rows of the block-to-field mapping: from the first `|` line after its heading to the first
# line that is not one.
mapping_rows() {
  awk '/^### Block-to-field mapping$/ {f = 1; next}
       f && /^\|/ {seen = 1; print; next}
       f && seen {exit}' "$SKILL"
}

# The grep above is file-wide and per-term, so a table with two rows swapped passes it, and a bare
# `map` or `driver` is satisfied by ordinary prose anywhere in the file. This reads the table. The
# pair list is spelled a second time on purpose: one shared copy would let a single edit move both
# tests together, and the mapping is the thing they exist to hold still.
@test "each mapped key reaches its field on a row of its own" {
  bt='`'
  rows="$(mapping_rows)"
  [ "$(printf '%s\n' "$rows" | wc -l)" -ge 19 ] || { echo "the mapping table did not parse"; return 1; }
  for pair in 'Language:[LANG]' 'Mode:[WORKFLOW_MODE]' 'Progress:[PROGRESS]' 'settings:[SETTINGS_REPORT]' \
              'Scale:[SCALE]' 'walkthrough:[WALKTHROUGH]' 'drive_app:[DRIVE_APP]' 'manual_checks:[MANUAL_CHECKS]' \
              'driver:[DRIVER]' 'phase_verification:[PHASE_VERIFICATION]' 'enabled:[DOCS]' 'map:[DOCS_MAP]' \
              'strictness:[DOCS_STRICTNESS]' 'freshness:[DOCS_FRESHNESS]' 'Budgets:[BUDGETS]' \
              'Models:[MODELS]' 'Effort:[EFFORT]'; do
    old="${pair%%:*}"; new="${pair#*:}"
    n="$(printf '%s\n' "$rows" | awk -F'|' -v old="$bt$old$bt" -v new="$bt$new$bt" '
           { for (i = 2; i <= 4; i++) gsub(/^[[:space:]]+|[[:space:]]+$/, "", $i) }
           ($2 == old || $3 == old) && $4 == new { c++ }
           END { print c + 0 }')"
    [ "$n" -eq 1 ] || { echo "$old -> $new is on $n row(s) of the table, expected 1"; return 1; }
  done
}

@test "a key the old file did not carry is written at its default, not asked about" {
  grep -qF 'filled_default_fields' "$SKILL" || { echo "nothing reports what was defaulted"; return 1; }
}

@test "the migration report exists in both locales" {
  for l in en ru; do
    grep -qxF '## report_block_migration' "$ROOT/skills/setup/locales/$l.md" \
      || { echo "$l.md lacks report_block_migration"; return 1; }
  done
}
