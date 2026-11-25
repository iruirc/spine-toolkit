#!/usr/bin/env bats
# changed: sweep skills
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
           'task-ranges.sh" since <task dir> --action <action>'; do
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

@test "Gating counts rounds from the last Done and numbers phases across the task" {
  g="$(section "$S" 'Gating')"
  grep -qF 'whose `<n>` is above the `[REVIEW_FIXES]` line of `Done.md`' <<<"$g" || { echo "round limit not reset by a Done"; return 1; }
  grep -qF 'below the last `Catch-up: commits after Done` row' <<<"$g" || { echo "round limit not reset by a catch-up"; return 1; }
  grep -qF 'every `R<n>` row of `Plan.md` plus one' <<<"$g" || { echo "fix_round is not task-wide"; return 1; }
  grep -qF 'rows of the `Plan.md` progress table whose id is `R<n>`' <<<"$g" || { echo "rounds not counted by id"; return 1; }
  grep -qF 'a row titled `Review fixes <n>` with no such id counts too' <<<"$g" || { echo "an older Plan.md lost its rounds"; return 1; }
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

@test "every Method B skill knows fix-review" {
  for p in bug feature refactor test; do
    f="$ROOT/skills/workflow-$p/SKILL.md"
    grep -qF 'Used for `action=run`/`continue`/`restart`/`catch-up`/`fix-review`.' "$f" || { echo "workflow-$p: forward bullet"; return 1; }
    for s in 'Under `fix-review`' '"Review fixes <n>"' '`fix_findings`' '`after_done`' 'row id `R<n>`' \
             'a finding left unfixed stays unticked, the row goes to ⏸'; do
      grep -qF "$s" "$f" || { echo "workflow-$p lost: $s"; return 1; }
    done
    grep -E '^- \*\*(Fix|Execute|Refactor|Write)\*\* — ' "$f" | grep -qF 'Under `fix-review` it runs the single "Review fixes <n>" phase built from `fix_findings` instead of `Plan.md`'"'"'s phases (see Done).' \
      || { echo "workflow-$p: the code-stage bullet does not point to the fix phase"; return 1; }
  done
}

@test "auto never runs more rounds than fix_rounds, whatever Plan.md shows" {
  g="$(section "$S" 'Gating')"
  for f in 'the `fix-review` rounds this session has dispatched for the task' 'whatever `Plan.md` shows' \
           'the fix phase went unrecorded' 'announce `warn_fix_round_unrecorded`' 'stop the loop with `auq_fix_rounds_spent`' \
           '`{n}` — the rounds spent plus one, not `fix_round`' '`{max}` — `fix_rounds`'; do
    grep -qF -- "$f" <<<"$g" || { echo "Gating lost: $f"; return 1; }
  done
  for l in en ru; do
    grep -qx '## warn_fix_round_unrecorded' "$ROOT/skills/orchestrator/locales/$l.md" || { echo "$l: no warn_fix_round_unrecorded"; return 1; }
  done
  awk '/^## warn_fix_round_unrecorded$/{f=1;next} f&&/^## /{exit} f' "$ROOT/skills/orchestrator/locales/en.md" | grep -qF '`R{n}`' || { echo "warn_fix_round_unrecorded does not name the R row"; return 1; }
}

@test "the fix-review precondition holds on its first dispatch, and every dispatch counts its ranges afresh" {
  r="$(section "$S" 'Resolution Algorithm')"
  for f in "checked on a fix-review's first dispatch (its code stage) only" 'does not re-check it' \
           'It runs at every dispatch, so a' 'Review dispatched on its own (manual) gets a review_since picked afresh' 'exit 2 from any call above is a stop'; do
    grep -qF -- "$f" <<<"$r" || { echo "resolution lost: $f"; return 1; }
  done
  for f in 'is counted after the commits the earlier stages made' 'exit 2 from either call'; do
    if grep -qF -- "$f" <<<"$r"; then echo "resolution still says: $f"; return 1; fi
  done
  grep -qF '`reviewed` for `fix-review`' "$ROOT/conventions/task-ranges.md" || { echo "task-ranges.md: no fix-review since"; return 1; }
}

@test "a fix round that left findings is neither closed nor passed to Validation" {
  g="$(section "$S" 'Gating')"
  for f in '**After Review fixes: findings left.**' '`unfixed_findings`' 'info_fix_incomplete' 'auq_fix_incomplete' \
           'auq_fix_incomplete_option_round' 'auq_fix_incomplete_option_accept' 'auq_fix_incomplete_option_stop' \
           '`→ R<n+1>`' '`⊘ left by owner, <date>`' 'at every `progress` value'; do
    grep -qF -- "$f" <<<"$g" || { echo "Gating lost: $f"; return 1; }
  done
  d="$(section "$S" 'State Detection')"
  grep -qF 'a last `R<n>` row at `⏸`' <<<"$d" || { echo "State Detection: no paused fix round"; return 1; }
  grep -qF 'checked before item 1' <<<"$d" || { echo "State Detection: a finished task skips the paused round"; return 1; }
  for l in en ru; do
    for k in info_fix_incomplete auq_fix_incomplete auq_fix_incomplete_option_round \
             auq_fix_incomplete_option_accept auq_fix_incomplete_option_stop; do
      grep -qx "## $k" "$ROOT/skills/orchestrator/locales/$l.md" || { echo "$l: no $k"; return 1; }
    done
  done
}

@test "fix-review is legal after APPROVED with the findings the owner chose" {
  r="$(section "$S" 'Resolution Algorithm')"
  grep -qF 'its first line is neither `CHANGES_REQUESTED` nor `APPROVED`, or it is `APPROVED` and `Review.md` lists no finding' <<<"$r" || { echo "precondition still needs CHANGES_REQUESTED"; return 1; }
  g="$(section "$S" 'Gating')"
  for f in '**After Review: `APPROVED` with findings.**' 'stage_done_option_fix_minor' 'any severity' 'In `auto` nothing changes'; do
    grep -qF -- "$f" <<<"$g" || { echo "Gating lost: $f"; return 1; }
  done
  grep -qF 'after `CHANGES_REQUESTED`, or after `APPROVED` with the findings the owner chose' "$S" || { echo "action row"; return 1; }
  for l in en ru; do
    grep -qx '## stage_done_option_fix_minor' "$ROOT/skills/orchestrator/locales/$l.md" || { echo "$l: no stage_done_option_fix_minor"; return 1; }
  done
}

@test "auto after a fix round that left findings goes on with those findings only" {
  g="$(section "$S" 'Gating')"
  for f in '`{findings}` being the findings left' '`auq_fix_rounds_option_more` dispatches only those' \
           '`auq_fix_rounds_option_self` marks each of them `⊘ left by owner, <date>`'; do
    grep -qF -- "$f" <<<"$g" || { echo "Gating lost: $f"; return 1; }
  done
}

@test "error_fix_review_nothing fits an approving review with nothing listed" {
  for l in en ru; do
    awk '/^## error_fix_review_nothing$/{f=1;next} f&&/^## /{exit} f' "$ROOT/skills/orchestrator/locales/$l.md" | grep -qF 'DISCUSSION' || { echo "$l: the message still assumes CHANGES_REQUESTED"; return 1; }
  done
}
