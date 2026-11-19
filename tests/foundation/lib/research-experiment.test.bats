#!/usr/bin/env bats
# An experiment is the one way a RESEARCH task changes code, and only on a branch that is never
# merged. The permission travels as a contract field; these tests hold every surface to it.

setup() {
  # BATS_TEST_FILENAME, not BASH_SOURCE[0]: bats sources a preprocessed copy of
  # the test file from a tmp dir, so BASH_SOURCE[0] there resolves to the copy.
  ROOT="$(cd -- "$(dirname -- "$BATS_TEST_FILENAME")/../../.." && pwd)"
  SKILL="$ROOT/skills/workflow-research/SKILL.md"
  SCRIPT="$ROOT/workflows/profile-research.js"
}

# A section's body, heading excluded, up to the next H2. $2 carries its own "## ".
section() {
  awk -v h="$2" '$0==h{f=1;next} f&&/^## /{exit} f' "$1"
}

@test "workflow-research takes research_experiment and rejects any other value" {
  contract="$(section "$SKILL" '## 1. Input Contract')"
  grep -qF '`research_experiment`' <<<"$contract" || { echo "§1 does not name the field"; return 1; }
  grep -qF 'invalid_research_experiment' <<<"$contract" || { echo "§1 does not reject a bad value"; return 1; }
  for l in en ru; do
    grep -qx '## invalid_research_experiment' "$ROOT/skills/workflow-research/locales/$l.md" \
      || { echo "locale $l lacks invalid_research_experiment"; return 1; }
  done
}

@test "the experiment rules live in one section of the skill" {
  rules="$(section "$SKILL" '## 2c. Experiment')"
  [ -n "$rules" ] || { echo "no ## 2c. Experiment"; return 1; }
  for token in 'experiment/<task>' 'blocked' 'physical device' 'drive_app=off' \
               '### Experiment' '**Evidence:** run' '**Evidence:** reasoning' \
               '<task_dir>/experiment/' 'restored' 'never merged' \
               'explicit path' 'git clean' 'reset --hard' 'temporary directory' 'created for this experiment'; do
    grep -qF "$token" <<<"$rules" || { echo "§2c does not say $token"; return 1; }
  done
}

@test "the desk invariant still stands when the experiment is off" {
  grep -qF 'With `research_experiment=off` the agent MUST NOT modify any source code' "$SKILL" \
    || { echo "the off invariant is gone"; return 1; }
}

@test "Review and Done name what the experiment left behind" {
  stages="$(section "$SKILL" '## 2. Stages')"
  review="$(grep -F -e '- **Review**' <<<"$stages")"
  grep -qF '### Experiment' <<<"$review" || { echo "Review does not check ### Experiment"; return 1; }
  grep -qF '**Evidence:**' <<<"$review" || { echo "Review does not check the evidence lines"; return 1; }
  done_="$(grep -F -e '- **Done**' <<<"$stages")"
  grep -qF 'unmerged' <<<"$done_" || { echo "Done does not name the branches"; return 1; }
}

@test "the output contract carries experiment and its note key" {
  out="$(section "$SKILL" '## 5. Output Contract')"
  grep -qF 'experiment:' <<<"$out" || { echo "no experiment in the return shape"; return 1; }
  grep -qF 'notes_experiment_branches' <<<"$out" || { echo "no note key"; return 1; }
  for l in en ru; do
    grep -A1 -x '## notes_experiment_branches' "$ROOT/skills/workflow-research/locales/$l.md" \
      | grep -qF '{branches}' || { echo "locale $l: notes_experiment_branches lacks {branches}"; return 1; }
  done
}

@test "the research script validates research_experiment and reads absent as off" {
  grep -qF "const EXPERIMENT = A.research_experiment === undefined ? 'off' : A.research_experiment" "$SCRIPT" \
    || { echo "no EXPERIMENT constant"; return 1; }
  grep -qF 'is not one of on, off' "$SCRIPT" || { echo "a bad value is not rejected"; return 1; }
}

@test "with the experiment off the research brief keeps the desk invariant verbatim" {
  grep -qF "const DESK = 'The invariant of this profile: you modify NO source code and write no file other than Research.md. When you find yourself wanting to apply a fix, write it down as a follow-up item instead — that is the deliverable here.'" "$SCRIPT" \
    || { echo "the desk invariant changed"; return 1; }
  grep -qxF "\${EXPERIMENT === 'on' ? EXPERIMENT_RULES : DESK}" "$SCRIPT" \
    || { echo "the Research brief does not choose between the two"; return 1; }
}

@test "the experiment brief carries the rules the skill states" {
  grep -q '^Return experiment ' "$SCRIPT" || { echo "EXPERIMENT_RULES lost its closing line"; return 1; }
  rules="$(sed -n '/^const EXPERIMENT_RULES = /,/^Return experiment /p' "$SCRIPT")"
  [ -n "$rules" ] || { echo "no EXPERIMENT_RULES"; return 1; }
  for token in 'experiment/<task>' 'blocked' 'physical device' 'drive_app' '### Experiment' \
               '**Evidence:** run' '**Evidence:** reasoning' '/experiment/' 'never merged' \
               'explicit path' 'git clean' 'reset --hard' 'temporary directory' 'created for this experiment'; do
    grep -qF "$token" <<<"$rules" || { echo "EXPERIMENT_RULES does not say $token"; return 1; }
  done
}

@test "an experiment that did not finish, or left a checkout behind, stops before Review" {
  grep -qF 'if (!experiment.restored) {' "$SCRIPT" || { echo "restored is not checked"; return 1; }
  grep -qF "if (experiment.status !== 'done') return finish('ask_user', { experiment })" "$SCRIPT" \
    || { echo "an unfinished experiment goes on to Review"; return 1; }
}

@test "an epic hands a pushed RESEARCH step its own agent and experiment" {
  E="$ROOT/workflows/profile-epic.js"
  block="$(sed -n '/const stepArgs/,/^    })$/p' "$E")"
  grep -qF 'research_agent: st.research_agent,' <<<"$block" || { echo "stepArgs drops research_agent"; return 1; }
  grep -qF 'research_experiment: st.research_experiment,' <<<"$block" || { echo "stepArgs drops research_experiment"; return 1; }
  grep -qF 'For a RESEARCH step, also its [RESEARCH_AGENT] and [RESEARCH_EXPERIMENT] where its Task.md carries them.' "$E" || { echo "the step reader never reads the line"; return 1; }
}

@test "task-new writes the line only on an explicit request, for RESEARCH" {
  TN="$ROOT/skills/task-new/SKILL.md"
  grep -qF '[RESEARCH_EXPERIMENT] = [on]' "$TN" || { echo "task-new does not name the line"; return 1; }
  grep -qF '`research_experiment_keywords`' "$TN" || { echo "task-new does not name the keyword key"; return 1; }
  grep -qF 'never on a guess' "$TN" || { echo "task-new does not forbid guessing"; return 1; }
  for l in en ru; do
    grep -qx '## research_experiment_keywords' "$ROOT/skills/task-new/locales/$l.md" \
      || { echo "locale $l lacks research_experiment_keywords"; return 1; }
  done
}

@test "the RESEARCH-vs-EPIC decision sends a spike to RESEARCH with the line" {
  quick="$(section "$ROOT/conventions/research-vs-epic.md" '## Quick decision')"
  grep -qF '[RESEARCH_EXPERIMENT] = [on]' <<<"$quick" || { echo "Quick decision does not name the line"; return 1; }
}

@test "a platform author learns that the research role may build and drive" {
  grep -qF 'research_experiment=on' "$ROOT/docs/building-a-platform.md" \
    || { echo "building-a-platform.md says nothing about the experiment"; return 1; }
}

@test "an epic never pushes an experiment step" {
  E="$ROOT/workflows/profile-epic.js"
  grep -qF "const experimentStep = st.task_type === 'RESEARCH' && st.research_experiment === 'on'" "$E" \
    || { echo "the walk does not recognise an experiment step"; return 1; }
  grep -qF 'if (!canPush || !wf || experimentStep) {' "$E" || { echo "an experiment step is still pushed"; return 1; }
  grep -qF '[RESEARCH_EXPERIMENT] = [on]' "$ROOT/skills/workflow-epic/SKILL.md" \
    || { echo "workflow-epic does not force pull for an experiment step"; return 1; }
}
