#!/usr/bin/env bash
# Checks a platform plugin's manifest skill against the spine-toolkit contract.
# Validates the five tables' presence, Roles content (vocabulary, named agents
# exist) and Entrypoints content (a named skill exists). Topics content is NOT
# checked here — a manifest may name topic skills that don't resolve within its
# own plugin as a teaching device (see core/tests/fixtures/fixture-platform);
# real platforms get their Topics checked by their own test suite. Entrypoints
# is checked because core calls it by name at install time, where a typo is
# indistinguishable from the legitimate '—' and surfaces only after the config
# is already written.
# Usage: lint-manifest.sh <plugin-dir>
set -euo pipefail

plugin="${1:?usage: lint-manifest.sh <plugin-dir>}"
manifest="$plugin/skills/manifest/SKILL.md"
ROLES="architect developer tester reviewer refactorer validator security diagnostics init"
violations=0

[ -f "$manifest" ] || { echo "no manifest skill at $manifest"; exit 1; }

for section in Roles Axes Heuristics Topics Entrypoints; do
  grep -q "^## $section\$" "$manifest" || { echo "missing table: $section"; violations=$((violations+1)); }
done

roles_block=$(sed -n '/^## Roles/,/^## /p' "$manifest")

# Restrict parsing to actual "role[axis=value]? = value" lines, not the prose
# paragraph above the table — a wrapped continuation line can start with a
# lowercase word (e.g. "demonstrated below...") and a backticked example like
# `plugin:agent` in prose would otherwise be mistaken for a real reference.
# `[[:space:]]*`, not literal spaces, so tab-aligned tables parse too.
# `|| true`: grep exits 1 on zero matches (an emptied Roles table), which
# would otherwise abort the whole script here under `set -e`, before a
# single role gets reported missing.
assignments=$(grep -E '^[a-z][a-z-]*(\[[^]]+\])?[[:space:]]*=' <<<"$roles_block" || true)

for role in $ROLES; do
  grep -qE "^${role}(\[[^]]+\])?[[:space:]]*=" <<<"$assignments" \
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

# A role line's RHS must be an em-dash (declared absent) or a plugin:agent
# reference — not empty. `role =` with nothing after it is neither a mapping
# nor an explicit absence; the two are indistinguishable to core at runtime,
# so this is the only place the difference can be caught.
while IFS= read -r line; do
  [[ "$line" =~ ^([a-z][a-z-]*)(\[[^]]+\])?[[:space:]]*=[[:space:]]*(.*)$ ]] || continue
  role_name="${BASH_REMATCH[1]}"
  rhs="${BASH_REMATCH[3]}"
  rhs="${rhs%"${rhs##*[![:space:]]}"}"  # trim trailing whitespace
  case "$rhs" in
    "—") ;;
    *)
      if [[ "$rhs" =~ ^[a-z][a-z-]*:[a-z][a-z-]*$ ]]; then
        :
      elif [ -z "$rhs" ]; then
        echo "role mapped to an empty value (write a plugin:agent reference or '—'): $role_name"
        violations=$((violations+1))
      else
        echo "role mapped to a malformed value '$rhs' (expected plugin:agent or '—'): $role_name"
        violations=$((violations+1))
      fi
      ;;
  esac
done <<<"$assignments"

# Entrypoints: `name = `skill`` or `name = —`. The skill is this plugin's own,
# so it must resolve to skills/<name>/SKILL.md here. Same window discipline as
# Roles — assignment lines only, so the prose above the table cannot pollute it.
# `,/^## /p`, not `,$p`: bounded like the Roles window above. `## Axes` rows share the
# `name = value` grammar, so an unbounded window would read every axis as a malformed
# entrypoint the moment this table stops being last. Still runs to EOF while it is.
entry_block=$(sed -n '/^## Entrypoints/,/^## /p' "$manifest")
entries=$(grep -E '^[a-z][a-z-]*[[:space:]]*=' <<<"$entry_block" || true)

while IFS= read -r line; do
  [ -n "$line" ] || continue
  [[ "$line" =~ ^([a-z][a-z-]*)[[:space:]]*=[[:space:]]*(.*)$ ]] || continue
  entry_name="${BASH_REMATCH[1]}"
  rhs="${BASH_REMATCH[2]}"
  rhs="${rhs%"${rhs##*[![:space:]]}"}"  # trim trailing whitespace
  case "$rhs" in
    "—") ;;
    '`'*'`')
      skill="${rhs//\`/}"
      [ -f "$plugin/skills/$skill/SKILL.md" ] \
        || { echo "entrypoint names a skill with no SKILL.md: $entry_name = $skill"; violations=$((violations+1)); }
      ;;
    *)
      echo "entrypoint mapped to a malformed value '$rhs' (expected \`skill\` or '—'): $entry_name"
      violations=$((violations+1))
      ;;
  esac
done <<<"$entries"

[ "$violations" -eq 0 ] || exit 1
echo "manifest OK: $plugin"
