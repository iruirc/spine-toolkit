#!/usr/bin/env bats
# The project config is SPINE.md; CLAUDE-spine-toolkit.md is the name a project may still carry
# until setup renames it (conventions/task-settings.md → Project config). The legacy name is
# read where lookup and migration need it, and nowhere else: a skill or document that still
# names it sends a reader to a file a migrated project no longer has.

setup() {
  ROOT="$(cd -- "$(dirname -- "$BATS_TEST_FILENAME")/../../.." && pwd)"
}

core_grep() {
  local rc=0
  git -C "$ROOT" grep --untracked --full-name "$@" || rc=$?
  [ "$rc" -le 1 ] || { echo "git grep exited $rc — the scan did not run" >&2; return 1; }
}

@test "the legacy config name survives only where migration or lookup needs it" {
  hits="$(core_grep -l 'CLAUDE-spine-toolkit')"
  offenders="$(grep -vE '^(skills/setup/|commands/setup\.md|skills/lang/|commands/lang\.md|conventions/task-settings\.md|conventions/i18n\.md|README\.md|docs/configuration\.md|scripts/resolve-settings\.sh|hooks/session-start|tests/)' <<<"$hits" || true)"
  [ -z "$offenders" ] || { echo "legacy config name outside the whitelist:"; echo "$offenders"; return 1; }
}

@test "the orchestrator resolves settings for the claude-code runtime" {
  grep -qE 'resolve-settings\.sh"? json .*--runtime claude-code' "$ROOT/skills/orchestrator/SKILL.md"
}

@test "orchestrator messages point an unmigrated project at its own config, not at SPINE.md" {
  # A project that still carries the legacy name and follows "write it in SPINE.md" creates a
  # second file that wins over the real one, with nothing else in it.
  for l in en ru; do
    offenders="$(awk '/^## /{k=$2} /SPINE\.md/ && k != "error_no_project_config" {print k}' "$ROOT/skills/orchestrator/locales/$l.md" | sort -u)"
    [ -z "$offenders" ] || { echo "$l names SPINE.md under: $offenders"; return 1; }
  done
}
