#!/usr/bin/env bats
# A refresh that only ever appends kept sections of commits a reset and a squash had dropped, and
# the Done agent called the file consistent; a later Done cut the file short with a patch of its own
# and nobody noticed. This lint is the measurement neither claim had.

setup() {
  ROOT="$(cd -- "$(dirname -- "$BATS_TEST_FILENAME")/../../.." && pwd)"
  LINT="$ROOT/scripts/lint-walkthrough.sh"
  PROJ="$BATS_TEST_TMPDIR/proj"
  TASK="$PROJ/Tasks/ACTIVE/001-x"
  mkdir -p "$TASK"
  printf '## Paths\n' >"$PROJ/CLAUDE-spine-toolkit.md"
  printf 'Tasks/\n' >"$PROJ/.gitignore"
  git -C "$PROJ" init -q -b main
  commit .gitignore
  "$ROOT/scripts/task-ranges.sh" record "$TASK"
  commit a.txt; A1="$(git -C "$PROJ" rev-parse --short HEAD)"
  commit b.txt; A2="$(git -C "$PROJ" rev-parse --short HEAD)"
  commit c.txt; GONE="$(git -C "$PROJ" rev-parse --short HEAD)"
  git -C "$PROJ" reset -q --hard HEAD~1
}

commit() {
  echo "$1 $RANDOM" >>"$PROJ/$1"
  git -C "$PROJ" add -- "$1"
  git -C "$PROJ" -c user.name=t -c user.email=t@t commit -qm "$1"
}

# $1 deep|brief, $2 the body of ## Commits, $3 the perimeter's Range cell ("-" leaves the table
# out), $4 its Commits cell. Every section the depth requires is present, and every numbered
# commit section carries **In short:**, so the style class has nothing to say about it.
walkthrough() {
  local range="${3:-$A1..$A2}" count="${4:-2}" s
  {
    printf '# Walkthrough\n[COVERS] = %s..%s\n\n' "$A1" "$A2"
    [ "$range" = - ] || printf '| Repository | Range | Commits | ± lines |\n|---|---|---|---|\n| `.` | `%s` | %s | +2/−0 |\n' "$range" "$count"
    for s in 'What changed' Glossary Summary 'Commit order' 'Plan vs. outcome' Commits 'How it works' 'Out of scope' Follow-ups; do
      [ "$1" = deep ] || case "$s" in Glossary | 'Commit order' | 'Out of scope') continue ;; esac
      printf '\n## %s\n\n' "$s"
      case "$s" in
        Commits) printf '%s\n' "$2" | awk '{ print } /^### [0-9]/ { print "\n**In short:** x." }' ;;
        'How it works') printf -- '- Only `%s` is named here.\n' "$GONE" ;;
        *) printf 'x\n' ;;
      esac
    done
  } >"$TASK/Walkthrough.md"
}

@test "a deep section and a bookkeeping range naming a dropped commit are findings" {
  walkthrough deep "$(printf '### 1. `%s` — first\n\n- `%s` inside a section is prose, not a log line.\n\n### 2. `%s` — second\n\n### 3. `%s` — dropped\n\n### Bookkeeping\n\n- `%s..%s` — two commits.' "$A1" "$GONE" "$A2" "$GONE" "$A2" "$GONE")"
  run "$LINT" "$TASK"
  [ "$status" -eq 1 ] || { echo "$status $output"; return 1; }
  [ "$output" = "$(printf 'Walkthrough.md: unreachable: %s is not in the task'"'"'s history (### 3)\nWalkthrough.md: unreachable: %s is not in the task'"'"'s history (Bookkeeping)' "$GONE" "$GONE")" ] \
    || { echo "$output"; return 1; }
}

@test "a brief log line naming a dropped commit is a finding" {
  walkthrough brief "$(printf -- '- `%s` `feat: a` — first.\n- `%s` `feat: b` — second.\n- `%s` `feat: c` — dropped.' "$A1" "$A2" "$GONE")"
  run "$LINT" "$TASK"
  [ "$status" -eq 1 ] || { echo "$status $output"; return 1; }
  [ "$output" = "Walkthrough.md: unreachable: $GONE is not in the task's history (brief)" ] || { echo "$output"; return 1; }
}

@test "grouped and prefixed headings and multi-sha lines are read whole" {
  walkthrough deep "$(printf '### 10–14. `%s`, `%s` — grouped\n\n### 18. app **`%s`** — prefixed\n\n### Bookkeeping\n\n- `%s`, `%s` (`app`) — two lines.' "$A1" "$GONE" "$A2" "$A2" "$GONE")"
  run "$LINT" "$TASK"
  [ "$status" -eq 1 ] || { echo "$status $output"; return 1; }
  [ "$output" = "$(printf 'Walkthrough.md: unreachable: %s is not in the task'"'"'s history (### 10–14)\nWalkthrough.md: unreachable: %s is not in the task'"'"'s history (Bookkeeping)\nWalkthrough.md: heading: 2 commits in one section (### 10–14)' "$GONE" "$GONE")" ] \
    || { echo "$output"; return 1; }
}

@test "a longer fence holding a shorter one does not hide what follows it" {
  walkthrough deep "$(printf '### 1. `%s` — first\n\n````markdown\n```swift\nlet x = 1\n````\n\n### 2. `%s` — second\n\n### 3. `%s` — dropped' "$A1" "$A2" "$GONE")"
  run "$LINT" "$TASK"
  [ "$status" -eq 1 ] || { echo "$status $output"; return 1; }
  [ "$output" = "Walkthrough.md: unreachable: $GONE is not in the task's history (### 3)" ] || { echo "$output"; return 1; }
}

@test "a file cut short from a heading its own text mentions is a finding" {
  walkthrough deep "$(printf '### 1. `%s` — first\n\nThe deferred part went to ## Follow-ups.\n\n### 2. `%s` — second' "$A1" "$A2")"
  python3 - "$TASK/Walkthrough.md" <<'PY'
import sys
p = sys.argv[1]
s = open(p, encoding='utf-8').read()
open(p, 'w', encoding='utf-8').write(s[:s.index('## Follow-ups')].rstrip() + '\n\n## Follow-ups\n\nnone\n')
PY
  run "$LINT" "$TASK"
  [ "$status" -eq 1 ] || { echo "$status $output"; return 1; }
  [ "$output" = "$(printf 'Walkthrough.md: section: missing (## Out of scope)\nWalkthrough.md: missing: %s is not named in ## Commits (.)' "$A2")" ] \
    || { echo "$output"; return 1; }
}

@test "a deep file may leave out its glossary and How it works" {
  walkthrough deep "$(printf '### 1. `%s` — first\n\n### 2. `%s` — second' "$A1" "$A2")"
  python3 - "$TASK/Walkthrough.md" <<'PY2'
import re, sys
p = sys.argv[1]
s = open(p, encoding='utf-8').read()
s = re.sub(r'\n## (Glossary|How it works)\n\n[^\n]*\n', '\n', s)
open(p, 'w', encoding='utf-8').write(s)
PY2
  grep -q '^## Glossary' "$TASK/Walkthrough.md" && { echo "the fixture still has a glossary"; return 1; }
  run "$LINT" "$TASK"
  [ "$status" -eq 0 ] || { echo "$status $output"; return 1; }
}

@test "a numbered deep heading with no sha is a finding" {
  walkthrough deep "$(printf '### 1. The first change\n\n**Files:** `.` `%s`\n\n### 2. `%s` — second' "$A1" "$A2")"
  run "$LINT" "$TASK"
  [ "$status" -eq 1 ] || { echo "$status $output"; return 1; }
  [ "$output" = "$(printf 'Walkthrough.md: heading: 0 commits in one section (### 1)\nWalkthrough.md: missing: %s is not named in ## Commits (.)' "$A1")" ] || { echo "$output"; return 1; }
}

@test "a deep section per phase instead of per commit is a finding" {
  walkthrough deep "$(printf '### 1. Phase one — `%s`, `%s`' "$A1" "$A2")"
  run "$LINT" "$TASK"
  [ "$status" -eq 1 ] || { echo "$status $output"; return 1; }
  [ "$output" = 'Walkthrough.md: heading: 2 commits in one section (### 1)' ] || { echo "$output"; return 1; }
}

@test "a header count the range does not hold is a finding" {
  walkthrough deep "$(printf '### 1. `%s` — first\n\n### 2. `%s` — second' "$A1" "$A2")" "" 3
  run "$LINT" "$TASK"
  [ "$status" -eq 1 ] || { echo "$status $output"; return 1; }
  [ "$output" = 'Walkthrough.md: count: the header says 3, the range holds 2 (.)' ] || { echo "$output"; return 1; }
}

@test "a header with no perimeter is a finding" {
  walkthrough deep "$(printf '### 1. `%s` — first\n\n### 2. `%s` — second' "$A1" "$A2")" -
  run "$LINT" "$TASK"
  [ "$status" -eq 1 ] || { echo "$status $output"; return 1; }
  [ "$output" = 'Walkthrough.md: section: no perimeter table with Range and Commits (header)' ] || { echo "$output"; return 1; }
}

@test "a perimeter ending on a dropped commit is a finding, not an error" {
  walkthrough deep "$(printf '### 1. `%s` — first\n\n### 2. `%s` — second' "$A1" "$A2")" "$A1..$GONE" 3
  run "$LINT" "$TASK"
  [ "$status" -eq 1 ] || { echo "$status $output"; return 1; }
  [ "$output" = "Walkthrough.md: unreachable: $GONE is not in the task's history (header .)" ] || { echo "$output"; return 1; }
}

@test "whole files at both depths pass silently, bookkeeping ranges included" {
  walkthrough deep "$(printf '### 1. `%s` — first\n\n### Bookkeeping\n\n- `%s` — one commit.' "$A1" "$A2")"
  run "$LINT" "$TASK"
  [ "$status" -eq 0 ] || { echo "deep: $status $output"; return 1; }
  walkthrough deep "$(printf '### Bookkeeping\n\n- `%s..%s` — two commits.' "$A1" "$A2")"
  run "$LINT" "$TASK"
  [ "$status" -eq 0 ] || { echo "a range: $status $output"; return 1; }
  walkthrough brief "$(printf -- '- `%s` `feat: a` — first.\n- `%s` `feat: b` — second.' "$A1" "$A2")"
  run "$LINT" "$TASK"
  [ "$status" -eq 0 ] || { echo "brief: $status $output"; return 1; }
  [ -z "$output" ] || { echo "$output"; return 1; }
}

@test "a range no repository holds is a finding, not an error" {
  walkthrough deep "$(printf '### 1. `%s` — first\n\n### Bookkeeping\n\n- `%s..%s` — written backwards.' "$A1" "$A2" "$A1")"
  run "$LINT" "$TASK"
  [ "$status" -eq 1 ] || { echo "$status $output"; return 1; }
  [ "$output" = "$(printf 'Walkthrough.md: range: %s..%s is not a range of one repository (Bookkeeping)\nWalkthrough.md: missing: %s is not named in ## Commits (.)' "$A2" "$A1" "$A2")" ] || { echo "$output"; return 1; }
  walkthrough deep "$(printf '### 1. `%s` — first\n\n### 2. `%s` — second' "$A1" "$A2")" "$A2..$A1"
  run "$LINT" "$TASK"
  [ "$status" -eq 1 ] || { echo "header: $status $output"; return 1; }
  [ "$output" = "Walkthrough.md: range: $A2..$A1 is not a range of one repository (header .)" ] || { echo "$output"; return 1; }
}

@test "a bullet wrapped onto a second line is read whole" {
  walkthrough deep "$(printf '### 1. `%s` — first\n\n### Bookkeeping\n\n- Two phase-closing commits in the task repository,\n  `%s` among them.' "$A1" "$A2")"
  run "$LINT" "$TASK"
  [ "$status" -eq 0 ] || { echo "$status $output"; return 1; }
}

@test "a table after the perimeter is not read as its rows" {
  walkthrough deep "$(printf '### 1. `%s` — first\n\n### 2. `%s` — second' "$A1" "$A2")"
  python3 - "$TASK/Walkthrough.md" "$A1" "$GONE" <<'PY2'
import sys
p, a, gone = sys.argv[1:]
s = open(p, encoding='utf-8').read()
i = s.index('\n## What changed')
extra = '\n| Build | Where | Runs | Result |\n|---|---|---|---|\n| ci | `%s..%s` | 1 | green |\n' % (a, gone)
open(p, 'w', encoding='utf-8').write(s[:i] + extra + s[i:])
PY2
  run "$LINT" "$TASK"
  [ "$status" -eq 0 ] || { echo "$status $output"; return 1; }
}

@test "no walkthrough, no base and an epic are not measured" {
  run "$LINT" "$TASK"
  [ "$status" -eq 0 ] || { echo "no file: $status $output"; return 1; }
  walkthrough deep "$(printf '### 1. `%s` — dropped' "$GONE")"
  printf '[TASK_TYPE] = [EPIC]\n' >"$TASK/Task.md"
  run "$LINT" "$TASK"
  [ "$status" -eq 0 ] || { echo "epic: $status $output"; return 1; }
  printf '[TASK_TYPE] = [FEATURE]\n' >"$TASK/Task.md"
  rm "$TASK/Base.md"
  run "$LINT" "$TASK"
  [ "$status" -eq 0 ] || { echo "no base: $status $output"; return 1; }
}

@test "--current passes a file naming the newest commit, and a later code commit puts it behind" {
  walkthrough deep "$(printf '### 1. `%s` — first\n\n### 2. `%s` — second' "$A1" "$A2")"
  run "$LINT" --current "$TASK"
  [ "$status" -eq 0 ] || { echo "current: $status $output"; return 1; }
  # Done's own report lands in the tasks folder: not a commit the file owes a line.
  echo done >"$TASK/Done.md"
  git -C "$PROJ" add -f -- "$TASK/Done.md"
  git -C "$PROJ" -c user.name=t -c user.email=t@t commit -qm done
  run "$LINT" --current "$TASK"
  [ "$status" -eq 0 ] || { echo "a tasks-folder commit: $status $output"; return 1; }
  commit d.txt; d="$(git -C "$PROJ" rev-parse --short=7 HEAD)"
  run "$LINT" --current "$TASK"
  [ "$status" -eq 1 ] || { echo "a code commit: $status $output"; return 1; }
  grep -qF "Walkthrough.md: behind: $d is not named in ## Commits (.)" <<<"$output" || { echo "$output"; return 1; }
  run "$LINT" "$TASK"
  [ "$status" -eq 0 ] || { echo "without --current: $status $output"; return 1; }
}

@test "--current reads nothing to measure as behind, and any finding as not current" {
  run "$LINT" --current "$TASK"
  [ "$status" -eq 1 ] || { echo "no file: $status $output"; return 1; }
  grep -qF 'Walkthrough.md: behind: no file, no Base.md, or an EPIC' <<<"$output" || { echo "$output"; return 1; }
  walkthrough deep "$(printf '### 1. `%s` — first\n\n### 2. `%s` — second\n\n### 3. `%s` — dropped' "$A1" "$A2" "$GONE")"
  run "$LINT" --current "$TASK"
  [ "$status" -eq 1 ] || { echo "a finding: $status $output"; return 1; }
  grep -qF 'unreachable' <<<"$output" || { echo "$output"; return 1; }
}

@test "a usage error exits 2" {
  run "$LINT"
  [ "$status" -eq 2 ] || { echo "no args: $status"; return 1; }
  run "$LINT" "$BATS_TEST_TMPDIR/nowhere"
  [ "$status" -eq 2 ] || { echo "no dir: $status"; return 1; }
  run "$LINT" --current
  [ "$status" -eq 2 ] || { echo "--current alone: $status"; return 1; }
}

# The style class: how the prose of the file reads, not what it says about the history.
STYLE="$BATS_TEST_DIRNAME/../../fixtures/walkthrough-style"

# $1 the body of ## What changed, $2 the body of ## Summary, $3 the body of ## Commits.
styled() {
  printf '# Walkthrough\n[COVERS] = a..b\n\n## What changed\n\n%s\n\n## Summary\n\n%s\n\n## Commits\n\n%s\n' \
    "$1" "$2" "$3" >"$BATS_TEST_TMPDIR/w.md"
}

@test "style: a sentence over thirty words is a finding with its word count" {
  run "$LINT" --style "$STYLE/long-sentences.en.md"
  [ "$status" -eq 1 ] || { echo "$status $output"; return 1; }
  [ "$output" = "Walkthrough.md: style: sentence of 38 words (## Summary)" ] || { echo "$output"; return 1; }
}

@test "style: the same rule reads a Russian file" {
  run "$LINT" --style "$STYLE/bad.ru.md"
  [ "$status" -eq 1 ] || { echo "$status $output"; return 1; }
  [ "$output" = "Walkthrough.md: style: sentence of 35 words (## Summary)" ] || { echo "$output"; return 1; }
}

@test "style: a sentence of exactly thirty words passes and thirty-one does not" {
  local w30 w31
  w30="$(printf 'word %.0s' $(seq 30))"
  w31="$(printf 'word %.0s' $(seq 31))"
  styled 'x' "${w30%% }." x
  run "$LINT" --style "$BATS_TEST_TMPDIR/w.md"
  [ "$status" -eq 0 ] || { echo "$status $output"; return 1; }
  styled 'x' "${w31%% }." x
  run "$LINT" --style "$BATS_TEST_TMPDIR/w.md"
  [ "$status" -eq 1 ] || { echo "$status $output"; return 1; }
  [ "$output" = "Walkthrough.md: style: sentence of 31 words (## Summary)" ] || { echo "$output"; return 1; }
}

@test "style: a list without final dots is not one long sentence" {
  local item="$(printf 'word %.0s' $(seq 12))"
  styled x "$(printf -- '- %s\n- %s\n- %s\n1. %s\n2. %s' "$item" "$item" "$item" "$item" "$item")" x
  run "$LINT" --style "$BATS_TEST_TMPDIR/w.md"
  [ "$status" -eq 0 ] || { echo "$status $output"; return 1; }
}

@test "style: a full stop inside a code span or after a list number does not split a sentence" {
  local w29="$(printf 'word %.0s' $(seq 27))"
  # 27 words + two spans = 29 words, one sentence although each span holds a full stop and a space.
  styled x "1. ${w29}\`a. b\` \`c. d\`." x
  run "$LINT" --style "$BATS_TEST_TMPDIR/w.md"
  [ "$status" -eq 0 ] || { echo "$status $output"; return 1; }
  # One more word and the same sentence is over the limit: the span did not hide it.
  styled x "1. word word ${w29}\`a. b\` \`c. d\`." x
  run "$LINT" --style "$BATS_TEST_TMPDIR/w.md"
  [ "$status" -eq 1 ] || { echo "$status $output"; return 1; }
  [ "$output" = "Walkthrough.md: style: sentence of 31 words (## Summary)" ] || { echo "$output"; return 1; }
}

@test "style: an identifier in what changed is a finding, a table row there too" {
  styled "$(printf 'The cart now reads `CartTotals` first.\n\n| Before | After |\n|---|---|\n| a | `CartTotals` |')" x x
  run "$LINT" --style "$BATS_TEST_TMPDIR/w.md"
  [ "$status" -eq 1 ] || { echo "$status $output"; return 1; }
  [ "$output" = "Walkthrough.md: style: identifier in ## What changed (## What changed)" ] || { echo "$output"; return 1; }
  styled "$(printf '| Before | After |\n|---|---|\n| a | `CartTotals` |')" x x
  run "$LINT" --style "$BATS_TEST_TMPDIR/w.md"
  [ "$status" -eq 1 ] || { echo "$status $output"; return 1; }
  [ "$output" = "Walkthrough.md: style: identifier in ## What changed (## What changed)" ] || { echo "$output"; return 1; }
}

@test "style: identifiers outside what changed are not rule b" {
  styled 'No names here.' 'The total comes from `CartTotals` only.' x
  run "$LINT" --style "$BATS_TEST_TMPDIR/w.md"
  [ "$status" -eq 0 ] || { echo "$status $output"; return 1; }
}

@test "style: a sentence that starts with an identifier is a finding" {
  styled x "$(printf 'The total is right. `CartTotals` now adds delivery last.')" x
  run "$LINT" --style "$BATS_TEST_TMPDIR/w.md"
  [ "$status" -eq 1 ] || { echo "$status $output"; return 1; }
  [ "$output" = "Walkthrough.md: style: sentence starts with an identifier (## Summary)" ] || { echo "$output"; return 1; }
}

@test "style: a bullet that starts with an identifier is a finding, a commit log line is not" {
  styled x "- \`CartTotals\` adds delivery last." x
  run "$LINT" --style "$BATS_TEST_TMPDIR/w.md"
  [ "$status" -eq 1 ] || { echo "$status $output"; return 1; }
  [ "$output" = "Walkthrough.md: style: sentence starts with an identifier (## Summary)" ] || { echo "$output"; return 1; }
  styled x x "$(printf -- '- `a1b2c3d` `feat: a` — first, see `CartTotals` and `CartStore`.\n- `a1b2c3d..e4f5a6b` — two commits.')"
  run "$LINT" --style "$BATS_TEST_TMPDIR/w.md"
  [ "$status" -eq 0 ] || { echo "$status $output"; return 1; }
}

@test "style: a brief log bullet that names a type and closes on a path is a log line" {
  styled x x "$(printf -- '- `a1b2c3d` `feat(domain): add CartReader` — introduces the read side, so the UI can\n  move off `CartService` before the write side is touched. `Sources/Domain/Cart*`.\n  **Changes:** 1.')"
  run "$LINT" --style "$BATS_TEST_TMPDIR/w.md"
  [ "$status" -eq 0 ] || { echo "$status $output"; return 1; }
}

@test "style: three identifiers in one sentence are a finding, two are not" {
  styled x 'The `CartTotals` type reads `CartStore` and writes `CartLog` last.' x
  run "$LINT" --style "$BATS_TEST_TMPDIR/w.md"
  [ "$status" -eq 1 ] || { echo "$status $output"; return 1; }
  [ "$output" = "Walkthrough.md: style: 3 identifiers in one sentence (## Summary)" ] || { echo "$output"; return 1; }
  styled x 'The `CartTotals` type reads `CartStore`. It writes `CartLog` last.' x
  run "$LINT" --style "$BATS_TEST_TMPDIR/w.md"
  [ "$status" -eq 0 ] || { echo "$status $output"; return 1; }
}

@test "style: a deep commit section without In short is a finding, Bookkeeping is not" {
  styled x x "$(printf '### 1. `a1b2c3d` — first\n\nText.\n\n### Bookkeeping\n\n- `a1b2c3d` — formatting.')"
  run "$LINT" --style "$BATS_TEST_TMPDIR/w.md"
  [ "$status" -eq 1 ] || { echo "$status $output"; return 1; }
  [ "$output" = "Walkthrough.md: style: missing **In short:** (### 1)" ] || { echo "$output"; return 1; }
}

@test "style: a commit section with sub-headings also needs How verified" {
  styled x x "$(printf '### 1. `a1b2c3d` — first\n\n**In short:** one.\n\n#### What appeared\n\nText.\n\n### 2. `e4f5a6b` — second\n\n**In short:** two.\n\n#### What appeared\n\nText.\n\n**How verified:** a test.\n\n### 3. `0a1b2c3` — third\n\n**In short:** three.')"
  run "$LINT" --style "$BATS_TEST_TMPDIR/w.md"
  [ "$status" -eq 1 ] || { echo "$status $output"; return 1; }
  [ "$output" = "Walkthrough.md: style: missing **How verified:** (### 1)" ] || { echo "$output"; return 1; }
}

@test "style: a brief file needs no commit labels" {
  styled x x "$(printf -- '- `a1b2c3d` `feat: a` — first.\n- `e4f5a6b` `feat: b` — second.')"
  run "$LINT" --style "$BATS_TEST_TMPDIR/w.md"
  [ "$status" -eq 0 ] || { echo "$status $output"; return 1; }
}

@test "style: tables, fences, headings, quotes and label lines full of backticks are not prose" {
  styled x "$(printf '| `A` `B` `C` `D` | `E` starts a cell. |\n|---|---|\n\n```\n`A` `B` `C` `D`. `E` starts a line.\n```\n\n> `A` `B` `C` `D` in a quote.\n\n**Files:** `A` (+1), `B` (+2), `C` (+3), `D` (+4).\n**Changes:** `A`, `B`, `C`, `D`.\n\n### `A` `B` `C` `D` heading')" x
  run "$LINT" --style "$BATS_TEST_TMPDIR/w.md"
  [ "$status" -eq 0 ] || { echo "$status $output"; return 1; }
}

@test "style: a wrapped Files line is one label line" {
  styled x "$(printf '**Files:** `A` (+1), `B` (+2),\n  `C` (+3), `D` (+4).')" x
  run "$LINT" --style "$BATS_TEST_TMPDIR/w.md"
  [ "$status" -eq 0 ] || { echo "$status $output"; return 1; }
}

@test "style: the clean files pass" {
  run "$LINT" --style "$STYLE/clean.en.md"
  [ "$status" -eq 0 ] || { echo "$status $output"; return 1; }
  [ -z "$output" ]
  run "$LINT" --style "$STYLE/clean.ru.md"
  [ "$status" -eq 0 ] || { echo "$status $output"; return 1; }
  [ -z "$output" ]
}

@test "style: a directory or a missing file exits 2" {
  run "$LINT" --style "$BATS_TEST_TMPDIR"
  [ "$status" -eq 2 ]
  run "$LINT" --style "$BATS_TEST_TMPDIR/nope.md"
  [ "$status" -eq 2 ]
  run "$LINT" --style
  [ "$status" -eq 2 ]
}

@test "style: a task directory reports the style findings after the history ones" {
  walkthrough brief "$(printf -- '- `%s` `feat: a` — first.\n- `%s` `feat: b` — second.' "$A1" "$A2")"
  sed -i.bak 's/^x$/The total comes from `A` and `B` and `C`./' "$TASK/Walkthrough.md"
  run "$LINT" "$TASK"
  [ "$status" -eq 1 ] || { echo "$status $output"; return 1; }
  [[ "$output" == *"Walkthrough.md: style: identifier in ## What changed (## What changed)"* ]] || { echo "$output"; return 1; }
  [[ "$output" == *"Walkthrough.md: style: 3 identifiers in one sentence (## Summary)"* ]] || { echo "$output"; return 1; }
}

# Style findings reach the writer once (spec D-7): --current decides whether Done dispatches the
# writer again, so a style finding left after the implementing stage must not make the file stale.
@test "--current ignores a style finding: the file is current, with no output" {
  walkthrough deep "$(printf '### 1. `%s` — first\n\n### 2. `%s` — second' "$A1" "$A2")"
  sed -i.bak 's/^x$/The total comes from `A` and `B` and `C`./' "$TASK/Walkthrough.md"
  run "$LINT" --current "$TASK"
  [ "$status" -eq 0 ] || { echo "a style finding made the file stale: $status $output"; return 1; }
  [ -z "$output" ] || { echo "$output"; return 1; }
}

@test "the same style finding is still reported without --current" {
  walkthrough deep "$(printf '### 1. `%s` — first\n\n### 2. `%s` — second' "$A1" "$A2")"
  sed -i.bak 's/^x$/The total comes from `A` and `B` and `C`./' "$TASK/Walkthrough.md"
  run "$LINT" "$TASK"
  [ "$status" -eq 1 ] || { echo "$status $output"; return 1; }
  grep -qF 'Walkthrough.md: style: 3 identifiers in one sentence (## Summary)' <<<"$output" || { echo "$output"; return 1; }
  ! grep -qv '^Walkthrough.md: style: ' <<<"$output" || { echo "a finding other than style: $output"; return 1; }
}

# The threshold is the budget key words-per-sentence of the directory the file sits in.
fifteen() { printf 'one two three four five six seven eight nine ten eleven twelve thirteen fourteen fifteen.'; }

@test "style: a Task.md budget of 12 flags a 15-word sentence, the default passes it" {
  mkdir -p "$BATS_TEST_TMPDIR/d"
  styled x "$(fifteen)" x
  mv "$BATS_TEST_TMPDIR/w.md" "$BATS_TEST_TMPDIR/d/Walkthrough.md"
  run "$LINT" --style "$BATS_TEST_TMPDIR/d/Walkthrough.md"
  [ "$status" -eq 0 ] || { echo "$status $output"; return 1; }
  printf '[TASK_TYPE] = [BUG]\n[BUDGETS] = [words-per-sentence: 12]\n' >"$BATS_TEST_TMPDIR/d/Task.md"
  run "$LINT" --style "$BATS_TEST_TMPDIR/d/Walkthrough.md"
  [ "$status" -eq 1 ] || { echo "$status $output"; return 1; }
  [ "$output" = "Walkthrough.md: style: sentence of 15 words (## Summary)" ] || { echo "$output"; return 1; }
}

@test "style: a task directory reads its own words-per-sentence" {
  walkthrough brief "$(printf -- '- `%s` `feat: a` — first.\n- `%s` `feat: b` — second.' "$A1" "$A2")"
  sed -i.bak "s/^x\$/$(fifteen)/" "$TASK/Walkthrough.md"
  run "$LINT" "$TASK"
  [ "$status" -eq 0 ] || { echo "$status $output"; return 1; }
  printf '[TASK_TYPE] = [BUG]\n[BUDGETS] = [words-per-sentence: 12]\n' >"$TASK/Task.md"
  run "$LINT" "$TASK"
  [ "$status" -eq 1 ] || { echo "$status $output"; return 1; }
  grep -qF 'Walkthrough.md: style: sentence of 15 words (## What changed)' <<<"$output" || { echo "$output"; return 1; }
  [ "$(grep -c 'style: sentence of' <<<"$output")" -ge 1 ]
}

@test "style: a Device line is not prose" {
  styled x "$(printf '**Device:** %s\n\nShort.' "$(printf 'word %.0s' $(seq 40))")" x
  run "$LINT" --style "$BATS_TEST_TMPDIR/w.md"
  [ "$status" -eq 0 ] || { echo "$status $output"; return 1; }
}

@test "style: a resolver failure is exit 2 in both modes" {
  cp -R "$ROOT/scripts" "$BATS_TEST_TMPDIR/scripts"
  # task-ranges.sh shares the resolver: only the reading the style pass makes (its caller is the
  # lint's python, not a shell script) fails.
  printf '#!/usr/bin/env bash\ncase "$(ps -o comm= -p "$PPID")" in *ython*) exit 1 ;; esac\nexec "%s/scripts/resolve-settings.sh" "$@"\n' "$ROOT" >"$BATS_TEST_TMPDIR/scripts/resolve-settings.sh"
  chmod +x "$BATS_TEST_TMPDIR/scripts/resolve-settings.sh"
  styled x x x
  run "$BATS_TEST_TMPDIR/scripts/lint-walkthrough.sh" --style "$BATS_TEST_TMPDIR/w.md"
  [ "$status" -eq 2 ] || { echo "$status $output"; return 1; }
  [[ "$output" == *"lint-walkthrough.sh: resolve-settings.sh failed for $BATS_TEST_TMPDIR"* ]] || { echo "$output"; return 1; }
  walkthrough brief "$(printf -- '- `%s` `feat: a` — first.\n- `%s` `feat: b` — second.' "$A1" "$A2")"
  run "$BATS_TEST_TMPDIR/scripts/lint-walkthrough.sh" "$TASK"
  [ "$status" -eq 2 ] || { echo "$status $output"; return 1; }
  [[ "$output" == *"lint-walkthrough.sh: resolve-settings.sh failed for $TASK"* ]] || { echo "$output"; return 1; }
}

@test "a walkthrough ending in a closing block passes, and COVERS stays on line 2" {
  walkthrough deep "$(printf '### 1. `%s` — first\n\n### Bookkeeping\n\n- `%s` — one commit.' "$A1" "$A2")"
  printf '\n**Run:** drive_app=off; directive: «leave the cart package alone»\n**Device:** Phone B, set by this run\n' >>"$TASK/Walkthrough.md"
  [ "$(sed -n 2p "$TASK/Walkthrough.md" | cut -c1-9)" = '[COVERS] ' ]
  run "$LINT" "$TASK"
  [ "$status" -eq 0 ] || { echo "$status $output"; return 1; }
  [ -z "$output" ] || { echo "$output"; return 1; }
}
