#!/usr/bin/env bats
# sync-workflow-prelude.sh copies workflow-src/prelude.js into every workflows/profile-*.js between the
# prelude markers. Each test changes one thing in a copy of the tree and expects the script to write,
# report or refuse exactly that.

setup() {
  ROOT="$(cd -- "$(dirname -- "$BATS_TEST_FILENAME")/../../.." && pwd)"
  T="$BATS_TEST_TMPDIR/tree"
  mkdir -p "$T/scripts"
  cp "$ROOT/scripts/sync-workflow-prelude.sh" "$T/scripts/"
  cp -R "$ROOT/workflows" "$ROOT/workflow-src" "$T/"
}

sync() { run "$T/scripts/sync-workflow-prelude.sh" "$@"; }

# Replaces one exact string in one file under the tree and fails when it is not there exactly once,
# so no test passes by mutating nothing.
mutate() { # $1 = path under $T, $2 = old, $3 = new
  python3 - "$T/$1" "$2" "$3" <<'PY'
import sys
path, old, new = sys.argv[1:4]
src = open(path, encoding='utf-8', newline='').read()
if src.count(old) != 1:
    sys.exit('expected exactly one %r in %s, found %d' % (old, path, src.count(old)))
open(path, 'w', encoding='utf-8', newline='').write(src.replace(old, new))
PY
}

block() { # prints the prelude block of $1
  python3 - "$1" <<'PY'
import re, sys
m = re.search(r'^// ── prelude ─.*?^// ── end prelude ─.*?$', open(sys.argv[1], encoding='utf-8', newline='').read(), flags=re.M | re.S)
print(m.group(0) if m else '<no block>')
PY
}

# Puts `// probe-line` on its own line right before the end marker of the source.
probe_source() {
  python3 - "$T/workflow-src/prelude.js" <<'PY'
import re, sys
p = sys.argv[1]
s = open(p, encoding='utf-8', newline='').read()
s, n = re.subn(r'^(// ── end prelude ─)', r'// probe-line\n\1', s, count=1, flags=re.M)
assert n == 1, 'no end marker in the source'
open(p, 'w', encoding='utf-8', newline='').write(s)
PY
}

DRIFT='workflows/profile-feature.js: prelude differs from workflow-src/prelude.js — run scripts/sync-workflow-prelude.sh'

@test "a clean tree is in sync" {
  sync --check
  [ "$status" -eq 0 ] || { echo "$output"; return 1; }
  sync
  [ "$status" -eq 0 ] || { echo "$output"; return 1; }
  [[ "$output" == *"synced 0 of 8"* ]] || { echo "$output"; return 1; }
}

@test "a hand edit in one copy is drift" {
  mutate workflows/profile-feature.js "ManualChecks.md check: nothing unclear." "ManualChecks.md check: all clear."
  cp "$T/workflows/profile-feature.js" "$BATS_TEST_TMPDIR/before.js"
  sync --check
  [ "$status" -eq 1 ] || { echo "status $status: $output"; return 1; }
  [[ "$output" == *"$DRIFT"* ]] || { echo "$output"; return 1; }
  [ "$(grep -c '^workflows/profile-' <<<"$output")" = 1 ] || { echo "$output"; return 1; }
  cmp "$T/workflows/profile-feature.js" "$BATS_TEST_TMPDIR/before.js"
}

@test "sync restores the copy and is idempotent" {
  mutate workflows/profile-feature.js "ManualChecks.md check: nothing unclear." "ManualChecks.md check: all clear."
  sync
  [ "$status" -eq 0 ] || { echo "$output"; return 1; }
  [[ "$output" == *"synced workflows/profile-feature.js"* ]] || { echo "$output"; return 1; }
  [[ "$output" == *"synced 1 of 8"* ]] || { echo "$output"; return 1; }
  cmp "$T/workflows/profile-feature.js" "$ROOT/workflows/profile-feature.js"
  sync
  [[ "$output" == *"synced 0 of 8"* ]] || { echo "$output"; return 1; }
}

@test "an edit to the source reaches all eight" {
  probe_source
  sync
  [ "$status" -eq 0 ] || { echo "$output"; return 1; }
  [[ "$output" == *"synced 8 of 8"* ]] || { echo "$output"; return 1; }
  src="$(block "$T/workflow-src/prelude.js")"
  for f in "$T"/workflows/profile-*.js; do
    [ "$(grep -c '^// probe-line$' "$f")" = 1 ] || { echo "$(basename "$f"): no probe line"; return 1; }
    [ "$(block "$f")" = "$src" ] || { echo "$(basename "$f"): block differs from the source"; return 1; }
  done
}

@test "the source header stays out of the copies" {
  { echo '// header-probe'; cat "$T/workflow-src/prelude.js"; } > "$BATS_TEST_TMPDIR/src.js"
  mv "$BATS_TEST_TMPDIR/src.js" "$T/workflow-src/prelude.js"
  sync
  [ "$status" -eq 0 ] || { echo "$output"; return 1; }
  [[ "$output" == *"synced 0 of 8"* ]] || { echo "$output"; return 1; }
  ! grep -l 'header-probe' "$T"/workflows/profile-*.js
}

@test "a script with a doubled marker" {
  echo '// ── end prelude ──────────' >> "$T/workflows/profile-test.js"
  sync
  [ "$status" -eq 2 ] || { echo "status $status: $output"; return 1; }
  [[ "$output" == *"workflows/profile-test.js"* ]] || { echo "$output"; return 1; }
}

@test "a structure error writes nothing" {
  probe_source
  sed -i.bak '/^\/\/ ── end prelude ─/d' "$T/workflows/profile-research.js" && rm "$T/workflows/profile-research.js.bak"
  sync
  [ "$status" -eq 2 ] || { echo "status $status: $output"; return 1; }
  [[ "$output" == *"workflows/profile-research.js"* ]] || { echo "$output"; return 1; }
  ! grep -l 'probe-line' "$T"/workflows/profile-*.js
}

@test "a missing source is an error" {
  rm "$T/workflow-src/prelude.js"
  sync --check
  [ "$status" -eq 2 ] || { echo "status $status: $output"; return 1; }
}

@test "an unknown flag is an error" {
  sync --fix
  [ "$status" -eq 2 ] || { echo "status $status: $output"; return 1; }
}

@test "runs from any directory" {
  cd "$BATS_TEST_TMPDIR"
  run "$T/scripts/sync-workflow-prelude.sh" --check
  [ "$status" -eq 0 ] || { echo "$output"; return 1; }
}

@test "an end marker above the opening marker is a structure error" {
  python3 - "$T/workflows/profile-quick.js" <<'PY'
import re, sys
p = sys.argv[1]
s = open(p, encoding='utf-8', newline='').read()
end = re.search(r'^// ── end prelude ─.*\n', s, flags=re.M)
s = s[:end.start()] + s[end.end():]
s, n = re.subn(r'^(// ── prelude ─)', end.group(0).replace('\\', r'\\') + r'\1', s, count=1, flags=re.M)
assert n == 1
open(p, 'w', encoding='utf-8', newline='').write(s)
PY
  sync --check
  [ "$status" -eq 2 ] || { echo "status $status: $output"; return 1; }
  [[ "$output" == *"workflows/profile-quick.js"* ]] || { echo "$output"; return 1; }
  [[ "$output" != *"Traceback"* ]] || { echo "$output"; return 1; }
}
