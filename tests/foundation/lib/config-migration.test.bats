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

# --- The legacy config name: state G renames CLAUDE-spine-toolkit.md to SPINE.md on request ---

@test "the setup skill declares state G for the legacy config name" {
  grep -q '^| \*\*G · legacy_name\*\*' "$SKILL" || { echo "no state G row"; return 1; }
  grep -qF 'auq_migrate_spine_name' "$SKILL" || { echo "state G asks nothing"; return 1; }
}

@test "state G's question, options and both reports exist in both locales" {
  for k in auq_migrate_spine_name auq_migrate_spine_name_options report_spine_name_migrated report_spine_name_kept; do
    for l in en ru; do
      grep -qxF "## $k" "$ROOT/skills/setup/locales/$l.md" || { echo "$l lacks $k"; return 1; }
    done
  done
}

@test "every state that writes the config writes SPINE.md" {
  ! grep -qF 'Write to <project>/CLAUDE-spine-toolkit.md' "$SKILL" || { echo "a state still writes the legacy name"; return 1; }
  grep -qF 'Write to <project>/SPINE.md' "$SKILL" || { echo "no state writes SPINE.md"; return 1; }
  ! grep -qF 'Insert `@./CLAUDE-spine-toolkit.md`' "$SKILL" || { echo "a state still inserts the legacy import"; return 1; }
}

@test "an import line without its file routes to state A and leaves CLAUDE.md alone" {
  grep -qF '`@./SPINE.md` import line, but `SPINE.md` is absent: route to **state A**' "$SKILL"
}

@test "the rollback hint for state G is one mv and the import line" {
  grep -qF 'mv SPINE.md CLAUDE-spine-toolkit.md' "$SKILL"
}

@test "the setup locales no longer name the legacy file except in state G's own texts" {
  for l in en ru; do
    offenders="$(awk '/^## /{k=$2} /CLAUDE-spine-toolkit/ && k !~ /spine_name/ {print k}' "$ROOT/skills/setup/locales/$l.md" | sort -u)"
    [ -z "$offenders" ] || { echo "$l: legacy name under $offenders"; return 1; }
  done
}

@test "state G asks nothing before its own question and stops after its report" {
  grep -qF 'state G → the config already carries the language' "$SKILL" || { echo "step 0 still asks state G the language"; return 1; }
  grep -qF 'state G → the config already names the platform' "$SKILL" || { echo "step 1 still runs discovery for state G"; return 1; }
  g="$(awk '/^   STATE G \(legacy_name\):/{f=1;next} f&&/^   STATE |^5\. /{exit} f' "$SKILL")"
  grep -qF 'Stop.' <<<"$g" || { echo "state G does not stop after its report"; return 1; }
  ! grep -qF 'step 6b still run' <<<"$g" || { echo "state G still runs the platform half"; return 1; }
  grep -qF 'carries `@./SPINE.md`, in which case leave it alone' <<<"$g" || { echo "state G may insert a second import"; return 1; }
  grep -qF 'Keep the old name' <<<"$g" && grep -qF 'stub' <<<"$g" || { echo "Keep with no CLAUDE.md does not create the stub"; return 1; }
}

@test "a legacy import line whose file is absent is rewritten when state A writes SPINE.md" {
  grep -qF 'rewrite that line to `@./SPINE.md` once `SPINE.md` is written' "$SKILL"
}

@test "state F keeps the source file name and leaves the rename to state G" {
  f="$(awk '/^   STATE F \(old_block_format\):/{f=1;next} f&&/^   STATE /{exit} f' "$SKILL")"
  grep -qF 'under the name it had' <<<"$f" || { echo "F does not say it keeps the source name"; return 1; }
  ! grep -qF 'removed' <<<"$f" || { echo "F still removes the legacy file"; return 1; }
  grep -qF '{config_name}' "$SKILL" || { echo "the F report has no {config_name} placeholder"; return 1; }
  for l in en ru; do grep -qF 'mv {backup_path} {config_name}' "$ROOT/skills/setup/locales/$l.md" || { echo "$l rollback hint is hard-coded"; return 1; }; done
}

@test "the state table, safeguards and report table all know state G" {
  grep -qF 'All five checks are file reads' "$SKILL"
  grep -qF 'routes to C, not D or E — to G while the file still carries the legacy name' "$SKILL"
  grep -qF 'State G → key `report_spine_name_migrated`' "$SKILL"
}
