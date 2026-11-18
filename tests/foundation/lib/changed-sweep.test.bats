#!/usr/bin/env bats
# A test that walks a source tree is a sweep: it carries the '# changed: sweep' mark that
# `scripts/test-foundation.sh changed` reads. So is a test that reaches a profile script or a skill
# through a variable (profile-$p.js, skills/$s/SKILL.md), drives one through the run-profile
# helpers, or hands a whole directory to a tool ("$ROOT/skills" to ls, grep -r, cp -R): no file names
# its target literally, so nothing but the mark selects it.

setup() {
  ROOT="$(cd -- "$(dirname -- "$BATS_TEST_FILENAME")/../../.." && pwd)"
}

@test "a test that walks a source tree is marked as a sweep" {
  d='skills|conventions|templates|workflows|commands'
  re="($d)/\\*|find [^|]*($d)|for [a-z_]+ in [^;]*($d)/|profile-\\\$|workflow-\\\$|ROOT\\}?/($d)/[^ \"/]*\\\$|helpers/run-profile|ROOT\\}?/($d)\""
  missing=""
  for f in "$ROOT"/tests/foundation/lib/*.bats; do
    [ "$(basename "$f")" = changed-sweep.test.bats ] && continue
    grep -qE "$re" "$f" || continue
    head -10 "$f" | grep -qx '# changed: sweep' || missing="$missing $(basename "$f")"
  done
  [ -z "$missing" ] || { echo "walks a tree but carries no '# changed: sweep':$missing"; return 1; }
}
