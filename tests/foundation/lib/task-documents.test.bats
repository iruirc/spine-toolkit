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
  for h in 'Layers' 'Rules for every document' 'Task.md of a root task' 'Task.md of a step' 'Research.md' 'Plan.md' \
    'Done.md' 'Review.md' 'Questions.md' 'Validation.md' 'Worked example'; do
    grep -qxF "## $h" "$SKILL" || { echo "no ## $h"; return 1; }
  done
}

# A skill section, from its heading to the next one; the templates inside a section are fenced, so a
# heading inside a fence does not end it.
doc_section() { # $1 = heading text
  awk -v h="## $1" '/^```/{fence=!fence} !fence&&$0==h{f=1;next} f&&!fence&&/^## /{exit} f' "$SKILL"
}

@test "the skill speaks of the documents a task leaves, not of three" {
  desc="$(sed -n 's/^description: //p' "$SKILL")"
  ! grep -qF 'three documents' <<<"$desc" || { echo "the description still speaks of three documents"; return 1; }
  ! grep -qF 'Task.md, Research.md or Plan.md:' <<<"$desc" || { echo "the description still lists three files only"; return 1; }
  for f in Done.md Review.md Questions.md Validation.md; do
    grep -qF "$f" <<<"$desc" || { echo "the description never names $f"; return 1; }
  done
  grep -qF 'the documents a task leaves' "$SKILL" || { echo "the opening never speaks of the documents a task leaves"; return 1; }
}

@test "the layer table still divides Task.md, Research.md and Plan.md" {
  grep -qxF '| Document | Answers | Carries | Never carries |' "$SKILL" || { echo "the layer table's header is gone"; return 1; }
  for d in Task.md Research.md Plan.md; do
    grep -q "^| \`$d\` | " "$SKILL" || { echo "the layer table has no row for $d"; return 1; }
  done
}

@test "Research.md opens with a short answer to each question for Research" {
  s="$(doc_section Research.md)"
  grep -qF 'opens with `## Short answer`' <<<"$s" || { echo "Research.md is not told to open with ## Short answer"; return 1; }
  grep -qF 'how it is ensured' <<<"$s" || { echo "the property table's cell rule is missing"; return 1; }
}

@test "Plan.md is two parts: for the owner, then for the implementer" {
  s="$(doc_section Plan.md)"
  grep -qF '`## For the owner`' <<<"$s" || { echo "no ## For the owner"; return 1; }
  grep -qF '`## For the implementer`' <<<"$s" || { echo "no ## For the implementer"; return 1; }
  [ "$(grep -bo '## For the owner' <<<"$s" | head -1 | cut -d: -f1)" -lt "$(grep -bo '## For the implementer' <<<"$s" | head -1 | cut -d: -f1)" ] \
    || { echo "the implementer's part is named before the owner's"; return 1; }
  grep -qF 'the progress table stays a top-level table' <<<"$s" || { echo "the progress table's place is not fixed"; return 1; }
  grep -qF '`**Verification:**`' <<<"$s" || { echo "the implementer's part never names the Verification lines"; return 1; }
  grep -qF 'lite' <<<"$s" || { echo "the lite ceiling is not mentioned"; return 1; }
}

@test "Done.md names its sections in order, then the closing block" {
  s="$(doc_section Done.md)"
  want='`## Summary`|`## Why`|`## What is left and risks`|`## Objections`|`## Estimate retrospective`|`## Review findings closed`'
  got="$(grep -oE "$(sed 's/`//g; s/## //g; s/^/`## (/; s/$/)`/' <<<"$want")" <<<"$s" | awk '!seen[$0]++' | paste -sd'|' -)"
  [ "$got" = "$want" ] || { echo "Done.md sections: '$got'"; return 1; }
  grep -qF 'closing block' <<<"$s" || { echo "Done.md never names the closing block"; return 1; }
}

@test "Done.md says what shrinks at lite" {
  s="$(doc_section Done.md)"
  grep -qF 'At `lite` the sections stay in the same order' <<<"$s" || { echo "Done.md gives no lite guidance"; return 1; }
  grep -qF 'never a list of commits' <<<"$s" || { echo "a lite section may still be a list of commits"; return 1; }
  grep -qw 'lite' <<<"$s" || { echo "Done.md never names lite"; return 1; }
}

@test "every Review.md finding carries an Impact line" {
  s="$(doc_section Review.md)"
  grep -qF '`**Impact:**`' <<<"$s" || { echo "no **Impact:**"; return 1; }
  grep -qF '`[REVIEW_STATUS] = …`' <<<"$s" || { echo "the status line is not kept first"; return 1; }
}

@test "a Questions.md entry holds the question, the decision, the rejected options, who and when" {
  s="$(doc_section Questions.md)"
  grep -qF -- '- [<stage>] <id> — **Question:** <text>' <<<"$s" || { echo "the entry form is missing"; return 1; }
  for l in '**Decision:**' '**Rejected:**' '**Decided by:**'; do
    grep -qF -- "$l" <<<"$s" || { echo "the entry lacks $l"; return 1; }
  done
  grep -qF 'RESOLVED' <<<"$s" || { echo "the old RESOLVED tail is not ruled out"; return 1; }
}

@test "Validation.md cites its logs from the task folder and keeps contract fields out of the summary" {
  s="$(doc_section Validation.md)"
  grep -qF 'validation-evidence/' <<<"$s" || { echo "logs are not cited from validation-evidence/"; return 1; }
  for f in validation_status VALIDATION_STATUS manual_checks_changed; do
    grep -qF "$f" <<<"$s" || { echo "the summary rule never names $f"; return 1; }
  done
}

@test "a step writes an epic decision as the sentence, the label in brackets" {
  s="$(doc_section 'Task.md of a step')"
  grep -qF 'the label in brackets' <<<"$s" || { echo "a step may cite an epic decision by its label alone"; return 1; }
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

# A stage's brief in a profile script, from its banner to the next banner.
stage_brief() { # $1 = profile, $2 = stage
  awk -v s="// ── $2 " 'index($0,s)==1{p=1;next} p&&/^\/\/ ── /{exit} p' "$ROOT/workflows/profile-$1.js"
}
# A stage's own bullet in a Method B skill.
bullet() { # $1 = profile, $2 = stage
  awk -v s="- **$2**" 'index($0,s)==1{p=1;print;next} p&&/^- \*\*/{exit} p' "$ROOT/skills/workflow-$1/SKILL.md"
}
scale_section() { # $1 = profile
  awk '/^## 2a\. Scale$/{f=1;next} f&&/^## /{exit} f' "$ROOT/skills/workflow-$1/SKILL.md"
}
INVESTIGATING='feature:Research bug:Diagnose refactor:Analyze test:Analyze epic:Research'

@test "every investigating stage points its writer at the Research.md section — Method A" {
  for pair in $INVESTIGATING; do
    b="$(stage_brief "${pair%%:*}" "${pair##*:}")"
    grep -qF 'by applying the task-documents skill, its Research.md section' <<<"$b" \
      || { echo "profile-${pair%%:*}.js ${pair##*:}: no pointer at the skill"; return 1; }
  done
}

@test "every investigating stage points its writer at the Research.md section — Method B" {
  for pair in $INVESTIGATING; do
    bullet "${pair%%:*}" "${pair##*:}" | grep -qF 'applies the `task-documents` skill, its `Research.md` section' \
      || { echo "workflow-${pair%%:*}/SKILL.md ${pair##*:}: no pointer at the skill"; return 1; }
  done
}

@test "every Plan stage points at the Plan.md section — both forms" {
  for p in feature bug refactor test epic; do
    stage_brief "$p" Plan | grep -qF 'by applying the task-documents skill, its Plan.md section' \
      || { echo "profile-$p.js Plan: no pointer at the skill"; return 1; }
    bullet "$p" Plan | grep -qF 'applies the `task-documents` skill, its `Plan.md` section' \
      || { echo "workflow-$p/SKILL.md Plan: no pointer at the skill"; return 1; }
  done
}

@test "a lite fold applies the Research.md section to the folded section — both forms" {
  for p in feature refactor test; do
    stage_brief "$p" Plan | grep -qF "That section is Research.md folded into Plan.md, so the task-documents skill's Research.md section applies" \
      || { echo "profile-$p.js: the lite Plan brief drops the Research.md rules"; return 1; }
    scale_section "$p" | grep -qF 'folded into `Plan.md`' \
      || { echo "workflow-$p/SKILL.md: the lite fold drops the Research.md rules"; return 1; }
  done
  stage_brief bug Reproduce | grep -qF "That section is Research.md folded into Reproduce.md, so the task-documents skill's Research.md section applies" \
    || { echo "profile-bug.js: the lite Diagnosis section drops the Research.md rules"; return 1; }
  scale_section bug | grep -qF 'folded into `Reproduce.md`' \
    || { echo "workflow-bug/SKILL.md: the lite fold drops the Research.md rules"; return 1; }
}

@test "the epic's Plan writes each step's Task.md by the skill, under the contract's ceiling — both forms" {
  b="$(stage_brief epic Plan)"
  grep -qF "its section on a step's Task.md" <<<"$b" || { echo "profile-epic.js: steps are written without the skill"; return 1; }
  grep -qF "\${BUDGETS['Task.md']}" <<<"$b" || { echo "profile-epic.js: the step ceiling is not read from budgets"; return 1; }
  IFS='|' read -r a c d <<<"$ANCHORS"
  for anchor in "$a" "$c" "$d"; do
    grep -qF "$anchor" <<<"$b" || { echo "profile-epic.js: the brief never names $anchor"; return 1; }
  done
  m="$(bullet epic Plan)"
  grep -qF -- '--task-docs' <<<"$m" || { echo "workflow-epic/SKILL.md: no word that the steps are measured"; return 1; }
  grep -qF '`budgets`' <<<"$m" || { echo "workflow-epic/SKILL.md: the ceiling does not come from the contract"; return 1; }
}

@test "RESEARCH applies only the rules for every document — both forms" {
  b="$(stage_brief research Research)"
  grep -qF "task-documents skill's rules for every document" <<<"$b" || { echo "profile-research.js: no pointer at the skill"; return 1; }
  ! grep -qF 'Questions for Research' <<<"$b" || { echo "profile-research.js: a research deliverable is held to a step's questions"; return 1; }
  bullet research Research | grep -qF "\`task-documents\` skill's rules for every document" \
    || { echo "workflow-research/SKILL.md: no pointer at the skill"; return 1; }
}

@test "Reproduce points at the skill only inside its lite fold" {
  n="$(stage_brief bug Reproduce | grep -o 'task-documents' | wc -l | tr -d ' ')"
  [ "$n" -eq 1 ] || { echo "Reproduce names the skill $n time(s), expected exactly the lite fold"; return 1; }
}

@test "exactly five scripts carry each of the two stage clauses" {
  # Vacuity guard: without it the loops above iterate over a list someone shortened.
  n="$(grep -l 'by applying the task-documents skill, its Research.md section' "$ROOT"/workflows/profile-*.js | wc -l | tr -d ' ')"
  [ "$n" -eq 5 ] || { echo "$n script(s) carry the Research.md clause, expected 5"; return 1; }
  n="$(grep -l 'by applying the task-documents skill, its Plan.md section' "$ROOT"/workflows/profile-*.js | wc -l | tr -d ' ')"
  [ "$n" -eq 5 ] || { echo "$n script(s) carry the Plan.md clause, expected 5"; return 1; }
}

@test "every panel lens is pointed at the skill" {
  for pair in bug:Diagnose test:Analyze; do
    stage_brief "${pair%%:*}" "${pair##*:}" | grep -qF "apply the task-documents skill's Research.md section to what you look for" \
      || { echo "profile-${pair%%:*}.js ${pair##*:}: the lens is never pointed at the skill"; return 1; }
  done
  # FEATURE's lens is the security lens, whose brief lives in the shared prelude (securityLens).
  pre="$(awk '/^\/\/ ── prelude ─/{f=1} f{print} /^\/\/ ── end prelude ─/{exit}' "$ROOT/workflows/profile-feature.js")"
  grep -qF "apply the task-documents skill's Research.md section to what you look for" <<<"$pre" \
    || { echo "the security lens in the prelude is never pointed at the skill"; return 1; }
}

@test "the step process verifies structural anchors before reporting" {
  step="$(awk '/^## Process — step task/{f=1;next} f&&/^## /{exit} f' "$ROOT/skills/task-new/SKILL.md")"
  grep -qF 'step 10 of the root-task process' <<<"$step" \
    || { echo "the step process reports without verifying its anchors"; return 1; }
}

@test "workflow-epic's Auto mode names --task-docs" {
  sect="$(awk '/^## 4\. Auto mode$/{f=1;next} f&&/^## /{exit} f' "$ROOT/skills/workflow-epic/SKILL.md")"
  grep -qF -- '--task-docs' <<<"$sect" || { echo "Auto mode never mentions --task-docs"; return 1; }
}

@test "no brief retells the skill's rules" {
  # The rules live in the skill; a copy in a brief drifts from it.
  for phrase in 'corrupted state' 'what a user would see' 'superseded revisions' 'meaning before a code' 'every question under the task'; do
    ! grep -rqF "$phrase" "$ROOT"/workflows/profile-*.js "$ROOT"/skills/workflow-*/SKILL.md \
      || { echo "a brief still retells: $phrase"; return 1; }
  done
}

# Acceptance of milestone 6 (EPIC 548): the step template's Stack, Logs and StackTrace headings stayed
# empty in every step written from a plan, and a second copy of headings was appended below them.
@test "a step's Task.md carries no empty Stack, Logs or StackTrace and fills its headings in place" {
  t="$ROOT/templates/task-md/task-step.md"
  for h in '## 4. [Stack]' '## 5. [Logs]' '## 6. [StackTrace]'; do
    ! grep -qxF "$h" "$t" || { echo "the step template still has $h"; return 1; }
  done
  step="$(awk '/^## Process — step task/{f=1;next} f&&/^## /{exit} f' "$ROOT/skills/task-new/SKILL.md")"
  grep -qF 'never append a second copy of a heading' <<<"$step" || { echo "no in-place rule"; return 1; }
  grep -qF 'only the axes that differ' <<<"$step" || { echo "no rule for a step's own Stack"; return 1; }
}

@test "writers of a Task.md never raise a ceiling: task-new, the epic skill and the epic planner say so" {
  sentence="A \`[BUDGETS]\` entry is the owner's word: never write one to raise a ceiling."
  grep -qF -- "$sentence" "$ROOT/skills/task-new/SKILL.md" || { echo "task-new/SKILL.md does not carry the sentence"; return 1; }
  grep -qF -- "$sentence" "$ROOT/skills/workflow-epic/SKILL.md" || { echo "workflow-epic/SKILL.md does not carry the sentence"; return 1; }
  plain="A [BUDGETS] entry is the owner's word: never write one to raise a ceiling."
  stage_brief epic Plan | grep -qF -- "$plain" || { echo "profile-epic.js: the Plan brief does not carry the sentence"; return 1; }
}
