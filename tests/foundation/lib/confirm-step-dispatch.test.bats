#!/usr/bin/env bats
# A step the orchestrator offers from an epic's pending_steps is asked "run it now?", not the
# dispatch confirmation's "correct?": there "no" means "fix the stage", here it means "not now".
# The question is prose the model follows, so its options, their order and the four-option cap
# are held here.

setup() {
  ROOT="$(cd -- "$(dirname -- "$BATS_TEST_FILENAME")/../../.." && pwd)"
  S="$ROOT/skills/orchestrator/SKILL.md"
  STEP6="$(sed -n '/^6\. Confirmation in manual mode:/,/^```$/p' "$S")"
  # The step question stands before the ordinary confirmation; cut it up to that AUQ.
  BRANCH="$(printf '%s\n' "$STEP6" | awk '/key `confirm_step_dispatch`/{on=1} /AUQ using key `confirm_dispatch`/{on=0} on')"
}

line_of() { printf '%s\n' "$BRANCH" | grep -nF -- "$1" | head -1 | cut -d: -f1; }

@test "step 6 asks a pending step whether to run it now" {
  [ -n "$BRANCH" ] || { echo "step 6 has no step question before confirm_dispatch"; return 1; }
  grep -qF 'pending_steps' <<<"$BRANCH" || { echo "the step question does not say it is for pending_steps"; return 1; }
  run_l="$(line_of 'locale key `confirm_step_dispatch_run`')"
  pick_l="$(line_of 'locale key `auq_confirm_dispatch_pick_stage`')"
  later_l="$(line_of 'locale key `confirm_step_dispatch_later`')"
  skip_l="$(line_of 'locale key `confirm_step_dispatch_skip`')"
  [ -n "$run_l" ] && [ -n "$pick_l" ] && [ -n "$later_l" ] && [ -n "$skip_l" ] \
    || { echo "an option of the step question is missing"; return 1; }
  [ "$run_l" -lt "$pick_l" ] && [ "$pick_l" -lt "$later_l" ] && [ "$later_l" -lt "$skip_l" ] \
    || { echo "the step question's options are out of order"; return 1; }
}

@test "lite takes the stage picker's place in the step question" {
  grep -qF 'scale_lite_suggest_option' <<<"$BRANCH" || { echo "no lite option in the step question"; return 1; }
  grep -qF 'in place of `auq_confirm_dispatch_pick_stage`' <<<"$BRANCH" || { echo "lite does not replace the picker"; return 1; }
  grep -qF 'AUQ allows no more' <<<"$BRANCH" || { echo "the four-option cap is not stated"; return 1; }
}

@test "not now stops the pending steps and the picker's cancel is not now" {
  [ "$(grep -oF 'status_step_postponed' <<<"$BRANCH" | wc -l)" -ge 2 ] \
    || { echo "status_step_postponed is not both option 3 and the picker's cancel"; return 1; }
  grep -qF 'info_step_postponed' <<<"$BRANCH" || { echo "no info_step_postponed"; return 1; }
  grep -qF 'the epic is not re-dispatched' <<<"$BRANCH" || { echo "not now does not keep the epic waiting"; return 1; }
  ! grep -qF 'status_cancelled_user_no' <<<"$BRANCH" || { echo "the step question still cancels"; return 1; }
}

@test "close without a run moves the step to SKIPPED and goes on" {
  for w in 'SKIPPED' 'task-move' 'report_moved_step' 'next entry'; do
    grep -qF -- "$w" <<<"$BRANCH" || { echo "the skip option does not name: $w"; return 1; }
  done
}

@test "the step question is asked even when the command named profile and mode" {
  grep -qF 'does not apply to the step question' <<<"$STEP6" \
    || { echo "the explicit-parameters skip is not excluded for the step question"; return 1; }
}

@test "the step question's keys exist in both locales and option 2 no longer says no" {
  for k in confirm_step_dispatch confirm_step_dispatch_run confirm_step_dispatch_later \
           confirm_step_dispatch_skip info_step_postponed auq_confirm_dispatch_pick_stage; do
    for l in en ru; do
      grep -q "^## $k\$" "$ROOT/skills/orchestrator/locales/$l.md" || { echo "$l.md lacks $k"; return 1; }
    done
  done
  [ "$(sed -n '/^## auq_confirm_dispatch_pick_stage$/{n;p;}' "$ROOT/skills/orchestrator/locales/en.md")" = 'Change the start stage' ] \
    || { echo "option 2 of the dispatch confirmation still reads as a no"; return 1; }
}

@test "the pending_steps paragraph names the step question and both of its stops" {
  para="$(grep '^EPIC returns more:' "$S")"
  [ -n "$para" ] || { echo "the pending_steps paragraph is gone"; return 1; }
  for w in 'confirm_step_dispatch' 'status_step_postponed' 'SKIPPED' 'State Detection item 4'; do
    grep -qF -- "$w" <<<"$para" || { echo "the pending_steps paragraph does not name: $w"; return 1; }
  done
}

@test "codex dispatches pending steps the way the orchestrator does" {
  row="$(grep -F 'An EPIC always returns its steps as `pending_steps`' "$ROOT/runtimes/codex-cli.md")"
  [ -n "$row" ] || { echo "the Codex runtime lost its pending_steps row"; return 1; }
  grep -qF 'confirm_step_dispatch' <<<"$row" || { echo "the Codex row does not name the step question"; return 1; }
  ! grep -qF 'start_stage=Done' <<<"$row" || { echo "the Codex row still re-dispatches the epic at Done only"; return 1; }
}

@test "a step not run now leaves no Base.md that this dispatch wrote" {
  # Step 5.6 records the base before step 6 asks; a postponed step would later start from a stale tip.
  grep -qF 'Base.md' <<<"$BRANCH" || { echo "the step question does not undo the base 5.6 recorded"; return 1; }
  grep -qF 'step 5.6 wrote' <<<"$BRANCH" || { echo "the step question does not limit the removal to this dispatch's Base.md"; return 1; }
}

@test "the skip report names the locale file it lives in" {
  # report_moved_step is task-move's key: the orchestrator's own locale lookup fails loudly on it.
  grep -qF 'skills/task-move/locales/<lang>.md' <<<"$BRANCH" || { echo "report_moved_step is looked up in the orchestrator's locales"; return 1; }
}
