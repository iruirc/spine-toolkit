#!/usr/bin/env bats
# The open-questions gate showed the first 80 characters of an item, so the options and the
# recommendation written under it never reached the person answering, and a numbered list was
# not seen at all.

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
