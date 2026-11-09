#!/usr/bin/env bats
# A task whose results spread over several artifacts leaves one report in a documentation place, and
# every artifact of the task links to it. This lint is the measurement: the report is there, it names
# the task, it has the section where sources disagree, and Done.md (Plan.md, Research.md when they
# exist) holds a link that resolves to it.

setup() {
  ROOT="$(cd -- "$(dirname -- "$BATS_TEST_FILENAME")/../../.." && pwd)"
  LINT="$ROOT/scripts/lint-report-links.sh"
  P="$BATS_TEST_TMPDIR/proj"
  T="$P/Tasks/ACTIVE/042-measure"
  REPORT_DIR="Documents/Topic"
  REPORT_REL="$REPORT_DIR/Report.md"
  LINK="../../../Documents/Topic/Report.md"
  build
}

# A Russian string as \uXXXX escapes: no Cyrillic outside *.ru.md.
ru() { python3 -c 'import sys; sys.stdout.write(sys.argv[1].encode().decode("unicode_escape"))' "$1"; }

# A project root with a complete set; the pieces a test replaces are the variables set in setup.
build() {
  rm -rf "$P"
  mkdir -p "$P/$REPORT_DIR" "$T"
  printf '# Project\n' > "$P/SPINE.md"
  printf '# Report\n\nTask 042-measure.\n\n## 5. Where sources disagree\n\nNothing yet.\n' > "$P/$REPORT_REL"
  printf '# Plan\n\n[REPORT_DECISION] = needed\n[REPORT_PATH] = %s\n\nSee [the report](%s).\n' "$REPORT_REL" "$LINK" > "$T/Plan.md"
  printf '# Done\n\nSee [the report](%s#summary).\n' "$LINK" > "$T/Done.md"
}

@test "a complete set passes" {
  run "$LINT" "$T"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "no fields, or not-needed, is nothing to check" {
  printf '# Plan\n' > "$T/Plan.md"
  rm "$T/Done.md"
  run "$LINT" "$T"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  printf '# Plan\n\n[REPORT_DECISION] = [not-needed]\n' > "$T/Plan.md"
  run "$LINT" "$T"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "unplaced prints the reminder and passes" {
  printf '# Plan\n\n[REPORT_DECISION] = unplaced\n' > "$T/Plan.md"
  rm "$T/Done.md"
  run "$LINT" "$T"
  [ "$status" -eq 0 ]
  [ "$output" = "report: unplaced — Done writes no report until Questions.md answers where it goes" ]
}

@test "brackets around the value are optional" {
  sed -i.bak 's/= needed/= [needed]/; s|= Documents/Topic/Report.md|= [Documents/Topic/Report.md]   # where|' "$T/Plan.md"
  run "$LINT" "$T"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "the root defaults to the folder of the project config" {
  mkdir -p "$BATS_TEST_TMPDIR/elsewhere"
  cd "$BATS_TEST_TMPDIR/elsewhere"
  run "$LINT" "$T"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "no project config and no --root is a usage error" {
  rm "$P/SPINE.md"
  T2="$BATS_TEST_TMPDIR/bare/Tasks/ACTIVE/042-measure"
  mkdir -p "$T2"
  cp "$T/Plan.md" "$T/Done.md" "$T2/"
  cp -R "$P/Documents" "$BATS_TEST_TMPDIR/bare/"
  run "$LINT" "$T2"
  [ "$status" -eq 2 ]
  [ "$output" = "report: no project config above $T2; pass --root" ]
  run "$LINT" "$T2" --root "$BATS_TEST_TMPDIR/bare"
  [ "$status" -eq 0 ]
}

@test "the report file is missing" {
  rm "$P/$REPORT_REL"
  run "$LINT" "$T"
  [ "$status" -eq 1 ]
  [ "$output" = "report: Documents/Topic/Report.md: missing" ]
}

@test "Done.md is missing" {
  rm "$T/Done.md"
  run "$LINT" "$T"
  [ "$status" -eq 1 ]
  [ "$output" = "report: Done.md: missing" ]
}

@test "Done.md has no link" {
  printf '# Done\n\nNo link.\n' > "$T/Done.md"
  run "$LINT" "$T"
  [ "$status" -eq 1 ]
  [ "$output" = "report: Done.md: no link to Documents/Topic/Report.md" ]
}

@test "Plan.md has no link" {
  printf '# Plan\n\n[REPORT_DECISION] = needed\n[REPORT_PATH] = %s\n' "$REPORT_REL" > "$T/Plan.md"
  run "$LINT" "$T"
  [ "$status" -eq 1 ]
  [ "$output" = "report: Plan.md: no link to Documents/Topic/Report.md" ]
}

@test "a link to another file is no link" {
  printf '# Done\n\n[x](../../../Documents/Topic/Other.md)\n' > "$T/Done.md"
  run "$LINT" "$T"
  [ "$status" -eq 1 ]
  [ "$output" = "report: Done.md: no link to Documents/Topic/Report.md" ]
}

@test "a reference definition is a link" {
  printf '# Done\n\nSee [the report][r].\n\n[r]: %s\n' "$LINK" > "$T/Done.md"
  run "$LINT" "$T"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "the report does not name the task" {
  printf '# Report\n\n## Where sources disagree\n' > "$P/$REPORT_REL"
  run "$LINT" "$T"
  [ "$status" -eq 1 ]
  [ "$output" = "report: Documents/Topic/Report.md: does not name the task 042-measure" ]
}

@test "the report has no section where sources disagree" {
  printf '# Report\n\nTask 042-measure.\n\n## Results\n' > "$P/$REPORT_REL"
  run "$LINT" "$T"
  [ "$status" -eq 1 ]
  [ "$output" = 'report: Documents/Topic/Report.md: no "Where sources disagree" section' ]
}

@test "the phrase in running text is not a section" {
  printf '# Report\n\nTask 042-measure.\n\nWhere sources disagree: nowhere.\n' > "$P/$REPORT_REL"
  run "$LINT" "$T"
  [ "$status" -eq 1 ]
  [ "$output" = 'report: Documents/Topic/Report.md: no "Where sources disagree" section' ]
}

@test "the heading is matched without regard to case and level" {
  printf '# Report\n\nTask 042-measure.\n\n### where Sources DISAGREE\n' > "$P/$REPORT_REL"
  run "$LINT" "$T"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "the Russian divergence heading counts" {
  { printf '# Report\n\nTask 042-measure.\n\n## 5. '; ru '\u0413\u0434\u0435 \u0438\u0441\u0442\u043e\u0447\u043d\u0438\u043a\u0438 \u0440\u0430\u0441\u0445\u043e\u0434\u044f\u0442\u0441\u044f'; printf '\n'; } > "$P/$REPORT_REL"
  run "$LINT" "$T"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "Research.md is checked only when it exists" {
  run "$LINT" "$T"
  [ "$status" -eq 0 ]
  printf '# Research\n\nNo link.\n' > "$T/Research.md"
  run "$LINT" "$T"
  [ "$status" -eq 1 ]
  [ "$output" = "report: Research.md: no link to Documents/Topic/Report.md" ]
  printf '# Research\n\n[r](%s)\n' "$LINK" > "$T/Research.md"
  run "$LINT" "$T"
  [ "$status" -eq 0 ]
}

@test "a link survives the move to DONE" {
  mkdir -p "$P/Tasks/DONE"
  mv "$P/Tasks/ACTIVE/042-measure" "$P/Tasks/DONE/042-measure"
  run "$LINT" "$P/Tasks/DONE/042-measure"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "a path with a space is matched decoded" {
  REPORT_DIR="Documents/Perf Base"
  REPORT_REL="$REPORT_DIR/Report.md"
  LINK="../../../Documents/Perf%20Base/Report.md"
  build
  run "$LINT" "$T"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  printf '# Done\n\n[r](%s)\n' "../../../Documents/Perf Base/Report.md" > "$T/Done.md"
  run "$LINT" "$T"
  [ "$status" -eq 1 ]
  printf '# Done\n\n[r](<%s>)\n' "../../../Documents/Perf Base/Report.md" > "$T/Done.md"
  run "$LINT" "$T"
  [ "$status" -eq 0 ]
}

@test "fields of RESEARCH are read from Research.md" {
  rm "$T/Plan.md"
  printf '# Research\n\n[REPORT_DECISION] = needed\n[REPORT_PATH] = %s\n\n[r](%s)\n' "$REPORT_REL" "$LINK" > "$T/Research.md"
  run "$LINT" "$T"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "an unknown decision or a missing path is a usage error" {
  printf '# Plan\n\n[REPORT_DECISION] = maybe\n' > "$T/Plan.md"
  run "$LINT" "$T"
  [ "$status" -eq 2 ]
  [ "$output" = "report: [REPORT_DECISION] = maybe is not one of needed, update, not-needed, unplaced" ]
  printf '# Plan\n\n[REPORT_DECISION] = update\n' > "$T/Plan.md"
  run "$LINT" "$T"
  [ "$status" -eq 2 ]
  [ "$output" = "report: [REPORT_DECISION] = update without [REPORT_PATH]" ]
}

@test "usage" {
  run "$LINT"
  [ "$status" -eq 2 ]
  run "$LINT" "$BATS_TEST_TMPDIR/no-such-dir"
  [ "$status" -eq 2 ]
}
