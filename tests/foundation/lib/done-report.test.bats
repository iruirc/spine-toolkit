#!/usr/bin/env bats
# A Done that runs again meets the report an earlier Done left. That report is claims to check
# against the task, never a draft to confirm, and the calibration row it wrote is corrected in place.

setup() {
  ROOT="$(cd -- "$(dirname -- "$BATS_TEST_FILENAME")/../../.." && pwd)"
}

@test "every profile's Done brief says a prior report is claims to check, naming its archived copy" {
  n=0
  for p in bug epic feature refactor research test; do
    f="$ROOT/workflows/profile-$p.js"
    awk '/const done = await agent\(/ { getline next_line; if (next_line ~ /^    doneBrief\($/) ok = 1 } END { exit !ok }' "$f" \
      || { echo "profile-$p.js: the done call does not go through doneBrief"; return 1; }
    n=$((n + 1))
  done
  [ "$n" -eq 6 ] || { echo "checked $n profile(s), expected 6"; return 1; }
  for f in "$ROOT"/workflows/profile-*.js; do
    for token in "const PRIOR_DONE = (Array.isArray(A.archive_paths) ? A.archive_paths : []).find((p) => /(^|\/)_archive\/Done-[^/]*\.md\$/.test(p))" \
                 'const doneBrief = (body) => brief(' \
                 'may already hold the report of an earlier Done of this task' \
                 'every claim in it is unverified' 'Never confirm a claim you did not check.'; do
      grep -qF -- "$token" "$f" || { echo "$(basename "$f"): the prelude lacks: $token"; return 1; }
    done
  done
}

@test "the calibration row of a task is corrected in place, in the skill and in both briefs" {
  est="$ROOT/skills/feature-estimation/SKILL.md"
  grep -qF 'a Done that runs again corrects its own task'"'"'s row instead of appending a second' "$est" \
    || { echo "feature-estimation still appends on every Done"; return 1; }
  grep -qF "Record this feature's data point in the calibration log: correct this task's row if the log already has one, otherwise append it." "$ROOT/workflows/profile-feature.js" \
    || { echo "the FEATURE Done brief still appends"; return 1; }
  grep -qF "Record this epic's data point in the calibration log: correct its row if the log already has one, otherwise append it." "$ROOT/workflows/profile-epic.js" \
    || { echo "the EPIC Done brief does not say how to correct its row"; return 1; }
  ! grep -qF "Append this feature's data point to the calibration log." "$ROOT/workflows/profile-feature.js" \
    || { echo "the FEATURE Done brief still carries the append-only line"; return 1; }
}

@test "every Method B Done bullet says the same about a prior report" {
  n=0
  for s in bug epic feature refactor research test; do
    f="$ROOT/skills/workflow-$s/SKILL.md"
    awk '/^- \*\*Done\*\*/{f=1} f{print} f&&/^$/{exit}' "$f" \
      | grep -qF 'When `Done.md` already exists — a redo, a restart, a continue after a hand-back — every claim in it is checked against the current artifacts and `git log` before it is kept' \
      || { echo "workflow-$s: the Done bullet does not say a prior report is claims to check"; return 1; }
    n=$((n + 1))
  done
  [ "$n" -eq 6 ] || { echo "checked $n skill(s), expected 6"; return 1; }
}

@test "the orchestrator sends Done.md back on the done kind" {
  tr '\n' ' ' <"$ROOT/skills/orchestrator/SKILL.md" | grep -qF 'kind `walkthrough` for `Walkthrough.md`, `done` for `Done.md`, `mechanical` for what REVIEW'"'"'s' \
    || { echo "the Artifact language paragraph still sends Done.md back as mechanical"; return 1; }
}
