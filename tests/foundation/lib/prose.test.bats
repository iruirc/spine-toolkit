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
sys.dont_write_bytecode = True
sys.path.insert(0, '$ROOT/scripts/lib')
from prose import chunks, prose, sentences, words, units, words_per_sentence, DROPPED_LINE, MAX_WORDS
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

@test "the spaced Russian forms t. e. and t. d. do not end a sentence" {
  # "Answer arrives, t. e. fast, and t. d. too. Next one." is two sentences, not four.
  run py 'print(len(sentences("\u041e\u0442\u0432\u0435\u0442 \u043f\u0440\u0438\u0445\u043e\u0434\u0438\u0442, \u0442. \u0435. \u0431\u044b\u0441\u0442\u0440\u043e, \u0438 \u0442. \u0434. \u0442\u043e\u0436\u0435. \u0414\u0430\u043b\u044c\u0448\u0435 \u043e\u0434\u043d\u043e.")))'
  [ "$status" -eq 0 ] || { echo "$output"; return 1; }
  [ "$output" = "2" ] || { echo "got $output"; return 1; }
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

# A python that keeps its bytecode next to the source would write scripts/lib/__pycache__ into the
# plugin on every lint run. The scripts are copied out so a failure cannot dirty this checkout, and
# a sitecustomize turns off any cache prefix the local python ships with.
@test "the lints that import prose leave no __pycache__ behind" {
  T="$BATS_TEST_TMPDIR/copy"
  mkdir -p "$T/site" "$T/task"
  cp -R "$ROOT/scripts" "$T/scripts"
  rm -rf "$T/scripts/lib/__pycache__"
  printf 'import sys\nsys.pycache_prefix = None\n' >"$T/site/sitecustomize.py"
  printf '# W\n\n## Summary\n\nText.\n' >"$T/w.md"
  env -u PYTHONDONTWRITEBYTECODE PYTHONPATH="$T/site" "$T/scripts/lint-walkthrough.sh" --style "$T/w.md" || true
  [ ! -e "$T/scripts/lib/__pycache__" ] || { echo "lint-walkthrough.sh wrote $(ls "$T/scripts/lib/__pycache__")"; return 1; }
  env -u PYTHONDONTWRITEBYTECODE PYTHONPATH="$T/site" "$T/scripts/lint-artifact-lang.sh" "$T/task" >/dev/null 2>&1 || true
  [ ! -e "$T/scripts/lib/__pycache__" ] || { echo "lint-artifact-lang.sh wrote $(ls "$T/scripts/lib/__pycache__")"; return 1; }
}

@test "the repository ignores __pycache__" {
  grep -qxF '__pycache__/' "$ROOT/.gitignore" || { echo ".gitignore does not name __pycache__/"; return 1; }
}

@test "the merge after a sentence-final abbreviation is documented as a known limit" {
  grep -qF 'Known limit: a full stop after an abbreviation never ends a sentence' "$ROOT/scripts/lib/prose.py" \
    || { echo "prose.py does not document the merge"; return 1; }
  grep -qF 'Known limit: a full stop after an abbreviation such as `e.g.` or `etc.` never ends a sentence' "$ROOT/skills/task-walkthrough/SKILL.md" \
    || { echo "task-walkthrough does not document the merge"; return 1; }
}

@test "units makes a list item or a numbered item a unit of its own" {
  run py '
body = "Intro line\ncontinues here.\n\n- one\n- two\n  wrapped\n1. three\n2) four\n\n**Files:** a, b\n  c, d\nAfter."
for u in units(body):
    print(" | ".join(u))'
  [ "$status" -eq 0 ] || { echo "$output"; return 1; }
  [ "${lines[0]}" = "Intro line | continues here." ] || { echo "$output"; return 1; }
  [ "${lines[1]}" = "one" ] || { echo "$output"; return 1; }
  [ "${lines[2]}" = "two | wrapped" ] || { echo "$output"; return 1; }
  [ "${lines[3]}" = "three" ] || { echo "$output"; return 1; }
  [ "${lines[4]}" = "four" ] || { echo "$output"; return 1; }
  [ "${lines[5]}" = "After." ] || { echo "$output"; return 1; }
  [ "${#lines[@]}" -eq 6 ] || { echo "$output"; return 1; }
}

@test "a Device line is not prose" {
  run py '
assert DROPPED_LINE.match("**Device:** iPhone 15, iOS 17")
assert DROPPED_LINE.match("  **Device:** x")
body = "\n".join(b for _, b in chunks("Intro.\n\n**Device:** the long device line that is not prose at all.\n\nMore.\n"))
assert "device line" not in body, body
print("ok")'
  [ "$status" -eq 0 ] || { echo "$output"; return 1; }
  [ "$output" = "ok" ]
}

# words_per_sentence(directory) asks scripts/resolve-settings.sh; $1 of mk is a Task.md body.
mk() {
  P="$BATS_TEST_TMPDIR/proj"
  mkdir -p "$P/Tasks/ACTIVE/001-x"
  printf '## Paths\n' >"$P/CLAUDE-spine-toolkit.md"
  printf '%s\n' "$1" >"$P/Tasks/ACTIVE/001-x/Task.md"
  D="$P/Tasks/ACTIVE/001-x"
}

@test "words_per_sentence is the default 30 with no entry" {
  mk '[TASK_TYPE] = [BUG]'
  run py "print(words_per_sentence('$D'))"
  [ "$status" -eq 0 ] || { echo "$output"; return 1; }
  [ "$output" = "30" ]
}

@test "words_per_sentence reads a Task.md entry" {
  mk '[TASK_TYPE] = [BUG]
[BUDGETS] = [words-per-sentence: 12]'
  run py "print(words_per_sentence('$D'))"
  [ "$status" -eq 0 ] || { echo "$output"; return 1; }
  [ "$output" = "12" ]
}

@test "words_per_sentence forwards a budgets warning once and drops the others" {
  mk '[TASK_TYPE] = [BUG]
[BUDGETS] = [words-per-sentence: 12, Plan.md: abc]
[MODELS] = [nonsense]'
  mkdir -p "$P/Tasks/ACTIVE/002-y"
  cp "$D/Task.md" "$P/Tasks/ACTIVE/002-y/Task.md"
  run py "print(words_per_sentence('$D')); print(words_per_sentence('$P/Tasks/ACTIVE/002-y'))"
  [ "$status" -eq 0 ] || { echo "$output"; return 1; }
  [ "$(grep -c "Plan.md: abc' not recognized" <<<"$output")" -eq 1 ] || { echo "$output"; return 1; }
  ! grep -q 'MODELS' <<<"$output" || { echo "$output"; return 1; }
}

@test "words_per_sentence on a resolver failure names the lint and the directory and exits 2" {
  run py "words_per_sentence('$BATS_TEST_TMPDIR/missing', 'lint-x.sh')"
  [ "$status" -eq 2 ] || { echo "$status $output"; return 1; }
  [[ "$output" == *"lint-x.sh: resolve-settings.sh failed for $BATS_TEST_TMPDIR/missing"* ]] || { echo "$output"; return 1; }
}

# A resolver that is missing, not executable or answers with something that is not the settings
# json is the same failure as one that exits non-zero: exit 2, not a traceback and exit 1, which
# the lints read as "findings".
@test "words_per_sentence with a missing resolver names the lint and exits 2" {
  mk '[TASK_TYPE] = [BUG]'
  run py "import prose
prose._RESOLVE = '$BATS_TEST_TMPDIR/no-such-resolver.sh'
prose.words_per_sentence('$D', 'lint-x.sh')"
  [ "$status" -eq 2 ] || { echo "$status $output"; return 1; }
  [[ "$output" == *"lint-x.sh: resolve-settings.sh failed for $D"* ]] || { echo "$output"; return 1; }
  ! grep -q Traceback <<<"$output" || { echo "$output"; return 1; }
}

@test "words_per_sentence with malformed json names the lint and exits 2" {
  mk '[TASK_TYPE] = [BUG]'
  printf '#!/usr/bin/env bash\necho "{not json"\n' >"$BATS_TEST_TMPDIR/bad.sh"
  chmod +x "$BATS_TEST_TMPDIR/bad.sh"
  run py "import prose
prose._RESOLVE = '$BATS_TEST_TMPDIR/bad.sh'
prose.words_per_sentence('$D', 'lint-x.sh')"
  [ "$status" -eq 2 ] || { echo "$status $output"; return 1; }
  [[ "$output" == *"lint-x.sh: resolve-settings.sh failed for $D"* ]] || { echo "$output"; return 1; }
  ! grep -q Traceback <<<"$output" || { echo "$output"; return 1; }
}

@test "words_per_sentence with json that is not an object names the lint and exits 2" {
  mk '[TASK_TYPE] = [BUG]'
  printf '#!/usr/bin/env bash\necho "[1, 2]"\n' >"$BATS_TEST_TMPDIR/list.sh"
  chmod +x "$BATS_TEST_TMPDIR/list.sh"
  run py "import prose
prose._RESOLVE = '$BATS_TEST_TMPDIR/list.sh'
prose.words_per_sentence('$D', 'lint-x.sh')"
  [ "$status" -eq 2 ] || { echo "$status $output"; return 1; }
  [[ "$output" == *"lint-x.sh: resolve-settings.sh failed for $D"* ]] || { echo "$output"; return 1; }
}
