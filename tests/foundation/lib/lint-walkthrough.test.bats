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
# out), $4 its Commits cell. Every section the depth requires is present.
walkthrough() {
  local range="${3:-$A1..$A2}" count="${4:-2}" s
  {
    printf '# Walkthrough\n[COVERS] = %s..%s\n\n' "$A1" "$A2"
    [ "$range" = - ] || printf '| Repository | Range | Commits | ± lines |\n|---|---|---|---|\n| `.` | `%s` | %s | +2/−0 |\n' "$range" "$count"
    for s in 'What changed' Glossary Summary 'Commit order' 'Plan vs. outcome' Commits 'How it works' 'Out of scope' Follow-ups; do
      [ "$1" = deep ] || case "$s" in Glossary | 'Commit order' | 'Out of scope') continue ;; esac
      printf '\n## %s\n\n' "$s"
      case "$s" in
        Commits) printf '%s\n' "$2" ;;
        'How it works') printf -- '- `%s` is only named here.\n' "$GONE" ;;
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
