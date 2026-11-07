#!/usr/bin/env bats
# A writer of Done, Plan, Review or Research is told twice what the reader needs: to write it by the
# task-documents skill and the style of artifact-reader, and to run the readability lint once on the
# file and name what is left. Each brief says it in two sentences, with its own file and section.

setup() {
  ROOT="$(cd -- "$(dirname -- "$BATS_TEST_FILENAME")/../../.." && pwd)"
  LINT_CMD="Run \"\${core('scripts/lint-artifact-readability.sh')}\" --words-per-sentence \${BUDGETS['words-per-sentence']} \${DIR}/"
  LINT_TAIL=' once. Fix each finding once; do not run it again; name what is left in your summary.'
  STYLE_TAIL="; its Style and spine-toolkit:artifact-reader's override any brevity instruction in your agent body."
  WRITE_HEAD='Write it by applying the spine-toolkit:task-documents skill, its '
}

# A stage's briefs in a profile script, from its banner to the next banner.
stage_brief() { # $1 = profile, $2 = stage
  awk -v s="// ── $2 " 'index($0,s)==1{p=1;next} p&&/^\/\/ ── /{exit} p' "$ROOT/workflows/profile-$1.js"
}
# doneBrief, as the shared prelude defines it.
done_brief() { # $1 = profile
  awk '/^const doneBrief = /{p=1} p{print} p&&/^\)$/{exit}' "$ROOT/workflows/profile-$1.js"
}
count() { grep -oF -- "$1" | wc -l | tr -d ' '; }

# script:stage:file:section sentence. The file's section opens the sentence; Research in a RESEARCH
# task is the deliverable, so it takes the short answer and the rules every document follows.
RESEARCH_BRIEFS='feature:Research bug:Diagnose refactor:Analyze test:Analyze epic:Research'
PLAN_BRIEFS='feature:Plan bug:Plan refactor:Plan test:Plan epic:Plan'
REVIEW_BRIEFS='feature:Review bug:Review refactor:Review test:Review quick:Review research:Review review:Review'
DONE_PROFILES='feature bug refactor test quick epic research review'

sentence_1() { # $1 = Research | Plan | Review | Done
  case "$1" in
    Review) printf '%s%s' "${WRITE_HEAD}Review.md section, whose Impact rule gives every finding an **Impact:** line" "$STYLE_TAIL" ;;
    Plan) printf '%s%s' "${WRITE_HEAD}Plan.md section, which puts the progress table under ## For the owner and the details behind it under ## For the implementer" "$STYLE_TAIL" ;;
    *) printf '%s%s' "${WRITE_HEAD}$1.md section" "$STYLE_TAIL" ;;
  esac
}
sentence_2() { printf '%s%s%s' "$LINT_CMD" "$1.md" "$LINT_TAIL"; }

@test "every Research brief carries both sentences with Research.md, once" {
  n=0
  for t in $RESEARCH_BRIEFS; do
    b="$(stage_brief "${t%%:*}" "${t##*:}")"
    [ "$(count "$(sentence_1 Research)" <<<"$b")" -eq 1 ] || { echo "profile-${t%%:*}.js ${t##*:}: the Research.md writing sentence is not there exactly once"; return 1; }
    [ "$(count "$(sentence_2 Research)" <<<"$b")" -eq 1 ] || { echo "profile-${t%%:*}.js ${t##*:}: the Research.md lint sentence is not there exactly once"; return 1; }
    [ "$(count 'lint-artifact-readability.sh' <<<"$b")" -eq 1 ] || { echo "profile-${t%%:*}.js ${t##*:}: the lint is named more than once"; return 1; }
    n=$((n + 1))
  done
  [ "$n" -eq 5 ] || { echo "checked $n brief(s), expected 5"; return 1; }
}

@test "RESEARCH's Research brief takes the short answer and the rules every document follows, then lints once" {
  b="$(stage_brief research Research)"
  grep -qF "${WRITE_HEAD}Research.md section for the short answer and its rules for every document (the document is the deliverable, so the skill's layers and its other per-document sections do not apply)${STYLE_TAIL}" <<<"$b" \
    || { echo "profile-research.js Research: the writing sentence is not the one for a deliverable"; return 1; }
  [ "$(count "$(sentence_2 Research)" <<<"$b")" -eq 1 ] || { echo "profile-research.js Research: no lint sentence, or more than one"; return 1; }
  [ "$(count 'lint-artifact-readability.sh' <<<"$b")" -eq 1 ] || { echo "profile-research.js Research: the lint is named more than once"; return 1; }
}

@test "every Plan brief carries both sentences with Plan.md, once (the epic's twice, one per branch)" {
  n=0
  for t in $PLAN_BRIEFS; do
    b="$(stage_brief "${t%%:*}" "${t##*:}")"
    want=1
    [ "${t%%:*}" = epic ] && want=2
    [ "$(count "$(sentence_1 Plan)" <<<"$b")" -eq 1 ] || { echo "profile-${t%%:*}.js ${t##*:}: the Plan.md writing sentence is not there exactly once"; return 1; }
    [ "$(count "$(sentence_2 Plan)" <<<"$b")" -eq "$want" ] || { echo "profile-${t%%:*}.js ${t##*:}: the Plan.md lint sentence is not there $want time(s)"; return 1; }
    [ "$(count 'lint-artifact-readability.sh' <<<"$b")" -eq "$want" ] || { echo "profile-${t%%:*}.js ${t##*:}: the lint is named other than $want time(s)"; return 1; }
    n=$((n + 1))
  done
  [ "$n" -eq 5 ] || { echo "checked $n brief(s), expected 5"; return 1; }
}

@test "QUICK writes its one-phase Plan.md by the skill, and runs no lint on it" {
  b="$(stage_brief quick Edit)"
  [ "$(count "$(sentence_1 Plan)" <<<"$b")" -eq 1 ] || { echo "profile-quick.js Edit: the Plan.md writing sentence is not there exactly once"; return 1; }
  ! grep -qF 'lint-artifact-readability.sh' <<<"$b" || { echo "profile-quick.js Edit: lints a plan it ticks off a minute later"; return 1; }
}

@test "every reviewer brief carries both sentences with Review.md, once, and not through the ranges record" {
  n=0
  for t in $REVIEW_BRIEFS; do
    b="$(stage_brief "${t%%:*}" "${t##*:}")"
    [ "$(count "$(sentence_1 Review)" <<<"$b")" -eq 1 ] || { echo "profile-${t%%:*}.js ${t##*:}: the Review.md writing sentence is not there exactly once"; return 1; }
    [ "$(count "$(sentence_2 Review)" <<<"$b")" -eq 1 ] || { echo "profile-${t%%:*}.js ${t##*:}: the Review.md lint sentence is not there exactly once"; return 1; }
    [ "$(count 'lint-artifact-readability.sh' <<<"$b")" -eq 1 ] || { echo "profile-${t%%:*}.js ${t##*:}: the lint is named more than once"; return 1; }
    n=$((n + 1))
  done
  [ "$n" -eq 7 ] || { echo "checked $n brief(s), expected 7"; return 1; }
  # REVIEW_RECORD is empty when the profile is not ranged, so a sentence inside it would vanish there.
  for f in "$ROOT"/workflows/profile-*.js; do
    rec="$(awk '/^const REVIEW_RECORD = /{p=1} p{print} p&&/^  : '"''"'$/{exit}' "$f")"
    [ -n "$rec" ] || { echo "$(basename "$f"): no REVIEW_RECORD found"; return 1; }
    ! grep -qF 'lint-artifact-readability' <<<"$rec" || { echo "$(basename "$f"): the lint sentence sits in REVIEW_RECORD"; return 1; }
  done
}

@test "the Done brief carries both sentences with Done.md, the lint last, the line cap kept" {
  for p in $DONE_PROFILES; do
    b="$(done_brief "$p")"
    [ -n "$b" ] || { echo "profile-$p.js: no doneBrief"; return 1; }
    [ "$(count "$(sentence_1 Done)" <<<"$b")" -eq 1 ] || { echo "profile-$p.js: the Done.md writing sentence is not there exactly once"; return 1; }
    [ "$(count "$(sentence_2 Done)" <<<"$b")" -eq 1 ] || { echo "profile-$p.js: the Done.md lint sentence is not there exactly once"; return 1; }
    [ "$(count 'lint-artifact-readability.sh' <<<"$b")" -eq 1 ] || { echo "profile-$p.js: the lint is named more than once"; return 1; }
    last="$(grep -n '' <<<"$b" | grep -F 'lint-artifact-readability.sh' | cut -d: -f1)"
    total="$(wc -l <<<"$b" | tr -d ' ')"
    [ "$last" -ge $((total - 2)) ] || { echo "profile-$p.js: the lint sentence is not the last thing in doneBrief"; return 1; }
  done
  for p in bug refactor test quick feature; do
    grep -qF "cap('Done.md')" "$ROOT/workflows/profile-$p.js" || { echo "profile-$p.js: the lite line cap of Done.md is gone"; return 1; }
  done
}

@test "doneBrief is byte-equal in the eight scripts" {
  want="$(done_brief feature)"
  [ -n "$want" ] || { echo "no doneBrief in profile-feature.js"; return 1; }
  for p in $DONE_PROFILES; do
    [ "$(done_brief "$p")" = "$want" ] || { echo "profile-$p.js: doneBrief differs from profile-feature.js"; return 1; }
  done
}

@test "no script runs the lint more often than it has writers" {
  # feature, bug, refactor: Research, Plan, Validation (OpsChecklist.md), Review, Done. test:
  # Research, Plan, Review, Done. epic: Research, Plan on each branch, Done. quick: Review, Done.
  # research: Research, Review, Done. review: Review, the DISCUSSION log, Done.
  for t in feature:5 bug:5 refactor:5 test:4 epic:4 quick:2 research:3 review:3; do
    n="$(grep -c 'lint-artifact-readability.sh' "$ROOT/workflows/profile-${t%%:*}.js")"
    [ "$n" -eq "${t##*:}" ] || { echo "profile-${t%%:*}.js names the lint on $n line(s), expected ${t##*:}"; return 1; }
  done
}

@test "the older Research.md and Plan.md clauses are replaced, not doubled" {
  for f in "$ROOT"/workflows/profile-*.js; do
    ! grep -qF 'by applying the task-documents skill, its Research.md section' "$f" || { echo "$(basename "$f"): the old Research.md clause is still there"; return 1; }
    ! grep -qF 'by applying the task-documents skill, its Plan.md section' "$f" || { echo "$(basename "$f"): the old Plan.md clause is still there"; return 1; }
  done
}

@test "every Research brief opens Research.md with the short answer, once" {
  for t in feature:Research bug:Diagnose refactor:Analyze test:Analyze epic:Research research:Research; do
    b="$(stage_brief "${t%%:*}" "${t##*:}")"
    [ "$(count '## Short answer' <<<"$b")" -eq 1 ] || { echo "profile-${t%%:*}.js ${t##*:}: ## Short answer is not named exactly once"; return 1; }
    grep -qE '(^## Short answer —|Research\.md opens with ## Short answer)' <<<"$b" \
      || { echo "profile-${t%%:*}.js ${t##*:}: the short answer is not said to come first"; return 1; }
  done
  b="$(stage_brief feature Research)"
  [ "$(grep -n '## Short answer' <<<"$b" | cut -d: -f1)" -lt "$(grep -n '^## Requirements' <<<"$b" | cut -d: -f1)" ] \
    || { echo "profile-feature.js Research: the short answer is listed after Requirements"; return 1; }
  b="$(stage_brief research Research)"
  [ "$(grep -n '## Short answer' <<<"$b" | cut -d: -f1)" -lt "$(grep -n '^## Goal' <<<"$b" | cut -d: -f1)" ] \
    || { echo "profile-research.js Research: the short answer is listed after Goal"; return 1; }
}

@test "the Research.md headings are named once in each of the three skills that name two" {
  for t in feature:Research:'## Requirements':'## Landscape' epic:Research:'## Requirements':'## Landscape' refactor:Analyze:'## Landscape (current)':'## Landscape (target)'; do
    IFS=: read -r p s h1 h2 <<<"$t"
    b="$(awk -v s="- **$s**" 'index($0,s)==1{p=1;print;next} p&&/^- \*\*/{exit} p' "$ROOT/skills/workflow-$p/SKILL.md")"
    for h in "$h1" "$h2"; do
      [ "$(count "\`$h\`" <<<"$b")" -eq 1 ] || { echo "workflow-$p/SKILL.md $s: $h is not named exactly once"; return 1; }
    done
    [ "$(count '`## Short answer`' <<<"$b")" -eq 1 ] || { echo "workflow-$p/SKILL.md $s: ## Short answer is not named exactly once"; return 1; }
  done
}

@test "the epic's Plan lints the decomposition plan before the pure-research branch, and the roadmap too" {
  b="$(stage_brief epic Plan)"
  first="$(grep -nF "$(sentence_2 Plan)" <<<"$b" | head -n 1 | cut -d: -f1)"
  pure="$(grep -nF 'If the verdict is PURE_RESEARCH' <<<"$b" | cut -d: -f1)"
  last="$(grep -nF "$(sentence_2 Plan)" <<<"$b" | tail -n 1 | cut -d: -f1)"
  [ -n "$first" ] && [ -n "$pure" ] && [ "$first" -lt "$pure" ] || { echo "the decomposition lint does not precede the pure-research branch"; return 1; }
  [ "$last" -gt "$pure" ] || { echo "the roadmap Plan.md is not linted"; return 1; }
  grep -qF 'If you wrote Plan.md: ' <<<"$(sed -n "${last}p" <<<"$b")" || { echo "the roadmap lint is not conditional on the file"; return 1; }
}

# A profile run with stubbed agents, one stage; $3 extra contract members.
run_one() { # $1 = profile, $2 = stage, $3 = extra contract members
  local agents='{"architect":"a","developer":"d","tester":"t","reviewer":"r","refactorer":"f","validator":"v","security":"-","diagnostics":"g","init":"-"}'
  node "$ROOT/tests/foundation/helpers/run-profile.js" "$ROOT/workflows/profile-$1.js" \
    "{\"task_id\": \"001\", \"task_dir\": \"/p/t\", \"plugin_root\": \"/core\", \"lang\": \"en\", \"agents\": $agents, \"start_stage\": \"$2\", \"end_stage\": \"$2\", \"stage_scope\": \"forward\", \"walkthrough\": \"off\"$3}" '{}'
}
prompt_of() { node -e 'const o = JSON.parse(require("fs").readFileSync(0, "utf8")); const c = o.calls.find((c) => c.label === process.argv[1]); console.log(c ? c.prompt : "")' "$1"; }

@test "the Validation briefs that write OpsChecklist.md lint it once, at full only" {
  for p in feature bug refactor; do
    v="$(run_one "$p" Validation ', "scale": "full"' | prompt_of validation)"
    [ -n "$v" ] || { echo "profile-$p.js: no validation dispatch"; return 1; }
    grep -qF 'Run "/core/scripts/lint-artifact-readability.sh" --words-per-sentence 30 /p/t/OpsChecklist.md once. Fix each finding once; do not run it again; name what is left in your summary.' <<<"$v" \
      || { echo "profile-$p.js: the full Validation brief does not lint OpsChecklist.md"; return 1; }
    v="$(run_one "$p" Validation ', "scale": "lite"' | prompt_of validation)"
    ! grep -qF 'OpsChecklist.md once' <<<"$v" || { echo "profile-$p.js: the lite Validation brief lints a file it does not write"; return 1; }
  done
}

@test "the lint sentences carry the run's words-per-sentence, 30 without one" {
  d="$(run_one feature Done ', "budgets": {"words-per-sentence": 22}' | prompt_of done)"
  grep -qF 'lint-artifact-readability.sh" --words-per-sentence 22 /p/t/Done.md once.' <<<"$d" || { echo "$d" | tail -n 3; return 1; }
  d="$(run_one feature Done '' | prompt_of done)"
  grep -qF 'lint-artifact-readability.sh" --words-per-sentence 30 /p/t/Done.md once.' <<<"$d" || { echo "$d" | tail -n 3; return 1; }
  for p in feature bug refactor test quick epic research review; do
    [ "$(grep -cF "\"\${core('scripts/lint-walkthrough.sh')}\" --words-per-sentence \${BUDGETS['words-per-sentence']} \${DIR}" "$ROOT/workflows/profile-$p.js")" -eq 2 ] \
      || { echo "profile-$p.js: the walkthrough writer runs its lint without the run's words-per-sentence"; return 1; }
  done
}

@test "the DISCUSSION log and the orchestrator's open-questions log lint Questions.md once" {
  grep -qF "Run \"\${core('scripts/lint-artifact-readability.sh')}\" --words-per-sentence \${BUDGETS['words-per-sentence']} \${DIR}/Questions.md once. Fix each finding once; do not run it again; name what is left in your summary." "$ROOT/workflows/profile-review.js" \
    || { echo "profile-review.js: DISCUSSION does not lint Questions.md"; return 1; }
  ML='run scripts/lint-artifact-readability.sh on `Questions.md` once, with `--words-per-sentence` taken from the contract'"'"'s `budgets`; fix each finding once and name what is left in the stage summary.'
  grep -F -- '- `DISCUSSION` →' "$ROOT/skills/workflow-review/SKILL.md" | grep -qF "$ML" || { echo "workflow-review: DISCUSSION does not lint Questions.md"; return 1; }
  grep -F 'an `## Open Questions Log` section is appended to `Questions.md`' "$ROOT/skills/orchestrator/SKILL.md" | grep -qF "${ML/run scripts/run <core root>/scripts}" \
    || { echo "orchestrator: the open-questions log is not linted"; return 1; }
}

@test "the Method B Validation bullets that write OpsChecklist.md lint it once" {
  ML='Last, run scripts/lint-artifact-readability.sh on `OpsChecklist.md` once, with `--words-per-sentence` taken from the contract'"'"'s `budgets`; fix each finding once and name what is left in the stage summary.'
  for s in feature bug refactor; do
    body="$(awk '/^## 2\. Stages/{z=1;next} z&&/^## /{exit} z&&/^- \*\*/{f=index($0, "- **Validation**")==1} z&&f' "$ROOT/skills/workflow-$s/SKILL.md")"
    [ "$(grep -cF "$ML" <<<"$body")" -eq 1 ] || { echo "workflow-$s: the Validation bullet does not lint OpsChecklist.md once"; return 1; }
  done
}

@test "the walkthrough writer's skill runs its lint with the contract's words-per-sentence" {
  grep -qF 'Each run of the lint here takes `--words-per-sentence` from the contract'"'"'s `budgets`' "$ROOT/skills/task-walkthrough/SKILL.md" \
    || { echo "task-walkthrough: the refresh lint does not take the run's words-per-sentence"; return 1; }
}
