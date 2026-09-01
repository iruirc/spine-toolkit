#!/usr/bin/env bash
set -euo pipefail

# Paths below are repo-relative: anchor the cwd so a run from elsewhere
# cannot scan the wrong tree and report a pass.
cd "$(dirname "$0")/.."

violations=0
for en in skills/*/locales/en.md; do
  dir=$(dirname "$en")
  ru="$dir/ru.md"
  if [ ! -f "$ru" ]; then
    echo "Missing ru.md next to $en"
    violations=$((violations + 1))
    continue
  fi

  # Existence only, not content-identity: a workspace skill legitimately resolves
  # a different config and so states different steps (conventions/i18n.md).
  skill="${dir%/locales}/SKILL.md"
  if ! grep -q '^## Language Resolution' "$skill"; then
    echo "Localized skill with no '## Language Resolution' section: $skill"
    violations=$((violations + 1))
  fi

  diff_out=$(diff <(grep '^## ' "$en" | sort) <(grep '^## ' "$ru" | sort) || true)
  if [ -n "$diff_out" ]; then
    echo "Key parity mismatch in $dir/:"
    echo "$diff_out"
    violations=$((violations + 1))
  fi
done

if [ "$violations" -gt 0 ]; then
  echo
  echo "Locale parity lint failed: $violations issue(s)"
  exit 1
fi

echo "Locale parity lint passed: all locales in sync"
