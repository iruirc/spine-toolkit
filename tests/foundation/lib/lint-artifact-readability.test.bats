#!/usr/bin/env bats
# The readability lint of the artifacts a task leaves (Done, Plan, Review, Research, Questions,
# OpsChecklist): a sentence over words-per-sentence words, identifiers piled into the first section
# or one table cell, a label (M1, u3) without a gloss, a Questions.md entry without a question and a
# table in an OpsChecklist.md. The fixtures are synthetic (a shopping cart); a Russian one is named
# *.ru.md and is copied here under the artifact's real name. Russian words never appear in this
# file: lint-i18n.sh keeps Cyrillic out of it.

setup() {
  ROOT="$(cd -- "$(dirname -- "$BATS_TEST_FILENAME")/../../.." && pwd)"
  LINT="$ROOT/scripts/lint-artifact-readability.sh"
  FIX="$ROOT/tests/fixtures/artifact-readability"
  PROJ="$BATS_TEST_TMPDIR/proj"
  TASK="$PROJ/Tasks/ACTIVE/001-x"
  mkdir -p "$TASK"
  printf '## Paths\n' >"$PROJ/CLAUDE-spine-toolkit.md"
}

# write <Artifact.md>: stdin becomes that artifact of the task.
write() { cat >"$TASK/$1"; }

# fixture <fixture file> <Artifact.md>: a copy of the fixture under the artifact's real name.
fixture() { cp "$FIX/$1" "$TASK/$2"; }

# words <n>: n filler words separated by single spaces.
words() { local i; for ((i = 1; i <= $1; i++)); do [ "$i" -gt 1 ] && printf ' '; printf 'word'; done; }

# sentence <n>: one sentence of n words under a heading, in Done.md.
sentence() { { printf '# Done\n\n## Summary\n\n'; words "$1"; printf '.\n'; } | write Done.md; }

# expect <status> [<output line>...]: the lint on the task dir ends so and prints exactly these lines.
expect() {
  local want="$1" text=""
  shift
  [ "$#" -eq 0 ] || text="$(printf '%s\n' "$@")"
  run "$LINT" "$TASK"
  [ "$status" -eq "$want" ] || { echo "$status $output"; return 1; }
  [ "$output" = "$text" ] || { echo "got:  $output"; echo "want: $text"; return 1; }
}

@test "the good fixtures pass in both languages" {
  for a in Done Plan Review Research Questions OpsChecklist; do fixture "$a.en.md" "$a.md"; done
  expect 0
  rm -f "${TASK:?}"/*.md
  for a in Done Plan; do fixture "$a.ru.md" "$a.md"; done
  expect 0
}

@test "a directory without artifacts exits 0 and says nothing" {
  printf 'x\n' >"$TASK/Task.md"
  expect 0
}

@test "a sentence of exactly the threshold passes and one word more is a finding" {
  sentence 30
  expect 0
  sentence 31
  expect 1 'Done.md: sentence: sentence of 31 words (Summary)'
}

@test "words-per-sentence in a Task.md moves the threshold" {
  printf '[TASK_TYPE] = [BUG]\n[BUDGETS] = [words-per-sentence: 12]\n' >"$TASK/Task.md"
  sentence 12
  expect 0
  sentence 13
  expect 1 'Done.md: sentence: sentence of 13 words (Summary)'
}

@test "the sentence class reads Plan.md, Review.md, Research.md and Questions.md too" {
  for a in Plan Review Research; do
    { printf '# T\n\n## Summary\n\n'; words 31; printf '.\n'; } | write "$a.md"
  done
  { printf '# T\n\n## Questions Log\n\n- [plan] q1 — **Question:** Is this fine for us all?\n  **Decision:** '; words 31; printf '.\n'; } | write Questions.md
  run "$LINT" "$TASK"
  [ "$status" -eq 1 ] || { echo "$status $output"; return 1; }
  [ "$(grep -c 'sentence of 31 words' <<<"$output")" -eq 4 ] || { echo "$output"; return 1; }
}

@test "a twelve-item checkbox list without final dots is no sentence finding" {
  {
    printf '# Plan\n\n## Steps\n\n'
    for i in 1 2 3 4 5 6 7 8 9 10 11 12; do printf -- '- [x] step number %s of the plan with a few more words\n' "$i"; done
  } | write Plan.md
  expect 0
}

@test "a numbered list without final dots is no sentence finding" {
  {
    printf '# Plan\n\n## Steps\n\n'
    for i in 1 2 3 4 5 6 7 8 9 10 11 12; do printf '%s. run the check number %s of the plan\n' "$i" "$i"; done
  } | write Plan.md
  expect 0
}

@test "a table row, a fence, a heading, a quote and the closing block are not prose" {
  {
    printf '# %s\n\n## %s\n\n' "$(words 40)" "$(words 40)"
    printf '| What | Evidence |\n|---|---|\n| %s | ok |\n\n' "$(words 40)"
    printf '```\n%s\n```\n\n' "$(words 40)"
    printf '> %s\n\n' "$(words 40)"
    printf 'Short and clean.\n\n'
    printf '[DONE_COMMIT] = %s\n[REVIEW_FIXES] = %s\n**Run:** %s\n**Device:** %s\n' "$(words 40)" "$(words 40)" "$(words 40)" "$(words 40)"
  } | write Done.md
  expect 0
}

@test "a list item is its own unit and a long item is found alone" {
  { printf '# Done\n\n## Summary\n\n- short item\n- '; words 31; printf '.\n- another short item\n'; } | write Done.md
  expect 1 'Done.md: sentence: sentence of 31 words (Summary)'
}

@test "identifiers: at least 3 spans and more than 10 percent of the first section" {
  write Done.md <<'MD'
# Done

## Summary

The totals moved from `CartTotals` to `CartPricing` and `CartRules` today.

## Verification

The `CartA` and `CartB` and `CartC` names here do not count, this is not the first section at all.
MD
  expect 1 'Done.md: identifiers: 3 of 10 words are identifiers in the first section (Summary)'
}

@test "identifiers: two spans, or a small share, pass" {
  write Done.md <<'MD'
# Done

## Summary

The totals moved from `CartTotals` to `CartPricing` today.

## Verification

Nothing here.
MD
  expect 0
  write Done.md <<'MD'
# Done

## Summary

The discount now applies to the goods only, so a free-delivery order can no longer go below zero. The change touches `CartTotals`, `CartRules` and `CartPricing`, while every other part of the cart stays exactly as it was before the change was made at all.

## Verification

Nothing here.
MD
  expect 0
}

@test "identifiers: the first section runs to the next section, sub-headings included" {
  write Done.md <<'MD'
# Done

## Summary

### Part

Moved `CartTotals`, `CartPricing`, `CartRules` today.

## Verification

Nothing here.
MD
  expect 1 'Done.md: identifiers: 3 of 5 words are identifiers in the first section (Summary)'
}

@test "identifiers: more than 2 spans in a What, Note or Evidence cell" {
  write Done.md <<'MD'
# Done

## Verification

| What | Evidence |
|---|---|
| Totals | The tests `a_test`, `b_test` and `c_test` pass |
| Cart | The test `d_test` and `e_test` pass |
MD
  expect 1 'Done.md: identifiers: 3 identifiers in one cell (Verification)'
}

@test "identifiers: the column header is English and case-insensitive, other columns are free" {
  write Done.md <<'MD'
# Done

## Verification

| Name | NOTE |
|---|---|
| `a` `b` `c` `d` | one `a`, two `b` and three `c` |
MD
  expect 1 'Done.md: identifiers: 3 identifiers in one cell (Verification)'
}

@test "label: a label at the start of a sentence is a finding" {
  write Done.md <<'MD'
# Done

## Summary

M1 fixed the rounding in the totals.
MD
  expect 1 'Done.md: label: label without a gloss (Summary)'
}

@test "label: a label in brackets or parentheses passes" {
  write Done.md <<'MD'
# Done

## Summary

The rounding in the totals is fixed (M1). The cart screen follows [u3] later on.

- Totals rounded once at the end (P5)
MD
  expect 0
}

@test "label: a backticked label at the start is a finding, one in a short sentence too" {
  write Done.md <<'MD'
# Done

## Summary

`u3` is done. See M1.
MD
  expect 1 'Done.md: label: label without a gloss (Summary)' 'Done.md: label: label without a gloss (Summary)'
}

@test "label: a label in a sentence of four words or more once it is removed passes" {
  write Done.md <<'MD'
# Done

## Summary

The totals now round once at the end, as M1 asked.
MD
  expect 0
}

@test "label: tokens that are not labels pass" {
  write Done.md <<'MD'
# Done

## Summary

The a1b2c3d commit and the UTF8 text and the abc123 name stay as they are.
MD
  expect 0
}

@test "question: an entry in the log without a question is a finding" {
  write Questions.md <<'MD'
# Questions

## Questions Log

- [plan] q1 — **Question:** Should rounding happen once at the end?
  **Decision:** once.
- [plan] q2 — RESOLVED: once at the end
- [plan] q3 — **Question:** too short
- [plan] q4 — **Decision:** once at the end
MD
  expect 1 'Questions.md: question: entry without a question (Questions Log)' \
    'Questions.md: question: entry without a question (Questions Log)' \
    'Questions.md: question: entry without a question (Questions Log)'
}

@test "question: entries under other headings are free text" {
  write Questions.md <<'MD'
# Questions

## Notes

- anything goes here
- [plan] q2 — RESOLVED: once at the end

## Questions Log

- [plan] q1 — **Question:** Should rounding happen once at the end?
MD
  expect 0
}

@test "question: the class belongs to Questions.md" {
  write Done.md <<'MD'
# Done

## Questions Log

- [plan] rounding — RESOLVED: once at the end
MD
  expect 0
}

@test "format: a table row in OpsChecklist.md is a finding" {
  write OpsChecklist.md <<'MD'
# Ops checklist

## Applicable

| Item | State |
|---|---|
| Analytics | done |
MD
  expect 1 'OpsChecklist.md: format: table row; the checklist is a list (Applicable)'
}

@test "format: a table in another artifact, or a table in a fence, is not a format finding" {
  write Done.md <<'MD'
# Done

## Verification

| Item | State |
|---|---|
| Analytics | done |
MD
  write OpsChecklist.md <<'MD'
# Ops checklist

## Applicable

```
| Item | State |
```

- Analytics: done
MD
  expect 0
}

@test "an old-layout Done.md passes and a defect in it is still found" {
  fixture Done.old-layout.en.md Done.md
  expect 0
  { cat "$FIX/Done.old-layout.en.md"; printf '\nM1 fixed the rounding.\n'; } | write Done.md
  expect 1 'Done.md: label: label without a gloss (Follow-ups)'
}

@test "a file argument is checked by its basename and read against its own directory" {
  printf '[BUDGETS] = [words-per-sentence: 12]\n' >"$TASK/Task.md"
  sentence 13
  run "$LINT" "$TASK/Done.md"
  [ "$status" -eq 1 ] || { echo "$status $output"; return 1; }
  [ "$output" = 'Done.md: sentence: sentence of 13 words (Summary)' ] || { echo "$output"; return 1; }
}

@test "a directory checks only the artifacts that exist, in a fixed order" {
  { printf '# T\n\n## Summary\n\n'; words 31; printf '.\n'; } | write Plan.md
  sentence 31
  expect 1 'Done.md: sentence: sentence of 31 words (Summary)' 'Plan.md: sentence: sentence of 31 words (Summary)'
}

@test "usage: no argument, two arguments, a missing path and a foreign basename exit 2" {
  run "$LINT"
  [ "$status" -eq 2 ] || { echo "$status $output"; return 1; }
  run "$LINT" "$TASK" "$TASK"
  [ "$status" -eq 2 ] || { echo "$status $output"; return 1; }
  run "$LINT" "$TASK/missing"
  [ "$status" -eq 2 ] || { echo "$status $output"; return 1; }
  printf 'x\n' >"$TASK/Walkthrough.md"
  run "$LINT" "$TASK/Walkthrough.md"
  [ "$status" -eq 2 ] || { echo "$status $output"; return 1; }
  [[ "$output" == *"Walkthrough.md"* ]] || { echo "$output"; return 1; }
}
