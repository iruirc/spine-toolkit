#!/usr/bin/env bats
# changed: sweep skills workflows
# Split from task-documents.test.bats: the tests that walk the source trees.

setup() {
  ROOT="$(cd -- "$(dirname -- "$BATS_TEST_FILENAME")/../../.." && pwd)"
  SKILL="$ROOT/skills/task-documents/SKILL.md"
  ANCHORS='### Expected behaviour|### Questions for Research|### Acceptance'
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
    grep -qF 'by applying the spine-toolkit:task-documents skill, its Research.md section' <<<"$b" \
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
    stage_brief "$p" Plan | grep -qF 'by applying the spine-toolkit:task-documents skill, its Plan.md section' \
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
  grep -qF "task-documents skill, its Research.md section for the short answer and its rules for every document" <<<"$b" || { echo "profile-research.js: no pointer at the skill"; return 1; }
  ! grep -qF 'Questions for Research' <<<"$b" || { echo "profile-research.js: a research deliverable is held to a step's questions"; return 1; }
  bullet research Research | grep -qF "\`task-documents\` skill's rules for every document" \
    || { echo "workflow-research/SKILL.md: no pointer at the skill"; return 1; }
}

@test "Reproduce points at the skill only inside its lite fold" {
  n="$(stage_brief bug Reproduce | grep -o 'task-documents' | wc -l | tr -d ' ')"
  [ "$n" -eq 1 ] || { echo "Reproduce names the skill $n time(s), expected exactly the lite fold"; return 1; }
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

@test "writers of a Task.md never raise a ceiling: task-new, the epic skill and the epic planner say so" {
  sentence="A \`[BUDGETS]\` entry is the owner's word: never write one to raise a ceiling."
  grep -qF -- "$sentence" "$ROOT/skills/task-new/SKILL.md" || { echo "task-new/SKILL.md does not carry the sentence"; return 1; }
  grep -qF -- "$sentence" "$ROOT/skills/workflow-epic/SKILL.md" || { echo "workflow-epic/SKILL.md does not carry the sentence"; return 1; }
  plain="A [BUDGETS] entry is the owner's word: never write one to raise a ceiling."
  stage_brief epic Plan | grep -qF -- "$plain" || { echo "profile-epic.js: the Plan brief does not carry the sentence"; return 1; }
}

@test "the two reader skills keep their own sentences within thirty words" {
  for s in artifact-reader task-documents; do
    d="$BATS_TEST_TMPDIR/$s"
    mkdir -p "$d"
    cp "$ROOT/skills/$s/SKILL.md" "$d/Research.md"
    out="$("$ROOT/scripts/lint-artifact-readability.sh" --words-per-sentence 30 "$d/Research.md" | grep ': sentence: ' || true)"
    # The Style rules of artifact-reader are pinned by their leads; any other long sentence is a finding.
    out="$(grep -v '(Style)$' <<<"$out" || true)"
    [ -z "$out" ] || { echo "$s: $out"; return 1; }
  done
}
