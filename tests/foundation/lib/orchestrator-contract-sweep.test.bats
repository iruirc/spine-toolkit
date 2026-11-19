#!/usr/bin/env bats
# changed: sweep skills conventions templates workflows commands
# Split from orchestrator-contract.test.bats: the tests that walk the source trees.

setup() {
  ROOT="$(cd -- "$(dirname -- "$BATS_TEST_FILENAME")/../../.." && pwd)"
  SKILL="$ROOT/skills/orchestrator/SKILL.md"
}

# A section's body, heading excluded, up to the next H2. $2 carries its own "## ".
section() {
  awk -v h="$2" '$0==h{f=1;next} f&&/^## /{exit} f' "$1"
}

@test "scale reaches the two profiles that have no implementing stage" {
  # Stated rather than omitted: a field that is "sometimes there" is a field
  # every consumer has to test for before reading.
  for p in review research; do
    grep -q 'scale' "$ROOT/skills/workflow-$p/SKILL.md" \
      || { echo "workflow-$p says nothing about scale"; return 1; }
  done
}

@test "the artifact language is measured at the budget's boundaries and each file goes back once" {
  para="$(awk '/^\*\*Artifact language\.\*\*/{f=1} f&&/^\*\*Per-phase commits/{exit} f' "$SKILL")"
  [ -n "$para" ] || { echo "no Artifact language paragraph in the orchestrator"; return 1; }
  for token in 'lint-artifact-lang.sh`, at the path the budget measured' 'conventions/artifact-language.md' 'stage_done_prompt' \
               '`auto` Method A range' '`lang_mismatch`' '`lang_mismatch_persists`' '**once**' \
               '`research_agent`' 'names the' 'language goes first' 'before sending either rewrite' \
               '`<task_dir>/<step_id>`' '`completed_steps`' '`failed_steps`' \
               '`[TASK_TYPE]` names' 'is not sent again' '`lang_mismatch_unowned`' '`lang_readers_disagree`' \
               'for `Done.md`, `mechanical` for what REVIEW'"'"'s `auto-move` writes' 'quoted logs and messages' "case title" \
               'Exit 0 reports only what the script printed on'; do
    grep -qF -- "$token" <<<"$para" || { echo "the Artifact language paragraph does not name $token"; return 1; }
  done
  for artifact in Research Reproduce Plan Validation OpsChecklist ManualChecks Review ChangesRequested Walkthrough Done Docs; do
    grep -qF "\`$artifact.md\`" <<<"$para" || { echo "no owner for $artifact.md"; return 1; }
  done
}

@test "no progress template key comes back" {
  for k in progress_open_header progress_open_live_hint progress_open_live_ticker_note progress_open_method_b_live \
           progress_open_settings progress_open_settings_rest progress_dispatch progress_stage_report \
           progress_stage_artifact progress_stage_verdict progress_run_elapsed dispatch_method_a dispatch_method_b \
           info_run_setting info_run_directive; do
    hits="$(grep -rlw "$k" "$ROOT/skills" "$ROOT/workflows" "$ROOT/docs" "$ROOT/conventions" \
      "$ROOT/commands" "$ROOT/templates" "$ROOT/README.md" || true)"
    [ -z "$hits" ] || { echo "$k is back in: $hits"; return 1; }
  done
}

@test "the open-questions gate collects through its script and offers a marked recommendation" {
  para="$(awk '/^\*\*Open-questions inline/{f=1} f&&/^\*\*Scope:\*\*/{exit} f' "$SKILL")"
  [ -n "$para" ] || { echo "no Open-questions inline paragraph in the orchestrator"; return 1; }
  for token in '<core root>/scripts/open-questions.sh` on those of them that exist' '`{artifact, section, id, text, recommended}`' \
               '`stage_done_dialog_accept`, only when `recommended` is not `null`' 'free-text option'; do
    grep -qF -- "$token" <<<"$para" || { echo "the gate paragraph does not name $token"; return 1; }
  done
  ! grep -qF 'first 80 chars' <<<"$para" || { echo "the gate still cuts an item to 80 characters"; return 1; }
  for f in "$SKILL" "$ROOT"/skills/orchestrator/locales/*.md; do
    ! grep -qF stage_done_dialog_answer "$f" || { echo "$f still names stage_done_dialog_answer"; return 1; }
  done
  for l in en ru; do
    grep -qx '## stage_done_dialog_accept' "$ROOT/skills/orchestrator/locales/$l.md" || { echo "$l.md has no stage_done_dialog_accept"; return 1; }
  done
}
