#!/usr/bin/env bats
# The loop lives in the orchestrator: it picks the findings, counts the rounds and decides whether
# auto goes round again. These hold each of those decisions to its words.

setup() {
  ROOT="$(cd -- "$(dirname -- "$BATS_TEST_FILENAME")/../../.." && pwd)"
  S="$ROOT/skills/orchestrator/SKILL.md"
}

section() { awk -v h="## $2" '$0==h{f=1;next} f&&/^## /{exit} f' "$1"; }

@test "the contract carries fix-review and its three fields" {
  grep -qF '/ `catch-up` / `fix-review` |' "$S" || { echo "input contract enum"; return 1; }
  c="$(section "$S" 'Outbound Contract')"
  grep -qF 'action=run|continue|redo|restart|restart-full|catch-up|fix-review' <<<"$c" || { echo "example action"; return 1; }
  for f in 'fix_findings=[]' 'fix_round=0' 'after_done=false' '`fix_findings`, `fix_round`, `after_done` — filled only when `action=fix-review`'; do
    grep -qF "$f" <<<"$c" || { echo "outbound contract lost: $f"; return 1; }
  done
}

@test "fix-review starts at the code stage, needs CHANGES_REQUESTED and reads only the fixes" {
  r="$(section "$S" 'Resolution Algorithm')"
  for f in 'action=fix-review              → start at the code-changing stage' 'error_fix_review_nothing' \
           'reviewed if action=fix-review'; do
    grep -qF "$f" <<<"$r" || { echo "resolution lost: $f"; return 1; }
  done
}

@test "Gating runs the loop in auto and asks in manual" {
  g="$(section "$S" 'Gating')"
  for f in '**After Review: `CHANGES_REQUESTED`.**' '`blocking_findings`' '### Findings' '**Critical** and **Major**' \
           'fewer than `fix_rounds`' 'info_fix_round' 'auq_fix_rounds_spent' 'auq_fix_review_question' \
           '`fix_rounds` does not apply' 'DISCUSSION'; do
    grep -qF -- "$f" <<<"$g" || { echo "Gating lost: $f"; return 1; }
  done
}

@test "Gating counts rounds from the last catch-up and numbers phases across the task" {
  g="$(section "$S" 'Gating')"
  grep -qF 'below the last `Catch-up: commits after Done` row' <<<"$g" || { echo "round limit not reset by a catch-up"; return 1; }
  grep -qF 'every `Review fixes <n>` row of `Plan.md` plus one' <<<"$g" || { echo "fix_round is not task-wide"; return 1; }
}

@test "fix-review has its triggers, its rows and every key in both locales" {
  m="$(section "$S" 'Stage Management')"
  grep -qF '| "fix review 026" | `fix-review` |' <<<"$m" || { echo "no trigger row"; return 1; }
  grep -qF '| `fix-review` |' <<<"$m" || { echo "no archival row"; return 1; }
  grep -qF 'goes on with `fix-review`' <<<"$m" || { echo "a stopped catch-up still resumes by catch-up"; return 1; }
  ru="$(python3 -c 'print("\"%s N\"" % "".join(map(chr, (0x438, 0x441, 0x43f, 0x440, 0x430, 0x432, 0x44c, 0x20, 0x43d, 0x430, 0x445, 0x43e, 0x434, 0x43a, 0x438))))')"
  sed -n '/^description:/,/^---$/p' "$S" | grep -qF "$ru" || { echo "no Russian trigger in the description"; return 1; }
  sed -n '/^description:/,/^---$/p' "$S" | grep -qF '"fix review N"' || { echo "no English trigger in the description"; return 1; }
  for l in en ru; do
    for k in error_fix_review_nothing info_fix_round auq_fix_review_question auq_fix_review_option_all \
             auq_fix_review_option_pick auq_fix_review_option_leave auq_fix_rounds_spent \
             auq_fix_rounds_option_more auq_fix_rounds_option_self; do
      grep -qx "## $k" "$ROOT/skills/orchestrator/locales/$l.md" || { echo "$l: no $k"; return 1; }
    done
  done
}
