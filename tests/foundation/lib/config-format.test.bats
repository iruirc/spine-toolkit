#!/usr/bin/env bats
# changed: sweep skills conventions workflows commands
# The config's settings live in [FIELD] = [value] lines. A surface still telling a reader to find
# a `## <Block>` section of that file is a surface that will send them looking for something the
# file no longer has.

setup() { ROOT="$(cd -- "$(dirname -- "$BATS_TEST_FILENAME")/../../.." && pwd)"; }

# Every mention of the config's `## <block>` in $2, minus the headings of $2 that merely begin with
# that word or name a task file (`## Validation.md`) — and minus `## Language Resolution`, a contract
# section every localized skill carries, and `## Validation's regression`, the section of the
# phase-verification skill that defines what Validation runs.
mentions() {
  command grep -nE "(^|[^#])## $1([^A-Za-z]|\$)" "$2" \
    | command grep -vE "## Language Resolution|## Validation's regression|^[0-9]+:#+ $1( [A-Za-z]|\.md\$)"
}

# Prints each mention of `## $1` in $2 as `<file>:<line>: <text>`, then the hint, and returns 1; returns 0
# when there is none. A finding that only says "still names" leaves the reader to guess what to write instead.
report_mentions() {
  local found l
  found="$(mentions "$1" "$2")" || true
  [ -n "$found" ] || return 0
  while IFS= read -r l; do printf '%s:%s: %s\n' "$2" "${l%%:*}" "${l#*:}"; done <<<"$found"
  printf 'hint: "## %s" reads as a section of the config, and the config has no such section any more: its settings are [FIELD] = [value] lines. Name a stage without "##" (the Validation stage) and a task file as Validation.md.\n' "$1"
  return 1
}

@test "a mention of a moved block prints the line and the hint" {
  printf '%s\n' 'see ## Validation for the setting' >"$BATS_TEST_TMPDIR/x.md"
  run report_mentions Validation "$BATS_TEST_TMPDIR/x.md"
  [ "$status" -eq 1 ]
  [[ "$output" == *'x.md:1: see ## Validation for the setting'* ]]
  [[ "$output" == *'hint: "## Validation" reads as a section of the config, and the config has no such section any more: its settings are [FIELD] = [value] lines. Name a stage without "##" (the Validation stage) and a task file as Validation.md.'* ]]
  printf '%s\n' "the ## Validation's regression section" >"$BATS_TEST_TMPDIR/x.md"
  run report_mentions Validation "$BATS_TEST_TMPDIR/x.md"
  [ "$status" -eq 0 ]
}

@test "no core surface tells a reader to find a moved block of the config" {
  n=0
  while IFS= read -r f; do
    n=$((n + 1))
    for block in Language Mode Progress Scale Reporting Validation Docs Budgets Models Effort; do
      report_mentions "$block" "$f" || return 1
    done
  done < <(find "$ROOT/skills" "$ROOT/conventions" "$ROOT/commands" "$ROOT/docs" -name '*.md')
  [ "$n" -ge 60 ] || { echo "scanned $n file(s), expected at least 60"; return 1; }
}

@test "no script or workflow names a moved block of the config" {
  n=0
  for f in "$ROOT"/scripts/*.sh "$ROOT"/workflows/*.js; do
    n=$((n + 1))
    for block in Language Mode Progress Scale Reporting Validation Docs Budgets Models Effort; do
      report_mentions "$block" "$f" || return 1
    done
  done
  [ "$n" -ge 10 ] || { echo "scanned $n file(s), expected at least 10"; return 1; }
}
