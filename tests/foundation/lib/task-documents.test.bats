#!/usr/bin/env bats
# A task's documents are written by one agent and read by another who never saw the research.
# This suite holds the rule's text and every surface that points at it: the step template,
# task-new, and the briefs of both dispatch forms.

setup() {
  ROOT="$(cd -- "$(dirname -- "$BATS_TEST_FILENAME")/../../.." && pwd)"
  SKILL="$ROOT/skills/task-documents/SKILL.md"
  ANCHORS='### Expected behaviour|### Questions for Research|### Acceptance'
}

@test "the skill exists and resolves under its own name" {
  [ -f "$SKILL" ] || { echo "no skills/task-documents/SKILL.md"; return 1; }
  grep -q '^name: task-documents$' "$SKILL" || { echo "frontmatter name is not task-documents"; return 1; }
}

@test "the skill carries every section the writers apply" {
  for h in 'Layers' 'Rules for every document' 'Task.md of a root task' 'Task.md of a step' 'Research.md' 'Plan.md' 'Worked example'; do
    grep -qxF "## $h" "$SKILL" || { echo "no ## $h"; return 1; }
  done
}

@test "the skill names the three anchors and what a dash needs" {
  IFS='|' read -r a b c <<<"$ANCHORS"
  for anchor in "$a" "$b" "$c"; do
    grep -qF "\`$anchor\`" "$SKILL" || { echo "the skill never names $anchor"; return 1; }
  done
  grep -qF '`— <reason>`' "$SKILL" || { echo "a dash with no reason is not ruled out"; return 1; }
}

@test "the skill states that a document decides nothing its source did not" {
  grep -qF 'A document decides nothing its source did not.' "$SKILL" \
    || { echo "a writer may settle a question nobody settled"; return 1; }
  grep -qF '"Decided at this step" with no options is a defect' "$SKILL" \
    || { echo "a declared-but-empty decision still reads as one"; return 1; }
}

@test "the skill stays within its budget and ships no locales" {
  n="$(wc -l <"$SKILL" | tr -d ' ')"
  [ "$n" -le 200 ] || { echo "the skill runs to $n lines, budget 200"; return 1; }
  [ ! -d "$ROOT/skills/task-documents/locales" ] || { echo "task-documents must not carry locales/"; return 1; }
}

@test "both registries of core skill names list task-documents" {
  grep -qF '`task-documents`' "$ROOT/.claude/CLAUDE.md" || { echo ".claude/CLAUDE.md does not list it"; return 1; }
  awk '/^Do \*\*not\*\* name that skill `setup`/{f=1} f' "$ROOT/docs/building-a-platform.md" | grep -qF '`task-documents`' \
    || { echo "the platform guide's list of core skill names does not include it"; return 1; }
}

@test "the platform guide says the document shape comes from core" {
  grep -qF 'spine-toolkit:task-documents' "$ROOT/docs/building-a-platform.md" \
    || { echo "a platform author is never told whose shape an artifact follows"; return 1; }
}

@test "the step template carries the three anchors inside ## 3. [Task], in order" {
  got="$(awk '/^## 3\. \[Task\]$/{f=1;next} f&&/^## /{exit} f&&/^### /' "$ROOT/templates/task-md/task-step.md" | paste -sd'|' -)"
  [ "$got" = "$ANCHORS" ] || { echo "anchors under ## 3. [Task]: '$got'"; return 1; }
}

@test "the root template carries none of the anchors" {
  ! grep -q '^### ' "$ROOT/templates/task-md/task-root.md" || { echo "the root template grew an anchor"; return 1; }
}

@test "task-new applies the skill to a root task and to a step" {
  N="$ROOT/skills/task-new/SKILL.md"
  root="$(awk '/^## Process — root task$/{f=1;next} f&&/^## /{exit} f' "$N")"
  step="$(awk '/^## Process — step task/{f=1;next} f&&/^## /{exit} f' "$N")"
  grep -qF "section on a root task's \`Task.md\`" <<<"$root" || { echo "the root process never applies the skill"; return 1; }
  grep -qF "section on a step's \`Task.md\`" <<<"$step" || { echo "the step process never applies the skill"; return 1; }
}

@test "task-new verifies a step's three anchors" {
  grep -qF 'For step tasks also verify `[STATUS] = `, `### Expected behaviour`, `### Questions for Research` and `### Acceptance`.' "$ROOT/skills/task-new/SKILL.md" \
    || { echo "a step whose anchor was translated passes task-new's own check"; return 1; }
}
