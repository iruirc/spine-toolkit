#!/usr/bin/env bash
# Checks a platform plugin's manifest skill against the spine-toolkit contract.
# Validates Roles, Axes, Heuristics presence and Roles content (vocabulary,
# named agents exist). Topics content is NOT checked here — a manifest may
# name topic skills that don't resolve within its own plugin as a teaching
# device (see core/tests/fixtures/fixture-platform); real platforms get their
# Topics checked by their own test suite.
# Usage: lint-manifest.sh <plugin-dir>
set -euo pipefail

plugin="${1:?usage: lint-manifest.sh <plugin-dir>}"
manifest="$plugin/skills/manifest/SKILL.md"
ROLES="architect developer tester reviewer refactorer validator security diagnostics init"
violations=0

[ -f "$manifest" ] || { echo "no manifest skill at $manifest"; exit 1; }

for section in Roles Axes Heuristics Topics; do
  grep -q "^## $section\$" "$manifest" || { echo "missing table: $section"; violations=$((violations+1)); }
done

roles_block=$(sed -n '/^## Roles/,/^## /p' "$manifest")

# Restrict parsing to actual "role[axis=value]? = value" lines, not the prose
# paragraph above the table — a wrapped continuation line can start with a
# lowercase word (e.g. "demonstrated below...") and a backticked example like
# `plugin:agent` in prose would otherwise be mistaken for a real reference.
assignments=$(grep -E '^[a-z][a-z-]*(\[[^]]+\])? *=' <<<"$roles_block")

for role in $ROLES; do
  grep -qE "^${role}(\[[^]]+\])? *=" <<<"$assignments" \
    || { echo "role not declared (map it or write '—'): $role"; violations=$((violations+1)); }
done

while read -r declared; do
  grep -qw "$declared" <<<"$ROLES" \
    || { echo "role outside the core vocabulary: $declared"; violations=$((violations+1)); }
done < <(grep -oE '^[a-z][a-z-]*' <<<"$assignments" | sort -u)

while read -r ref; do
  [ -f "$plugin/agents/${ref#*:}.md" ] \
    || { echo "manifest names an agent with no file: $ref"; violations=$((violations+1)); }
done < <(grep -oE '[a-z][a-z-]*:[a-z][a-z-]*' <<<"$assignments" | sort -u)

[ "$violations" -eq 0 ] || exit 1
echo "manifest OK: $plugin"
