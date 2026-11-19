#!/usr/bin/env bats
# changed: sweep skills workflows
# Split from artifact-lang.test.bats: the tests that walk the source trees.

setup() {
  ROOT="$(cd -- "$(dirname -- "$BATS_TEST_FILENAME")/../../.." && pwd)"
}

@test "every profile names the language in words, and says it again after the body" {
  n=0
  for f in "$ROOT"/workflows/profile-*.js; do
    n=$((n + 1))
    for token in "const LANG_NAME = { en: 'English', ru: 'Russian' }[LANG] || LANG" \
                 'Output language: ${LANG_NAME} — every sentence of prose' \
                 'commit subjects and quoted logs and messages stay English' \
                 '${DOCS_NOTE}${body}' 'Prose language: ${LANG_NAME}.`'; do
      grep -qF -- "$token" "$f" || { echo "$(basename "$f") lacks: $token"; return 1; }
    done
    ! grep -qF 'Output language: ${LANG} ' "$f" || { echo "$(basename "$f") still names the language by its code"; return 1; }
  done
  [ "$n" -eq 8 ] || { echo "scanned $n profile script(s), expected 8"; return 1; }
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
  [ "$n" -eq 8 ] || { echo "scanned $n workflow skill(s), expected 8"; return 1; }
}
