#!/usr/bin/env bats
# Codex CLI reads AGENTS.md and expands no @-imports, so the project config reaches it through a
# sentence, not an import line. setup writes that sentence in Codex CLI only, once: the marker line
# is what tells a later run the block is already there (spec: multi-llm milestone 2, section 4).

setup() {
  ROOT="$(cd -- "$(dirname -- "$BATS_TEST_FILENAME")/../../.." && pwd)"
  SK="$ROOT/skills/setup/SKILL.md"
  SECTION="$(awk '/^## AGENTS.md \(Codex CLI\)/{on=1; print; next} on && /^## /{exit} on' "$SK")"
}

@test "the AGENTS.md stub carries the marker in both languages" {
  for l in en ru; do
    f="$ROOT/templates/agents-md-stub/$l.md"
    grep -qxF '<!-- spine: project config -->' "$f" || { echo "no marker in $l"; false; }
    grep -qF '`SPINE.md`' "$f" || { echo "no SPINE.md in $l"; false; }
  done
}

@test "setup touches AGENTS.md only in Codex CLI" {
  [ -n "$SECTION" ]
  grep -qF 'Claude Code' <<<"$SECTION"
  grep -qiF 'nothing' <<<"$SECTION"
  grep -qF 'codex-cli' <<<"$SECTION"
}

@test "setup leaves a marked AGENTS.md alone" {
  grep -qF '<!-- spine: project config -->' <<<"$SECTION"
  grep -qF 'leave it untouched, no backup' <<<"$SECTION"
}

@test "setup backs up an unmarked AGENTS.md before appending" {
  grep -qF 'AGENTS.md.bak' <<<"$SECTION"
  grep -qiF 'append' <<<"$SECTION"
}

@test "a kept legacy name is what AGENTS.md points to" {
  grep -qF 'CLAUDE-spine-toolkit.md' <<<"$SECTION"
}

@test "state G runs the AGENTS.md step before it stops" {
  awk '/STATE G \(legacy_name\)/{on=1} on && /^5\. Hand the /{exit} on' "$SK" | grep -qF 'AGENTS.md (Codex CLI)'
}

@test "the AGENTS.md report keys exist in both locales" {
  for l in en ru; do
    for k in report_agents_md_created report_agents_md_appended report_agents_md_kept report_agents_md_updated; do
      grep -qx "## $k" "$ROOT/skills/setup/locales/$l.md" || { echo "no $k in $l"; false; }
    done
  done
  grep -A3 '^## report_agents_md_appended' "$ROOT/skills/setup/locales/en.md" | grep -qF '{backup_path}'
}

@test "a marked block naming another config file is brought up to date" {
  # Keep the old name, then Rename on a later run: the block must stop naming a file that is gone.
  grep -qF 'names a different config file' <<<"$SECTION"
}

@test "the Keep branch of state G runs step 6c too" {
  grep -A2 -- '- Keep the old name →' "$SK" | grep -qF 'step 6c'
  ! grep -E 'Keep the old name in state G' "$SK" | grep -qF 'no disk changes'
}

@test "setup sends a host other than Claude Code to the runtime map itself" {
  # setup is invoked directly, not through the orchestrator, so it names the runtime on its own.
  para="$(grep -m1 '^\*\*Runtime\.\*\*' "$SK")"
  grep -qF '`codex-cli` in Codex CLI' <<<"$para"
  grep -qF 'runtimes/<runtime>.md' <<<"$para"
  ! grep -qF "orchestrator's Runtime paragraph" <<<"$SECTION"
}
