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

@test "a key the old file did not carry is written at its default, not asked about" {
  grep -qF 'filled_default_fields' "$SKILL" || { echo "nothing reports what was defaulted"; return 1; }
}

@test "the migration report exists in both locales" {
  for l in en ru; do
    grep -qxF '## report_block_migration' "$ROOT/skills/setup/locales/$l.md" \
      || { echo "$l.md lacks report_block_migration"; return 1; }
  done
}
