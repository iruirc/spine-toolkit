#!/usr/bin/env bats
# The open-questions gate showed the first 80 characters of an item, so the options and the
# recommendation written under it never reached the person answering, and a numbered list was
# not seen at all.

bats_require_minimum_version 1.5.0

setup() {
  ROOT="$(cd -- "$(dirname -- "$BATS_TEST_FILENAME")/../../.." && pwd)"
  OQ="$ROOT/scripts/open-questions.sh"
  A="$BATS_TEST_TMPDIR/Research.md"
}

# One field of every item, one line each: $1 is a python expression over `i`.
field() { python3 -c 'import json,sys; [print(eval(sys.argv[1])) for i in json.load(sys.stdin)]' "$1"; }

@test "an item reaches the dialog with every sub-item under it" {
  cat >"$A" <<'MD'
## Requirements
### Known unknowns
- [u1] Offline sync conflicts — who decides: product, by Plan
  - keep the server copy (recommended)
  - keep the local copy
  - ask the user on every conflict
- [u2] Push payload size
MD
  run "$OQ" "$A"
  [ "$status" -eq 0 ] || { echo "$output"; return 1; }
  [ "$(field 'len(i["text"].splitlines())' <<<"$output")" = "$(printf '4\n1')" ] || { echo "$output"; return 1; }
  [ "$(field 'i["text"].splitlines()[-1]' <<<"$output" | head -1)" = '  - ask the user on every conflict' ] \
    || { echo "$output"; return 1; }
  [ "$(field 'i["text"]' <<<"$output" | tail -1)" = '- [u2] Push payload size' ] || { echo "$output"; return 1; }
}

@test "a numbered list is read, and a closed item is left out whatever its marker" {
  cat >"$A" <<'MD'
## Requirements
### Designer questions
1. [RESOLVED] Empty state illustration
2. Error copy for a lost connection
### Backend questions
1. Pagination cursor or offset
* [DEFERRED] Rate limits
MD
  run "$OQ" "$A"
  [ "$status" -eq 0 ] || { echo "$output"; return 1; }
  [ "$(field 'i["section"] + ": " + i["text"]' <<<"$output")" = "$(printf '%s\n%s' \
    'Designer questions: 2. Error copy for a lost connection' 'Backend questions: 1. Pagination cursor or offset')" ] \
    || { echo "$output"; return 1; }
}

@test "only the four sections count, and a section ends at the next heading" {
  cat >"$A" <<'MD'
## Findings
- not a question
### Open Questions
- Q1 Which cache
#### Notes
- a note under a deeper heading
### Risks
- a risk
MD
  run "$OQ" "$A"
  [ "$status" -eq 0 ] || { echo "$output"; return 1; }
  [ "$(field 'i["section"] + "|" + i["id"]' <<<"$output")" = 'Open Questions|Q1' ] || { echo "$output"; return 1; }
}

@test "the text after an item ends it, and a later item at the same depth starts again" {
  cat >"$A" <<'MD'
### Known unknowns
- [u1] First
  - an option
Paragraph between two lists.
- [u2] Second
MD
  run "$OQ" "$A"
  [ "$(field 'i["text"]' <<<"$output")" = "$(printf '%s\n%s\n%s' '- [u1] First' '  - an option' '- [u2] Second')" ] \
    || { echo "$output"; return 1; }
}

@test "the id is the leading token, or the first 80 characters" {
  long="$(printf 'x%.0s' $(seq 1 100))"
  printf '### Open questions\n- D12: pick a store\n- %s\n' "$long" >"$A"
  run "$OQ" "$A"
  [ "$(field 'i["id"]' <<<"$output")" = "$(printf 'D12\n%s' "${long:0:80}")" ] || { echo "$output"; return 1; }
}

@test "a recommendation is taken only when exactly one sub-item carries the mark" {
  cat >"$A" <<'MD'
### Open questions
- Q1 one mark
  - SQLite (Recommended) — the app already ships it
  - Realm
- Q2 no mark
  - SQLite
- Q3 two marks
  - SQLite (recommended)
  - Realm (recommended)
MD
  run "$OQ" "$A"
  [ "$status" -eq 0 ] || { echo "$output"; return 1; }
  [ "$(field 'i["recommended"]' <<<"$output")" = "$(printf '%s\n%s\n%s' 'SQLite — the app already ships it' None None)" ] \
    || { echo "$output"; return 1; }
}

@test "two artifacts are told apart, and a file with nothing open prints an empty array" {
  printf '### Open questions\n- Q1 in research\n' >"$A"
  printf '# Reproduce\n### Known unknowns\n- [u1] in reproduce\n' >"$BATS_TEST_TMPDIR/Reproduce.md"
  printf '# Plan\n- nothing here\n' >"$BATS_TEST_TMPDIR/Plan.md"
  run "$OQ" "$A" "$BATS_TEST_TMPDIR/Reproduce.md"
  [ "$(field 'i["artifact"].rsplit("/", 1)[1] + " " + i["id"]' <<<"$output")" = "$(printf '%s\n%s' 'Research.md Q1' 'Reproduce.md [u1]')" ] \
    || { echo "$output"; return 1; }
  run "$OQ" "$BATS_TEST_TMPDIR/Plan.md"
  [ "$status" -eq 0 ] && [ "$output" = '[]' ] || { echo "$output"; return 1; }
}

@test "no argument, or a file that is not there, is exit 2" {
  run "$OQ"
  [ "$status" -eq 2 ] || { echo "$status $output"; return 1; }
  grep -qF 'usage: open-questions.sh' <<<"$output" || { echo "$output"; return 1; }
  run "$OQ" "$BATS_TEST_TMPDIR/missing.md"
  [ "$status" -eq 2 ] || { echo "$status $output"; return 1; }
  grep -qF 'no such file' <<<"$output" || { echo "$output"; return 1; }
}

@test "a list or a heading inside a code block is not an item" {
  cat >"$A" <<'MD'
### Open questions
- Q1 Which config shape
  ```yaml
  - key: a
  ```
```
### Known unknowns
- not an item
```
MD
  run "$OQ" "$A"
  [ "$(field 'i["id"] + " " + str(len(i["text"].splitlines()))' <<<"$output")" = 'Q1 4' ] || { echo "$output"; return 1; }
}

@test "a file with CRLF line endings is read the same" {
  printf '### Open questions\r\n- Q1 first\r\n  - yes (recommended)\r\n' >"$A"
  run "$OQ" "$A"
  [ "$(field 'repr(i["text"]) + " " + i["recommended"]' <<<"$output")" = "'- Q1 first\\n  - yes (recommended)' yes" ] || { echo "$output"; return 1; }
}

@test "an item the file ends inside is still collected, an unclosed code block included" {
  printf '### Open questions\n- Q1 last\n  ```\n  - key: a\n' >"$A"
  run "$OQ" "$A"
  [ "$(field 'i["id"] + " " + str(len(i["text"].splitlines()))' <<<"$output")" = 'Q1 3' ] || { echo "$output"; return 1; }
}

@test "the Known unknowns template of feature-requirements yields a recommendation" {
  awk '/^```markdown$/{f=1;next} f&&/^```$/{exit} f' "$ROOT/skills/feature-requirements/SKILL.md" >"$A"
  run "$OQ" "$A"
  [ "$(field 'i["id"] + " " + str(i["recommended"])' <<<"$output" | grep '^\[u1\]')" = '[u1] <option A> — <why>' ] \
    || { echo "$output"; return 1; }
}

@test "rule 5 of task-documents names the mark the gate reads" {
  grep -qF 'the recommended one carries `(recommended)`' "$ROOT/skills/task-documents/SKILL.md" \
    || { echo "rule 5 does not say how a recommendation is marked"; return 1; }
}

@test "a closed bullet keeps its prefix and a log entry in the Questions.md form is not an open item" {
  cat >"$A" <<'MD'
### Open questions
- [RESOLVED] Q1 Does a promo code apply to discounted items
  - no, full-price items only
- [DEFERRED] Q2 Rounding of the total
- Q3 Which cache
## Open Questions Log
- [Research] Q1 — **Question:** does a promo code apply to discounted items?
  **Decision:** no, the code applies to full-price items only.
  **Rejected:** applying it to every item, because two discounts on one item can break the cap.
  **Decided by:** owner, 2026-11-07
MD
  run "$OQ" "$A"
  [ "$status" -eq 0 ] || { echo "$output"; return 1; }
  [ "$(field 'i["id"]' <<<"$output")" = 'Q3' ] || { echo "$output"; return 1; }
}

# The gate showed an empty prompt when Diagnose wrote its questions under a translated heading, as
# paragraphs: the script read nothing and said nothing. What it cannot read now goes to stderr.
W1='an open question outside a section the gate reads — expected a heading beginning "Open Questions"'
W2='a question written as a paragraph — expected a list item "- <ID>. …"'
W3="a heading inside a question section — expected its questions as list items right under that section's heading"
# Translated headings as \uXXXX escapes: no Cyrillic outside *.ru.md.
unescape() { python3 -c 'import sys; print(sys.argv[1].encode("ascii").decode("unicode_escape"))' "$1"; }
RU_OPEN="$(unescape '\u041e\u0442\u043a\u0440\u044b\u0442\u044b\u0435 \u0432\u043e\u043f\u0440\u043e\u0441\u044b')"
RU_DECISIONS="$(unescape '\u0420\u0435\u0448\u0435\u043d\u0438\u044f')"

@test "a translated heading over paragraph questions is reported, not collected" {
  printf '## %s for Plan\n\n**Q1. A zero-length word in a pause.** Plan decides.\n\n- Take the previous word (recommended).\n- Take a neighbour only on contact.\n' "$RU_OPEN" >"$A"
  run --separate-stderr "$OQ" "$A"
  [ "$status" -eq 0 ] && [ "$output" = '[]' ] || { echo "$status $output"; return 1; }
  [ "$stderr" = "open-questions: $A:1: $W1" ] || { echo "$stderr"; return 1; }
}

@test "a translated heading over list questions is reported" {
  printf '## %s\n- Q1. Which cache\n  - LRU (recommended)\n' "$RU_OPEN" >"$A"
  run --separate-stderr "$OQ" "$A"
  [ "$output" = '[]' ] || { echo "$output"; return 1; }
  [ "$stderr" = "open-questions: $A:1: $W1" ] || { echo "$stderr"; return 1; }
}

@test "a heading that begins with a section name is that section" {
  for h in '## Open questions for Plan' '### Open Questions: Diagnose'; do
    printf '%s\n- Q1. Which cache\n  - LRU (recommended)\n' "$h" >"$A"
    run --separate-stderr "$OQ" "$A"
    [ "$(field 'i["section"] + "|" + i["id"] + "|" + str(i["recommended"])' <<<"$output")" = "${h#* }|Q1|LRU" ] \
      || { echo "$output"; return 1; }
    [ -z "$stderr" ] || { echo "$stderr"; return 1; }
  done
}

@test "a section name followed by a letter is not that section" {
  printf '## Open questionsXYZ\n- Q1. x\n' >"$A"
  run --separate-stderr "$OQ" "$A"
  [ "$output" = '[]' ] && [ -z "$stderr" ] || { echo "$output $stderr"; return 1; }
}

@test "the decision log is neither a section nor a warning" {
  cat >"$A" <<'MD'
## Open Questions Log
- [Research] Q1 — **Question:** which cache?
  **Decision:** LRU (recommended)
MD
  run --separate-stderr "$OQ" "$A"
  [ "$output" = '[]' ] && [ -z "$stderr" ] || { echo "$output $stderr"; return 1; }
}

@test "a bold id is the item's id" {
  printf '### Open Questions\n- **Q1.** Which cache\n' >"$A"
  run --separate-stderr "$OQ" "$A"
  [ "$(field 'i["id"] + "|" + i["text"]' <<<"$output")" = 'Q1|- **Q1.** Which cache' ] || { echo "$output"; return 1; }
}

@test "a question written as a paragraph under a read heading is reported on its line" {
  printf '## Open Questions\n\n**Q1. Which cache.** text\n\n- LRU (recommended)\n' >"$A"
  run --separate-stderr "$OQ" "$A"
  [ "$stderr" = "open-questions: $A:3: $W2" ] || { echo "$stderr"; return 1; }
  [ "$(field 'i["text"]' <<<"$output")" = '- LRU (recommended)' ] || { echo "$output"; return 1; }
}

@test "a mark inside a code block is not reported" {
  printf '## Notes\n```\n- x (recommended)\n```\n' >"$A"
  run --separate-stderr "$OQ" "$A"
  [ "$output" = '[]' ] && [ -z "$stderr" ] || { echo "$output $stderr"; return 1; }
}

@test "one warning per section, at its heading, and read sections still print" {
  printf '### Open Questions\n- Q1. a\n## %s\n- A (recommended)\n- B (recommended)\n**Q2. b**\n' "$RU_DECISIONS" >"$A"
  run --separate-stderr "$OQ" "$A"
  [ "$(field 'i["id"]' <<<"$output")" = 'Q1' ] || { echo "$output"; return 1; }
  [ "$stderr" = "open-questions: $A:3: $W1" ] || { echo "$stderr"; return 1; }
}

@test "a mark with no heading above is reported at its own line" {
  printf 'Intro.\n- A (recommended)\n' >"$A"
  run --separate-stderr "$OQ" "$A"
  [ "$stderr" = "open-questions: $A:2: $W1" ] || { echo "$stderr"; return 1; }
}

@test "a warning counts CRLF lines" {
  printf 'Intro.\r\n- A (recommended)\r\n' >"$A"
  run --separate-stderr "$OQ" "$A"
  [ "$stderr" = "open-questions: $A:2: $W1" ] || { echo "$stderr"; return 1; }
}

@test "a warning names its artifact" {
  R="$BATS_TEST_TMPDIR/Reproduce.md"
  printf 'Intro.\n- A (recommended)\n' >"$A"
  printf '# R\n## %s\n- B (recommended)\n' "$RU_DECISIONS" >"$R"
  run --separate-stderr "$OQ" "$A" "$R"
  [ "$stderr" = "$(printf 'open-questions: %s:2: %s\nopen-questions: %s:2: %s' "$A" "$W1" "$R" "$W1")" ] \
    || { echo "$stderr"; return 1; }
}

@test "rule 5 names the heading and the form the gate reads" {
  td="$ROOT/skills/task-documents/SKILL.md"
  for t in 'under a heading that begins `Open Questions`' '`- Q1. …`' 'goes under `## Open Questions`, written as rule 5 says'; do
    grep -qF -- "$t" "$td" || { echo "task-documents does not say: $t"; return 1; }
  done
}

@test "a subheading inside a question section is reported as one, not as a missing section" {
  printf '## Open Questions\n### For the owner\n- Q1. Which cache\n  - LRU (recommended)\n' >"$A"
  run --separate-stderr "$OQ" "$A"
  [ "$stderr" = "open-questions: $A:2: $W3" ] || { echo "$stderr"; return 1; }
  printf '## Requirements\n### Known unknowns\n#### Data\n- [u1] x\n  - y (recommended)\n## Risks\n- r (recommended)\n' >"$A"
  run --separate-stderr "$OQ" "$A"
  [ "$stderr" = "$(printf 'open-questions: %s:3: %s\nopen-questions: %s:6: %s' "$A" "$W3" "$A" "$W1")" ] || { echo "$stderr"; return 1; }
}
