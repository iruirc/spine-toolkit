#!/usr/bin/env bats
# The config's settings live in [FIELD] = [value] lines. A surface still telling a reader to find
# a `## <Block>` section of that file is a surface that will send them looking for something the
# file no longer has.

setup() { ROOT="$(cd -- "$(dirname -- "$BATS_TEST_FILENAME")/../../.." && pwd)"; }

# Every mention of the config's `## <block>` in $2, minus the headings of $2 that merely begin with
# that word — and minus `## Language Resolution`, a contract section every localized skill carries.
mentions() {
  command grep -nE "(^|[^#])## $1([^A-Za-z]|\$)" "$2" \
    | command grep -vE "## Language Resolution|^[0-9]+:#+ $1 [A-Za-z]"
}

@test "no core surface tells a reader to find a moved block of the config" {
  n=0
  while IFS= read -r f; do
    n=$((n + 1))
    for block in Language Mode Progress Scale Reporting Validation Docs Budgets Models Effort; do
      [ -z "$(mentions "$block" "$f")" ] || { echo "$f still names ## $block"; return 1; }
    done
  done < <(find "$ROOT/skills" "$ROOT/conventions" "$ROOT/commands" "$ROOT/docs" -name '*.md')
  [ "$n" -ge 60 ] || { echo "scanned $n file(s), expected at least 60"; return 1; }
}

@test "no script or workflow names a moved block of the config" {
  for f in "$ROOT"/scripts/*.sh "$ROOT"/workflows/*.js; do
    for block in Language Mode Progress Scale Reporting Validation Docs Budgets Models Effort; do
      [ -z "$(mentions "$block" "$f")" ] || { echo "$f still names ## $block"; return 1; }
    done
  done
}
