#!/usr/bin/env bats
# A caller that already holds the answers passes them through setup's `## Input`;
# one that fills every field is asked nothing about the config.

setup() {
  ROOT="$(cd -- "$(dirname -- "$BATS_TEST_FILENAME")/../../.." && pwd)"
  SKILL="$ROOT/skills/setup/SKILL.md"
}

# `## Input`, heading excluded, up to the next H2.
input_section() { awk '/^## Input$/{f=1;next} f&&/^## /{exit} f' "$SKILL"; }

# One numbered step of the Algorithm block, up to the next numbered step.
algorithm_step() {
  awk -v n="$1" '$0 ~ ("^" n "[.] ") {f=1; print; next} f && /^[0-9]+b?[.] / {exit} f' "$SKILL"
}

@test "Input has an answer for the Tasks/ and the registry question" {
  [ "$(input_section | wc -l)" -gt 10 ] || { echo "## Input not found"; return 1; }
  input_section | grep -qE '^tasks[[:space:]]+= create \| skip[[:space:]]' || { echo "no tasks field"; return 1; }
  input_section | grep -qE '^docs_map[[:space:]]+= create \| skip[[:space:]]' || { echo "no docs_map field"; return 1; }
}

@test "Input lets a caller defer the whole stack" {
  input_section | grep -qE '^stack[[:space:]]+= \{axis: value, …\} \| —[[:space:]]'
}

@test "Input promises a caller that fills every field no config question" {
  input_section | grep -qF 'A caller that fills every field is asked nothing about the config'
}

@test "step 5 skips the platform half for a caller-deferred stack" {
  step="$(algorithm_step 5)"
  grep -qF "the input's \`stack\` is \`—\`" <<<"$step" || { echo "step 5 has no — branch"; return 1; }
  grep -qF 'stack_status_deferred_by_caller' <<<"$step" || { echo "step 5 names no report key"; return 1; }
}

@test "steps 6 and 6b take their answer from the input" {
  for want in '`tasks = create`' '`tasks = skip`'; do
    algorithm_step 6 | grep -qF "$want" || { echo "step 6 lacks $want"; return 1; }
  done
  for want in '`docs_map = create`' '`docs_map = skip`'; do
    algorithm_step 6b | grep -qF "$want" || { echo "step 6b lacks $want"; return 1; }
  done
}

@test "the caller-deferred stack has a report line in both locales" {
  for l in en ru; do
    grep -qx '## stack_status_deferred_by_caller' "$ROOT/skills/setup/locales/$l.md" \
      || { echo "missing in $l.md"; return 1; }
  done
}

# State B, heading excluded, up to state C.
state_b() { awk '/^   STATE B /{f=1;next} f&&/^   STATE C /{exit} f' "$SKILL"; }

@test "state B backs up CLAUDE.md only when it will insert the import line" {
  body="$(state_b)"
  [ -n "$body" ] || { echo "state B not found"; return 1; }
  skip_at="$(grep -n 'already exists anywhere' <<<"$body" | head -1 | cut -d: -f1)"
  backup_at="$(grep -n 'CLAUDE.md.bak' <<<"$body" | head -1 | cut -d: -f1)"
  [ -n "$skip_at" ] || { echo "no already-present check"; return 1; }
  [ -n "$backup_at" ] || { echo "no backup step"; return 1; }
  [ "$skip_at" -lt "$backup_at" ] || { echo "backup precedes the already-present check"; return 1; }
}

@test "the backup safeguard is tied to a write, not to every run" {
  grep -qF 'A file setup does not write gets no backup' "$SKILL"
}

@test "Input has an answer for the manual-checks style question" {
  input_section | grep -qE '^manual_checks_style[[:space:]]+= brief \| full[[:space:]]+# skips qMS' \
    || { echo "no manual_checks_style field"; return 1; }
}

@test "the manual-checks style is a core question, qMS, with its locale keys in both languages" {
  grep -qF -- '- qMS — Manual checks style: `brief` (default) / `full` (`auq_manual_checks_style_label`, `auq_manual_checks_style_options`)' "$SKILL" \
    || { echo "Core Questions does not list qMS"; return 1; }
  grep -qF 'the bracketed value in `[MANUAL_CHECKS_STYLE]` | qMS' "$SKILL" || { echo "no placeholder row for qMS"; return 1; }
  for lang in en ru; do
    for key in auq_manual_checks_style_label auq_manual_checks_style_options; do
      grep -qxF "## $key" "$ROOT/skills/setup/locales/$lang.md" || { echo "$lang.md has no $key"; return 1; }
    done
  done
  diff <(grep '^## ' "$ROOT/skills/setup/locales/en.md" | sort) <(grep '^## ' "$ROOT/skills/setup/locales/ru.md" | sort) \
    || { echo "locale keys are not in parity"; return 1; }
  opts="$(awk '/^## auq_manual_checks_style_options$/{f=1;next} f&&/^## /{exit} f&&NF' "$ROOT/skills/setup/locales/en.md")"
  [ "$opts" = 'brief | full' ] || { echo "en options: $opts"; return 1; }
}

@test "qMS is asked in states A, B and C after qP, and in C only when the config holds no style" {
  [ "$(grep -cF 'qMS' <<<"$(awk '/^   STATE A /{f=1} /^   STATE D /{exit} f' "$SKILL")")" -ge 3 ] \
    || { echo "states A, B and C do not each name qMS"; return 1; }
  c="$(awk '/^   STATE C \(already_configured\):/{f=1} /^   STATE D /{exit} f' "$SKILL")"
  grep -qF 'qMS only when the config holds no `[MANUAL_CHECKS_STYLE]` line' <<<"$c" \
    || { echo "state C asks qMS although the config answers it"; return 1; }
  grep -qF 'A config that holds the line keeps its value' <<<"$c" || { echo "state C does not carry the value over"; return 1; }
}
