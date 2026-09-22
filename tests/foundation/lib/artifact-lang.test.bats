#!/usr/bin/env bats
# The prose language of an artifact is measured, not asked for: conventions/artifact-language.md.
# Russian text lives in tests/fixtures/artifact-lang/*.ru.md, the one place lint-i18n.sh lets it be.

setup() {
  ROOT="$(cd -- "$(dirname -- "$BATS_TEST_FILENAME")/../../.." && pwd)"
  LINT="$ROOT/scripts/lint-artifact-lang.sh"
  FIX="$ROOT/tests/fixtures/artifact-lang"
  PROJ="$BATS_TEST_TMPDIR/proj"
  TASK="$PROJ/Tasks/ACTIVE/042-promo"
  mkdir -p "$TASK"
  printf '## Project settings\n\n[LANG] = [ru]\n' >"$PROJ/CLAUDE-spine-toolkit.md"
  printf '[TASK_TYPE] = [BUG]\n' >"$TASK/Task.md"
}

findings() { grep -c ' § ' <<<"$output" || true; }

@test "Russian prose dense with identifiers passes in a ru project" {
  cp "$FIX/research.ru.md" "$TASK/Research.md"
  run "$LINT" "$TASK"
  [ "$status" -eq 0 ] || { echo "$output"; return 1; }
  [ "${lines[${#lines[@]}-1]}" = "artifact language passed" ]
}

@test "English prose in a ru project is a finding in every long section and in the file" {
  cp "$FIX/research.en.md" "$TASK/Research.md"
  run "$LINT" "$TASK"
  [ "$status" -eq 1 ] || { echo "$output"; return 1; }
  for part in '## Summary' '## Root cause' '## Evidence' '(file)'; do
    grep -qF "Research.md § $part: 0% Cyrillic" <<<"$output" || { echo "$output"; echo "no finding for $part"; return 1; }
  done
  [ "$(findings)" -eq 4 ] || { echo "$output"; return 1; }
  [ "${lines[${#lines[@]}-1]}" = "artifact language failed: 4 finding(s)" ]
}

@test "one English section in a Russian file is exactly one finding" {
  cp "$FIX/validation-mixed.ru.md" "$TASK/Validation.md"
  run "$LINT" "$TASK"
  [ "$status" -eq 1 ] || { echo "$output"; return 1; }
  [ "$(findings)" -eq 1 ] || { echo "$output"; return 1; }
  grep -qF 'Validation.md § ## Supplementary check:' <<<"$output" || { echo "$output"; return 1; }
}

@test "Russian prose in an en project is a finding too" {
  printf '## Project settings\n\n[LANG] = [en]\n' >"$PROJ/CLAUDE-spine-toolkit.md"
  cp "$FIX/paragraph.ru.md" "$TASK/Research.md"
  run "$LINT" "$TASK"
  [ "$status" -eq 1 ] || { echo "$output"; return 1; }
  grep -qF 'Research.md § (file): 0% Latin' <<<"$output" || { echo "$output"; return 1; }
}

@test "code, tables, subjects, paths, fields, labels, comments, URLs and file names are not prose" {
  # Each construct carries far more English than the Russian paragraph beside it, so a construct
  # counted as prose drops the share under the floor. The plain-English control proves it would.
  build() { # $1 = construct
    python3 - "$FIX/paragraph.ru.md" "$1" "$TASK/Research.md" <<'PY'
import sys
para, kind, out = open(sys.argv[1], encoding='utf-8').read(), sys.argv[2], sys.argv[3]
words = 'the promo code is taken from the goods and the delivery is priced after it'
n = 40
block = {
    'control': '\n'.join([words] * n),
    'indented-fence': '- the call:\n\n    ```\n' + '\n'.join('    // ' + words for _ in range(n)) + '\n    ```',
    'tilde-fence': '~~~\n' + '\n'.join([words] * n) + '\n~~~',
    'table': '| Case | Note |\n|---|---|\n' + '\n'.join('| %s | %s |' % (words, words) for _ in range(n)),
    'subjects': '\n'.join('- `a1b2c3d` fix(cart): ' + words for _ in range(n)),
    'paths': ' '.join(['src/cart/promo/discount/delivery/rules'] * n * 3),
    'fields': '\n'.join('[PROMO_FIELD] = [%s]' % words for _ in range(n)),
    'labels': ' '.join(['**Failure looks like:**'] * n * 3),
    'inline-code': ' '.join('`%s`' % words for _ in range(n)),
    'comment': '<!--\n' + '\n'.join([words] * n) + '\n-->',
    'urls': ' '.join(['https://example.com/promo/delivery/discount/rules'] * n * 2),
    'file-names': ' '.join(['DiscountPolicy.md PromoCalculator.json DeliveryRates.yaml'] * n * 2),
}[kind]
open(out, 'w', encoding='utf-8').write('## Summary\n\n' + para + '\n' + block + '\n')
PY
  }
  build control
  run "$LINT" "$TASK"
  [ "$status" -eq 1 ] || { echo "the control passed, so this test proves nothing"; echo "$output"; return 1; }
  for kind in indented-fence tilde-fence table subjects paths fields labels inline-code comment urls file-names; do
    build "$kind"
    run "$LINT" "$TASK"
    [ "$status" -eq 0 ] || { echo "$kind was counted as prose"; echo "$output"; return 1; }
  done
}

@test "a file of short English sections is caught as a whole" {
  cp "$FIX/ops-short.en.md" "$TASK/OpsChecklist.md"
  run "$LINT" "$TASK"
  [ "$status" -eq 1 ] || { echo "$output"; return 1; }
  [ "$(findings)" -eq 1 ] || { echo "$output"; return 1; }
  grep -qF 'OpsChecklist.md § (file):' <<<"$output" || { echo "$output"; return 1; }
}

@test "Task.md, Questions.md, _archive/ and step folders are not read" {
  cp "$FIX/research.en.md" "$TASK/Questions.md"
  { cat "$TASK/Task.md"; cat "$FIX/research.en.md"; } >"$TASK/Task.md.new" && mv "$TASK/Task.md.new" "$TASK/Task.md"
  mkdir -p "$TASK/_archive" "$TASK/1.step"
  cp "$FIX/research.en.md" "$TASK/_archive/Research-2026-09-22T101500.md"
  cp "$FIX/research.en.md" "$TASK/_archive/Research.md"
  cp "$FIX/research.en.md" "$TASK/1.step/Research.md"
  run "$LINT" "$TASK"
  [ "$status" -eq 0 ] || { echo "$output"; return 1; }
}

@test "a missing argument, a missing directory and an option are usage errors" {
  run "$LINT"
  [ "$status" -eq 2 ]
  run "$LINT" "$BATS_TEST_TMPDIR/nowhere"
  [ "$status" -eq 2 ]
  run "$LINT" --all "$TASK"
  [ "$status" -eq 2 ]
}

@test "the language is the project's, read through the resolver" {
  # [LANG] is a project-only field: a task that sets it does not move what is measured.
  printf '[TASK_TYPE] = [BUG]\n[LANG] = [en]\n' >"$TASK/Task.md"
  cp "$FIX/research.en.md" "$TASK/Research.md"
  run "$LINT" "$TASK"
  [ "$status" -eq 1 ] || { echo "$output"; return 1; }
  grep -qF '(lang ru)' <<<"$output" || { echo "$output"; return 1; }
}

@test "an unrecognized [LANG] is reported, and the default it falls to is what is measured" {
  printf '## Project settings\n\n[LANG] = [fr]\n[BUDGETS] = [Nope.md: 3]\n' >"$PROJ/CLAUDE-spine-toolkit.md"
  cp "$FIX/paragraph.ru.md" "$TASK/Research.md"
  run "$LINT" "$TASK"
  [ "$status" -eq 1 ] || { echo "$output"; return 1; }
  grep -qF "[LANG]: 'fr' not recognized" <<<"$output" || { echo "$output"; return 1; }
  grep -qF '(lang en)' <<<"$output" || { echo "$output"; return 1; }
  # Only the field this script reads is forwarded: a [BUDGETS] typo is the budget lint's to report.
  ! grep -qF '[BUDGETS]' <<<"$output" || { echo "$output"; return 1; }
}

@test "the script's table of scripts is the convention's" {
  conv="$ROOT/conventions/artifact-language.md"
  grep -qxF '| `en` | Latin | `A–Z`, `a–z` |' "$conv" || { echo "the convention has no en row"; return 1; }
  grep -qxF '| `ru` | Cyrillic | U+0400–U+04FF |' "$conv" || { echo "the convention has no ru row"; return 1; }
  grep -qF "'en': ('Latin', re.compile(r'[A-Za-z]'))," "$LINT" || { echo "the script's en row moved"; return 1; }
  grep -qF "'ru': ('Cyrillic', re.compile('[%s-%s]' % (chr(0x400), chr(0x4FF))))," "$LINT" || { echo "the script's ru row moved"; return 1; }
  for n in 200 '10%'; do
    grep -qF "**$n**" "$conv" || { echo "the convention does not state $n"; return 1; }
  done
  grep -qx 'MIN_LETTERS = 200' "$LINT" && grep -qx 'FLOOR_PERCENT = 10' "$LINT" \
    || { echo "the script's thresholds moved away from the convention's"; return 1; }
}

@test "every profile names the language in words, and says it again after the body" {
  n=0
  for f in "$ROOT"/workflows/profile-*.js; do
    n=$((n + 1))
    for token in "const LANG_NAME = { en: 'English', ru: 'Russian' }[LANG] || LANG" \
                 'Output language: ${LANG_NAME} — every sentence of prose' \
                 '${DOCS_NOTE}${body}' 'Prose language: ${LANG_NAME}.`'; do
      grep -qF -- "$token" "$f" || { echo "$(basename "$f") lacks: $token"; return 1; }
    done
    ! grep -qF 'Output language: ${LANG} ' "$f" || { echo "$(basename "$f") still names the language by its code"; return 1; }
  done
  [ "$n" -eq 7 ] || { echo "scanned $n profile script(s), expected 7"; return 1; }
}

@test "the walkthrough revision does not take its language from the reader's notes" {
  for f in "$ROOT"/workflows/profile-*.js; do
    grep -qF "The reader's notes above may be in another language; the file's prose stays \${LANG_NAME}." "$f" \
      || { echo "$(basename "$f"): the revision brief does not pin the language"; return 1; }
  done
}

@test "every workflow skill names the language in words, first and last, in every subagent prompt" {
  n=0
  for s in "$ROOT"/skills/workflow-*/SKILL.md; do
    n=$((n + 1))
    grep -F -- '- `lang` — ' "$s" | grep -qF 'names it in words (`English`, `Russian`) at its start and again as its last line' \
      || { echo "$s hands the language over as a bare code"; return 1; }
  done
  [ "$n" -eq 7 ] || { echo "scanned $n workflow skill(s), expected 7"; return 1; }
}

@test "the skills whose examples are English say which part of a line is translated" {
  ops="$ROOT/skills/ops-checklist/SKILL.md"
  mc="$ROOT/skills/manual-checks/SKILL.md"
  for token in "Everything after the dash" "is prose in" "keeps \`N/A: Forced-upgrade\` and"; do
    grep -qF -- "$token" "$ops" || { echo "ops-checklist does not say: $token"; return 1; }
  done
  for token in 'field labels above stay English' "A case's title after \`### N.\`" 'are prose in the project'; do
    grep -qF -- "$token" "$mc" || { echo "manual-checks does not say: $token"; return 1; }
  done
}
