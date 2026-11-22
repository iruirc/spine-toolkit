#!/usr/bin/env bats
# changed: sweep skills conventions templates workflows commands
# ops-risks is a closed list of seven operational risks the diff can show. It writes no artifact:
# the architect lays the proof into a phase at Plan, the reviewer checks it against the diff at
# Review. This suite holds the text of the skill and the design questions that feed it.

setup() {
  ROOT="$(cd -- "$(dirname -- "$BATS_TEST_FILENAME")/../../.." && pwd)"
  SKILL="$ROOT/skills/ops-risks/SKILL.md"
}

# A section's body, heading excluded, up to the next H2.
section() { # $1 = file, $2 = heading text without "## "
  awk -v h="## $2" '$0==h{f=1;next} f&&/^## /{exit} f' "$1"
}

@test "the skill exists under its own name and writes no artifact" {
  [ -f "$SKILL" ] || { echo "no skills/ops-risks/SKILL.md"; return 1; }
  grep -qxF 'name: ops-risks' "$SKILL" || { echo "frontmatter name is not ops-risks"; return 1; }
  grep -qF 'It writes no artifact.' "$SKILL" || { echo "nothing says the skill writes no artifact"; return 1; }
}

@test "the skill carries its sections" {
  for h in 'Touches' 'Risks' 'Plan' 'Review' 'Where it applies'; do
    grep -qxF "## $h" "$SKILL" || { echo "no ## $h"; return 1; }
  done
}

@test "the language rule is a paragraph of Review, not a section" {
  ! grep -qxF '## Language' "$SKILL" || { echo "## Language is a section again"; return 1; }
  p="$(section "$SKILL" 'Review' | grep -F '**Language.**' || true)"
  [ -n "$p" ] || { echo "## Review has no **Language.** paragraph"; return 1; }
  for token in 'labels' '`none triggered`' '`## Ops risks`' 'English' 'after the dash' '`[LANG]`'; do
    grep -qF -- "$token" <<<"$p" || { echo "the Language paragraph does not say $token"; return 1; }
  done
}

@test "the risk list is closed and holds exactly the seven labels" {
  s="$(section "$SKILL" 'Risks')"
  got="$(grep -oE '^\| `[a-z-]+` \|' <<<"$s" | sed -E 's/^\| `([a-z-]+)` \|$/\1/' | paste -sd ' ' -)"
  [ "$got" = "startup lifecycle stored-data contract rollout-flag hot-path release-settings" ] \
    || { echo "## Risks labels are: $got"; return 1; }
  grep -qF 'The list is closed.' <<<"$s" || { echo "nothing closes the list"; return 1; }
}

@test "security is left to security-lens" {
  intro="$(awk '/^## /{exit} {print}' "$SKILL")"
  grep -qF 'security-lens' <<<"$intro" || { echo "the introduction does not hand security to security-lens"; return 1; }
}

@test "touches reaches the behaviour's path, and doubt counts as touching" {
  s="$(section "$SKILL" 'Touches')"
  for token in 'code the behaviour calls, or code that calls it' 'When in doubt, it touches.'; do
    grep -qF "$token" <<<"$s" || { echo "## Touches does not say $token"; return 1; }
  done
}

@test "Review sorts a missing proof by who can give it" {
  s="$(section "$SKILL" 'Review')"
  for token in 'Major' 'Minor' '## For Done' '## Ops risks' 'none triggered — the diff touches' 'no case in ManualChecks.md'; do
    grep -qF -- "$token" <<<"$s" || { echo "## Review does not say $token"; return 1; }
  done
}

@test "Plan puts the proof into the phase" {
  s="$(section "$SKILL" 'Plan')"
  for token in '**Verification:**' '## For the owner'; do
    grep -qF -- "$token" <<<"$s" || { echo "## Plan does not say $token"; return 1; }
  done
}

@test "the size of the task does not move it" {
  grep -qF "follows from what the diff touches, never from the task's size." "$SKILL" \
    || { echo "the skill does not state the rule"; return 1; }
}

@test "release-settings resolves topic release ops, in the skill that names the topic" {
  grep -qF 'topic **release ops**' "$SKILL" || { echo "ops-risks does not name topic **release ops**"; return 1; }
  s="$(section "$SKILL" 'Risks')"
  for token in 'privacy disclosure' 'minimum OS version' 'signing'; do
    grep -qF -- "$token" <<<"$s" || { echo "## Risks does not say $token"; return 1; }
  done
  grep -qF 'conventions/platform-contract.md' "$SKILL" || { echo "no pointer to the contract that resolves topics"; return 1; }
}

@test "feature-requirements asks the three design questions" {
  f="$ROOT/skills/feature-requirements/SKILL.md"
  for row in '| Rollout switch |' '| Stored data |' '| Performance-sensitive path |'; do
    grep -qF -- "$row" "$f" || { echo "feature-requirements has no row $row"; return 1; }
  done
}

# A profile run with stubbed agents, one stage at one scale; the prompt of the dispatch labelled $3.
stage_prompt() { # $1 = profile, $2 = stage, $3 = label, $4 = scale
  local agents='{"architect":"a","developer":"d","tester":"t","reviewer":"r","refactorer":"f","validator":"v","security":"-","diagnostics":"g","init":"-"}'
  node "$ROOT/tests/foundation/helpers/run-profile.js" "$ROOT/workflows/profile-$1.js" \
    "{\"task_id\": \"001\", \"task_dir\": \"/p/t\", \"plugin_root\": \"/core\", \"lang\": \"en\", \"agents\": $agents, \"start_stage\": \"$2\", \"end_stage\": \"$2\", \"stage_scope\": \"forward\", \"walkthrough\": \"off\", \"scale\": \"$4\"}" '{}' \
    | node -e 'const o = JSON.parse(require("fs").readFileSync(0, "utf8")); const c = o.calls.find((c) => c.label === process.argv[1]); console.log(c ? c.prompt : "")' "$3"
}

@test "no stage writes or reads OpsChecklist.md" {
  cd "$ROOT"
  hits="$(grep -l -E 'OpsChecklist|Outstanding ops items|ops_checklist_path' skills/workflow-*/SKILL.md workflows/*.js workflow-src/prelude.js skills/orchestrator/SKILL.md skills/task-documents/SKILL.md || true)"
  [ -z "$hits" ] || { echo "still named in: $hits"; return 1; }
}

@test "Plan applies ops-risks in FEATURE, BUG and REFACTOR" {
  for p in feature bug refactor; do
    grep -qF 'Apply the `ops-risks` skill'"'"'s `## Plan`' "$ROOT/skills/workflow-$p/SKILL.md" \
      || { echo "workflow-$p: Plan does not apply ops-risks"; return 1; }
    for scale in full lite; do
      grep -qF "Apply the ops-risks skill's ## Plan" <<<"$(stage_prompt "$p" Plan plan "$scale")" \
        || { echo "profile-$p.js: the $scale Plan brief does not apply ops-risks"; return 1; }
    done
  done
}

@test "Review applies ops-risks in every profile that reviews code, at both scales" {
  for p in feature bug refactor quick review; do
    grep -qF 'Apply the `ops-risks` skill'"'"'s `## Review`' "$ROOT/skills/workflow-$p/SKILL.md" \
      || { echo "workflow-$p: Review does not apply ops-risks"; return 1; }
    for scale in full lite; do
      grep -qF "Apply the ops-risks skill's ## Review" <<<"$(stage_prompt "$p" Review review "$scale")" \
        || { echo "profile-$p.js: the $scale Review brief does not apply ops-risks"; return 1; }
    done
    ! grep -F 'ops-risks' "$ROOT/workflows/profile-$p.js" | grep -qF "lite() ? ''" \
      || { echo "profile-$p.js: ops-risks sits on a line with a lite() branch"; return 1; }
  done
}

@test "TEST, RESEARCH and EPIC do not apply it" {
  for p in test research epic; do
    ! grep -qF 'ops-risks' "$ROOT/skills/workflow-$p/SKILL.md" || { echo "workflow-$p names ops-risks"; return 1; }
    ! grep -qF 'ops-risks' "$ROOT/workflows/profile-$p.js" || { echo "profile-$p.js names ops-risks"; return 1; }
  done
}

@test "Review.md carries the ops risks section" {
  s="$(section "$ROOT/skills/task-documents/SKILL.md" 'Review.md')"
  grep -qF '## Ops risks' <<<"$s" || { echo "task-documents ## Review.md does not name ## Ops risks"; return 1; }
}

@test "the old skill is gone and no file names it" {
  [ ! -e "$ROOT/skills/ops-checklist" ] || { echo "skills/ops-checklist still exists"; return 1; }
  hits="$(grep -rIl 'ops-checklist' --exclude-dir=.git "$ROOT" | sed "s|^$ROOT/||")"
  [ "$hits" = "tests/foundation/lib/ops-risks.test.bats" ] || { echo "files naming it: $hits"; return 1; }
}

@test "manual-checks takes touches from ops-risks" {
  mc="$ROOT/skills/manual-checks/SKILL.md"
  for h in 'What a case must prove' 'Does this check need a person?'; do
    s="$(section "$mc" "$h")"
    grep -qF '`ops-risks`' <<<"$s" || { echo "## $h does not name ops-risks"; return 1; }
    grep -qF '`## Touches`' <<<"$s" || { echo "## $h does not name ## Touches"; return 1; }
  done
}
