#!/usr/bin/env bats
# A test that walks a source tree is a sweep: it carries the '# changed: sweep' mark that Task 4 reads.

setup() {
  ROOT="$(cd -- "$(dirname -- "$BATS_TEST_FILENAME")/../../.." && pwd)"
}

@test "a test that walks a source tree is marked as a sweep" {
  re='(skills|conventions|templates|workflows|commands)/\*|find [^|]*(skills|conventions|templates|workflows|commands)|for [a-z_]+ in [^;]*(skills|conventions|templates|workflows|commands)/'
  missing=""
  for f in "$ROOT"/tests/foundation/lib/*.bats; do
    [ "$(basename "$f")" = changed-sweep.test.bats ] && continue
    grep -qE "$re" "$f" || continue
    head -10 "$f" | grep -qx '# changed: sweep' || missing="$missing $(basename "$f")"
  done
  [ -z "$missing" ] || { echo "walks a tree but carries no '# changed: sweep':$missing"; return 1; }
}
