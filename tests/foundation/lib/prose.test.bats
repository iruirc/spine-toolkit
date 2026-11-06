#!/usr/bin/env bats
# The prose helpers the artifact lints share: scripts/lib/prose.py.
# Russian abbreviations are written as \u escapes: lint-i18n.sh keeps Cyrillic out of this file.

setup() {
  ROOT="$(cd -- "$(dirname -- "$BATS_TEST_FILENAME")/../../.." && pwd)"
}

# py <code>: runs the code with scripts/lib on the path and prose's names imported.
py() {
  python3 -c "
import sys
sys.path.insert(0, '$ROOT/scripts/lib')
from prose import chunks, prose, sentences, words, MAX_WORDS
$1"
}

@test "the module is importable and the style threshold is 30 words" {
  run py 'print(MAX_WORDS)'
  [ "$status" -eq 0 ] || { echo "$output"; return 1; }
  [ "$output" = "30" ]
}

@test "a decimal point does not end a sentence" {
  run py 'print(len(sentences("The gap is 0.8 s. Next one.")))'
  [ "$status" -eq 0 ] || { echo "$output"; return 1; }
  [ "$output" = "2" ]
}

@test "a decimal comma stays inside one sentence" {
  run py 'print(len(sentences("The gap is 0,8 \u0441. Next one.")))'
  [ "$status" -eq 0 ] || { echo "$output"; return 1; }
  [ "$output" = "2" ]
}

@test "Russian abbreviations do not end a sentence" {
  run py 'print(len(sentences("\u041e\u0442\u0432\u0435\u0442 \u043f\u0440\u0438\u0445\u043e\u0434\u0438\u0442, \u0442.\u0435. \u0431\u044b\u0441\u0442\u0440\u043e, \u0438 \u0442.\u0434. \u0442\u043e\u0436\u0435. \u041d\u0430\u043f\u0440. \u043e\u0434\u0438\u043d \u0432\u0430\u0440\u0438\u0430\u043d\u0442. \u0421\u043c. \u0440\u0438\u0441. 3 \u043d\u0438\u0436\u0435.")))'
  [ "$status" -eq 0 ] || { echo "$output"; return 1; }
  [ "$output" = "3" ] || { echo "got $output"; return 1; }
}

@test "English abbreviations do not end a sentence" {
  run py 'print(len(sentences("Use a cart, e.g. a guest one, i.e. unsigned, etc. Then stop. Really!")))'
  [ "$status" -eq 0 ] || { echo "$output"; return 1; }
  [ "$output" = "2" ] || { echo "got $output"; return 1; }
}

@test "sentences splits on full stop, exclamation, question mark and ellipsis" {
  run py 'print(len(sentences("One. Two! Three? Four… Five.")))'
  [ "$status" -eq 0 ] || { echo "$output"; return 1; }
  [ "$output" = "5" ]
}

@test "an inline code span counts as one word" {
  run py 'print(words("Call `cart.add(item, 2)` before the checkout"))'
  [ "$status" -eq 0 ] || { echo "$output"; return 1; }
  [ "$output" = "5" ]
}

@test "a hyphenated compound counts as one word" {
  run py 'print(words("A well-known, state-of-the-art cart"))'
  [ "$status" -eq 0 ] || { echo "$output"; return 1; }
  [ "$output" = "4" ]
}

@test "words counts Cyrillic runs of letters" {
  run py 'print(words("\u041a\u043e\u0440\u0437\u0438\u043d\u0430 \u043f\u0443\u0441\u0442\u0430, \u043f\u043e\u043a\u0430 \u043d\u0435\u0442 \u0442\u043e\u0432\u0430\u0440\u043e\u0432"))'
  [ "$status" -eq 0 ] || { echo "$output"; return 1; }
  [ "$output" = "5" ]
}

@test "chunks drops fences, tables, headings and blockquotes but keeps backticks" {
  run py '
tick = chr(96)
fence = tick * 3
text = "Intro with " + tick + "code" + tick + ".\n\n## Part\n\n" + fence + "\nfenced line\n" + fence + "\n| a | b |\n|---|---|\n> quoted\nBody with " + tick + "span" + tick + " kept.\n"
out = chunks(text)
print([t for t, _ in out])
body = "\n".join(b for _, b in out)
for gone in ("fenced line", "| a |", "quoted", "## Part"):
    assert gone not in body, gone
assert tick + "code" + tick in body and tick + "span" + tick in body
print("ok")'
  [ "$status" -eq 0 ] || { echo "$output"; return 1; }
  [ "${lines[0]}" = "['(preamble)', '## Part']" ] || { echo "$output"; return 1; }
  [ "${lines[1]}" = "ok" ]
}

@test "prose strips inline code, links, paths and quoted commit subjects" {
  run py '
out = prose("See `cart.add` and https://example.com/x in src/cart/Item.swift and file.md, fix(cart): quoted")
for gone in ("cart.add", "example.com", "src/cart", "file.md", "fix(cart)"):
    assert gone not in out, gone
print("ok")'
  [ "$status" -eq 0 ] || { echo "$output"; return 1; }
  [ "$output" = "ok" ]
}
