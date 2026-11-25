#!/usr/bin/env bats
# changed: sweep skills
# A Method A agent hears the owner's last typed message as the only user voice; a choice picked in
# an AUQ reaches it only once typed. These hold the orchestrator to that rule.

setup() {
  ROOT="$(cd -- "$(dirname -- "$BATS_TEST_FILENAME")/../../.." && pwd)"
  S="$ROOT/skills/orchestrator/SKILL.md"
}

section() { awk -v h="## $2" '$0==h{f=1;next} f&&/^## /{exit} f' "$1"; }

@test "a choice made in an AUQ is typed before a Workflow call" {
  w="$(section "$S" "The run's own words")"
  for f in '**A choice that must be typed.**' 'Method A only' \
           'the owner has typed a message since the request that started the range' \
           'answers that shape the brief rather than the contract' \
           '`auq_fix_review_option_all`' '`auq_fix_review_option_pick`' '`auq_fix_rounds_option_more`' \
           '`auq_fix_incomplete_option_round`' '`stage_done_option_fix_minor`' \
           'typed_confirmation_needed' 'typed_confirmation_bare' 'typed_confirmation_stopped' \
           'appended to `user_directive`' 'the reply wins' 'answers land in `Research.md` and `Questions.md`'; do
    grep -qF -- "$f" <<<"$w" || { echo "run's own words lost: $f"; return 1; }
  done
}

@test "fix_findings hold the review's findings verbatim, never a decision" {
  g="$(section "$S" 'Gating')"
  grep -qF '`fix_findings` hold the findings verbatim: no decision, note or gloss is written into them' <<<"$g" || { echo "Gating: no verbatim rule"; return 1; }
  grep -qF 'AUQ answers given after that message never reach the agent' "$ROOT/conventions/stage-dispatch.md" || { echo "stage-dispatch: no host paragraph"; return 1; }
}

@test "the typed-confirmation keys are in both locales" {
  for l in en ru; do
    for k in typed_confirmation_needed typed_confirmation_bare typed_confirmation_stopped; do
      grep -qx "## $k" "$ROOT/skills/orchestrator/locales/$l.md" || { echo "$l: no $k"; return 1; }
    done
  done
}
