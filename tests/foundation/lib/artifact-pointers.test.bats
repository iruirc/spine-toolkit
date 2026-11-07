#!/usr/bin/env bats
# The documents a task leaves are shaped by `task-documents` and read by the rules of `artifact-reader`.
# A stage skill that writes one of them has to say so, or the writer never meets either skill.
# This suite holds every surface that must name them, the stage bullets that write each document,
# and the Questions.md log form the orchestrator and workflow-review write.

setup() {
  ROOT="$(cd -- "$(dirname -- "$BATS_TEST_FILENAME")/../../.." && pwd)"
  PROFILES='bug feature refactor test quick epic research review'
}

# A stage's own bullet in a Method B skill.
bullet() { # $1 = profile, $2 = stage
  awk -v s="- **$2**" 'index($0,s)==1{p=1;print;next} p&&/^- \*\*/{exit} p' "$ROOT/skills/workflow-$1/SKILL.md"
}
scale_section() { # $1 = profile
  awk '/^## 2a\. Scale$/{f=1;next} f&&/^## /{exit} f' "$ROOT/skills/workflow-$1/SKILL.md"
}

# Files that must name one of the two skills. docs-route and ops-checklist join in a later change.
POINTERS='skills/workflow-bug skills/workflow-feature skills/workflow-refactor skills/workflow-test skills/workflow-quick skills/workflow-epic skills/workflow-research skills/workflow-review skills/orchestrator'

@test "the eight workflow skills and the orchestrator name artifact-reader or task-documents" {
  n=0
  for d in $POINTERS; do
    grep -qE '`(artifact-reader|task-documents)`|skills/(artifact-reader|task-documents)/SKILL\.md' "$ROOT/$d/SKILL.md" \
      || { echo "$d/SKILL.md names neither artifact-reader nor task-documents"; return 1; }
    n=$((n + 1))
  done
  [ "$n" -eq 9 ] || { echo "checked $n file(s), expected 9"; return 1; }
}

@test "every workflow skill names artifact-reader for the style of the documents it writes" {
  for p in $PROFILES; do
    grep -qF '`artifact-reader`' "$ROOT/skills/workflow-$p/SKILL.md" || { echo "workflow-$p/SKILL.md never names artifact-reader"; return 1; }
  done
  grep -qF '`artifact-reader`' "$ROOT/skills/orchestrator/SKILL.md" || { echo "orchestrator never names artifact-reader"; return 1; }
}

@test "every Plan, Review and Done bullet that writes the document applies its section and names artifact-reader" {
  # profile:stage:document
  for t in bug:Plan:Plan feature:Plan:Plan refactor:Plan:Plan test:Plan:Plan epic:Plan:Plan quick:Edit:Plan \
           bug:Review:Review feature:Review:Review refactor:Review:Review test:Review:Review quick:Review:Review research:Review:Review review:Review:Review \
           bug:Done:Done feature:Done:Done refactor:Done:Done test:Done:Done quick:Done:Done epic:Done:Done research:Done:Done; do
    IFS=: read -r p s d <<<"$t"
    b="$(bullet "$p" "$s")"
    [ -n "$b" ] || { echo "workflow-$p has no $s bullet"; return 1; }
    grep -qE "appl(y|ies|ying) the \`task-documents\` skill, its \`$d\.md\` section" <<<"$b" \
      || { echo "workflow-$p/SKILL.md $s: the bullet never applies the task-documents $d.md section"; return 1; }
    grep -qF '`artifact-reader`' <<<"$b" || { echo "workflow-$p/SKILL.md $s: the bullet never names artifact-reader"; return 1; }
  done
}

@test "each Review and Done bullet says it is written by applying the section" {
  for p in bug feature refactor test quick research review; do
    bullet "$p" Review | grep -qF 'by applying the `task-documents` skill, its `Review.md` section' \
      || { echo "workflow-$p/SKILL.md Review: no 'by applying' clause"; return 1; }
  done
  for p in bug feature refactor test quick epic research; do
    bullet "$p" Done | grep -qF 'by applying the `task-documents` skill, its `Done.md` section' \
      || { echo "workflow-$p/SKILL.md Done: no 'by applying' clause"; return 1; }
  done
}

@test "every Research.md bullet names the short answer once, first" {
  for t in feature:Research bug:Diagnose refactor:Analyze test:Analyze epic:Research research:Research; do
    p="${t%%:*}"
    b="$(bullet "$p" "${t##*:}")"
    [ "$(grep -oF '## Short answer' <<<"$b" | wc -l | tr -d ' ')" -eq 1 ] \
      || { echo "workflow-$p/SKILL.md ${t##*:}: ## Short answer is not named exactly once"; return 1; }
    grep -qE '`## Short answer`.{0,40}(first|opens)|(first|opens).{0,60}`## Short answer`' <<<"$b" \
      || { echo "workflow-$p/SKILL.md ${t##*:}: the short answer is not said to come first"; return 1; }
  done
}

@test "the stage names its own Research.md headings after the short answer" {
  b="$(bullet feature Research)"
  for h in '## Requirements' '## Landscape'; do
    grep -qF "\`$h\`" <<<"$b" || { echo "feature Research: no $h"; return 1; }
  done
  grep -qF 'appended as sections named for what they hold' <<<"$b" || { echo "feature Research: the analysis sections are not left to their writer"; return 1; }
  ! grep -qF 'Architectural Analysis' <<<"$b" || { echo "feature Research: a second heading set is still named"; return 1; }
  b="$(bullet epic Research)"
  for h in '## Requirements' '## Landscape'; do
    grep -qF "\`$h\`" <<<"$b" || { echo "epic Research: no $h"; return 1; }
  done
  b="$(bullet refactor Analyze)"
  grep -qF '`## Landscape (current)`' <<<"$b" || { echo "refactor Analyze: no ## Landscape (current)"; return 1; }
  grep -qF '`## Landscape (target)`' <<<"$b" || { echo "refactor Analyze: no ## Landscape (target)"; return 1; }
  b="$(bullet research Research)"
  for h in '## Goal' '## Method' '## Findings' '## Follow-up'; do
    grep -qF "\`$h\`" <<<"$b" || { echo "research Research: no $h"; return 1; }
  done
}

@test "a lite fold is the first section under the implementer's part of Plan.md, in both forms" {
  for p in feature refactor test; do
    s="$(scale_section "$p")"
    grep -qF 'first section under `## For the implementer`' <<<"$s" \
      || { echo "workflow-$p/SKILL.md: the lite fold is not placed under ## For the implementer"; return 1; }
    ! grep -qE '`Plan.md` opens with a `## (Research|Analysis)`' <<<"$s" \
      || { echo "workflow-$p/SKILL.md: the lite fold still opens Plan.md"; return 1; }
    grep -qF 'first section under "## For the implementer"' "$ROOT/workflows/profile-$p.js" \
      || { echo "profile-$p.js: the lite fold is not placed under ## For the implementer"; return 1; }
    ! grep -qE 'Open \$\{DIR\}/Plan.md with a "## (Research|Analysis)"' "$ROOT/workflows/profile-$p.js" \
      || { echo "profile-$p.js: the lite fold still opens Plan.md"; return 1; }
  done
}

@test "the orchestrator writes a resolved or deferred item to the log with its question" {
  s="$ROOT/skills/orchestrator/SKILL.md"
  grep -qF '`## Open Questions Log`' "$s" || { echo "the orchestrator never names the log heading"; return 1; }
  line="$(grep -F 'an `## Open Questions Log` section is appended to `Questions.md`' "$s")"
  [ -n "$line" ] || { echo "the log paragraph is gone"; return 1; }
  for token in '- [<stage>] <id> — **Question:** <item text>' '`**Decision:**`' '`deferred`' '`**Rejected:**`' '`none offered`' \
               '`**Decided by:** owner, <ISO date>`' 'skills/task-documents/SKILL.md'; do
    grep -qF -- "$token" <<<"$(tr '\n' ' ' <"$s")" || { echo "the orchestrator's log entry lacks: $token"; return 1; }
  done
  ! grep -qF 'RESOLVED: answer | DEFERRED' "$s" || { echo "the orchestrator still writes the old log form"; return 1; }
  ! grep -qF '[<section>] <id>' "$s" || { echo "the old entry still carries a section"; return 1; }
}

@test "the original bullet keeps its closing prefix while the log entry changes" {
  s="$(tr '\n' ' ' <"$ROOT/skills/orchestrator/SKILL.md")"
  grep -qF 'the original bullet is prefixed with `[RESOLVED]`' <<<"$s" || { echo "the RESOLVED prefix of the original bullet is gone"; return 1; }
  grep -qF 'prefix the original bullet with `[DEFERRED]`' <<<"$s" || { echo "the DEFERRED prefix of the original bullet is gone"; return 1; }
}

@test "workflow-review writes the disputed points of a DISCUSSION in the same log form" {
  s="$(tr '\n' ' ' <"$ROOT/skills/workflow-review/SKILL.md")"
  for token in '`## Open Questions Log`' '- [Review] <id> — **Question:** <disputed point>' '`**Decision:**`' '`**Rejected:**`' '`**Decided by:** owner, <ISO date>`' \
               'skills/task-documents/SKILL.md'; do
    grep -qF -- "$token" <<<"$s" || { echo "workflow-review lacks: $token"; return 1; }
  done
  ! grep -qF 'Discussion from Review' <<<"$s" || { echo "workflow-review still writes the dated discussion section"; return 1; }
}
