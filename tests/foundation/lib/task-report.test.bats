#!/usr/bin/env bats
# The report is one topic document a task leaves in a documentation component's places, holding
# its numbers and conclusions whole; every other artifact links to it. Every stage of every profile
# points at one section of the task-report skill in one sentence, so this suite holds the section
# names those sentences rely on, the tokens the lint reads, and the worked examples.

setup() {
  ROOT="$(cd -- "$(dirname -- "$BATS_TEST_FILENAME")/../../.." && pwd)"
  SKILL="$ROOT/skills/task-report/SKILL.md"
  EXAMPLES="$ROOT/skills/task-report/examples"
}

ru() { python3 -c 'import sys; sys.stdout.write(sys.argv[1].encode().decode("unicode_escape"))' "$1"; }
skill_section() { awk -v h="$1" '$0==h{f=1;next} f&&/^## /{exit} f' "$SKILL"; }

@test "the skill exists and resolves under its own name" {
  [ -f "$SKILL" ] || { echo "no skills/task-report/SKILL.md"; return 1; }
  grep -q '^name: task-report$' "$SKILL" || { echo "frontmatter name is not task-report"; return 1; }
  grep -q '^description: "Use at Plan to decide whether a task leaves a topic report' "$SKILL" \
    || { echo "the description does not open with the Plan decision"; return 1; }
}

@test "the skill carries every section the stages point at" {
  for h in '## When' '## Where' '## The decision' '## The document' '## Updating' '## Links' '## Review'; do
    grep -qx -- "$h" "$SKILL" || { echo "the skill has no $h"; return 1; }
  done
}

@test "the decision fields are spelled once, with all four values" {
  d="$(skill_section '## The decision')"
  grep -qF '[REPORT_DECISION] = needed | update | not-needed | unplaced' <<<"$d" \
    || { echo "## The decision does not spell the four values"; return 1; }
  grep -qF '[REPORT_PATH] = ' <<<"$d" || { echo "## The decision does not spell [REPORT_PATH]"; return 1; }
  for token in '## For the owner' 'Research.md'; do
    grep -qF -- "$token" <<<"$d" || { echo "## The decision does not name $token"; return 1; }
  done
  [ "$(grep -cF '[REPORT_DECISION] = needed | update | not-needed | unplaced' "$SKILL")" -eq 1 ] \
    || { echo "the four values are spelled more than once"; return 1; }
}

@test "When names the three criteria and that on forbids not-needed" {
  w="$(skill_section '## When')"
  [ -n "$w" ] || { echo "no ## When"; return 1; }
  for token in 'three or more' 'more than one table' 'other steps or tasks' '.step/'; do
    grep -qF -- "$token" <<<"$w" || { echo "## When does not name $token"; return 1; }
  done
  grep -qE '`on`.*`not-needed`' <<<"$w" || { echo "## When does not say on forbids not-needed"; return 1; }
  for type in QUICK BUG REFACTOR REVIEW; do
    grep -qF "$type" <<<"$w" || { echo "## When does not name $type"; return 1; }
  done
}

@test "Where says places, update, and Questions.md" {
  w="$(skill_section '## Where')"
  [ -n "$w" ] || { echo "no ## Where"; return 1; }
  for token in '`places`' '`covers`' 'docs-route.sh route' '`update`' '`unplaced`' 'Questions.md' '[DOCS] = [off]' '`task-documents`'; do
    grep -qF -- "$token" <<<"$w" || { echo "## Where does not name $token"; return 1; }
  done
}

@test "The document requires the slug, not a task path" {
  d="$(skill_section '## The document')"
  [ -n "$d" ] || { echo "no ## The document"; return 1; }
  for token in 'slug' 'Tasks/<STATUS>' 'Where sources disagree' '`artifact-reader`' \
               'examples/report.en.md' 'examples/report.ru.md'; do
    grep -qF -- "$token" <<<"$d" || { echo "## The document does not name $token"; return 1; }
  done
}

@test "Updating keeps the old numbers and labels the new ones by step" {
  u="$(skill_section '## Updating')"
  [ -n "$u" ] || { echo "no ## Updating"; return 1; }
  for token in 'slug' 'Where sources disagree'; do
    grep -qF -- "$token" <<<"$u" || { echo "## Updating does not name $token"; return 1; }
  done
}

@test "Links carries the six Done steps, the ratchet and the lint, for both methods" {
  l="$(skill_section '## Links')"
  [ -n "$l" ] || { echo "no ## Links"; return 1; }
  for n in 1 2 3 4 5 6; do
    grep -qE "^$n\. " <<<"$l" || { echo "## Links has no step $n"; return 1; }
  done
  for token in 'scripts/lint-report-links.sh' 'ratchet' 'Method A' 'Method B' 'conventions/stage-dispatch.md' \
               'Questions.md' 'unplaced'; do
    grep -qF -- "$token" <<<"$l" || { echo "## Links does not name $token"; return 1; }
  done
}

@test "Review makes a diverging number blocking" {
  r="$(skill_section '## Review')"
  [ -n "$r" ] || { echo "no ## Review"; return 1; }
  grep -qF 'blocking' <<<"$r" || { echo "## Review does not make a diverging number blocking"; return 1; }
  grep -qF '## For Done' <<<"$r" || { echo "## Review does not route the finding to ## For Done"; return 1; }
}

@test "the skill names its neighbours" {
  for s in docs-route task-documents artifact-reader task-walkthrough; do
    grep -qF -- "- \`$s\`" "$SKILL" || { echo "the Related skills block does not name $s"; return 1; }
  done
}

@test "the skill ships no locales and is hidden" {
  [ ! -d "$ROOT/skills/task-report/locales" ] || { echo "task-report must not carry locales/"; return 1; }
  f="$ROOT/skills/task-report/agents/openai.yaml"
  [ -f "$f" ] || { echo "no agents/openai.yaml"; return 1; }
  grep -qF 'allow_implicit_invocation: false' "$f" || { echo "task-report is not hidden"; return 1; }
  grep -qF 'display_name: "Task Report"' "$f" || { echo "display_name is not Task Report"; return 1; }
}

@test "the examples are a pair of equal length and pass the report checks" {
  en="$EXAMPLES/report.en.md" ruf="$EXAMPLES/report.ru.md"
  [ -f "$en" ] && [ -f "$ruf" ] || { echo "the examples are missing"; return 1; }
  n_en="$(wc -l <"$en" | tr -d ' ')" n_ru="$(wc -l <"$ruf" | tr -d ' ')"
  [ "$n_en" -eq "$n_ru" ] || { echo "report.en.md has $n_en lines, report.ru.md $n_ru"; return 1; }
  [ "$n_en" -le 150 ] || { echo "the examples run to $n_en lines, over 150"; return 1; }
  grep -qE '^#{1,6} .*Where sources disagree' "$en" || { echo "report.en.md: no divergence heading"; return 1; }
  grep -qE "^#{1,6} .*$(ru '\u0413\u0434\u0435 \u0438\u0441\u0442\u043e\u0447\u043d\u0438\u043a\u0438 \u0440\u0430\u0441\u0445\u043e\u0434\u044f\u0442\u0441\u044f')" "$ruf" \
    || { echo "report.ru.md: no divergence heading"; return 1; }
  ! LC_ALL=C grep -q "$(printf '\xd0')\|$(printf '\xd1')" "$en" || { echo "report.en.md carries Cyrillic"; return 1; }
  for f in "$en" "$ruf"; do
    ! grep -qE 'Tasks/(ACTIVE|DONE|BACKLOG)' "$f" || { echo "$f: names a task by its path"; return 1; }
  done
  # The lint's own checks: a task that links to the example from Done.md and Plan.md passes.
  slug=02-notes-perf-app-baseline.step
  for f in "$en" "$ruf"; do
    proj="$BATS_TEST_TMPDIR/$(basename "$f")"
    mkdir -p "$proj/Documents" "$proj/Tasks/ACTIVE/$slug"
    cp "$f" "$proj/Documents/PerfBaseline.md"
    printf '# Plan\n\n[PerfBaseline](../../../Documents/PerfBaseline.md)\n\n## For the owner\n\n[REPORT_DECISION] = needed\n[REPORT_PATH] = Documents/PerfBaseline.md\n' \
      >"$proj/Tasks/ACTIVE/$slug/Plan.md"
    printf '# Done\n\n[PerfBaseline](../../../Documents/PerfBaseline.md)\n' >"$proj/Tasks/ACTIVE/$slug/Done.md"
    run "$ROOT/scripts/lint-report-links.sh" "$proj/Tasks/ACTIVE/$slug" --root "$proj"
    [ "$status" -eq 0 ] || { echo "$f: $output"; return 1; }
  done
}
