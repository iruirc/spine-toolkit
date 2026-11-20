#!/usr/bin/env bats
# changed: sweep skills workflows
# The axis promises cheaper, not looser. Everything else about scale is prose a reviewer
# reads once; this is the half a reviewer cannot see, because gating one more stage on
# lite looks exactly like the gating that is correct three lines above it.

setup() {
  ROOT="$(cd -- "$(dirname -- "$BATS_TEST_FILENAME")/../../.." && pwd)"
  # The stages D9 puts a floor under, plus the two implementing stages whose per-phase
  # commit is that floor's other half.
  FLOOR="Reproduce|Validation|Review|Execute|Fix|Refactor|Write"
}

@test "no profile script gates a floor stage on scale" {
  offenders=""
  for f in "$ROOT"/workflows/profile-*.js; do
    while IFS= read -r line; do
      case "$line" in
        *"lite()"*) offenders="$offenders${f##*/}: $line"$'\n' ;;
      esac
    done < <(grep -E "^(\} else )?if \(.*runs\('($FLOOR)'\)" "$f")
  done
  [ -z "$offenders" ] || { echo "a floor stage gated on scale:"; echo "$offenders"; return 1; }
}

@test "the scripts that gate anything on scale are the ones that fold a stage" {
  # Vacuity guard for the test above: if no script gates anything, it iterates over
  # nothing and passes over an axis that was never wired up.
  n="$(grep -lE "runs\('[A-Za-z]+'\) && !lite\(\)" "$ROOT"/workflows/profile-*.js | wc -l | tr -d ' ')"
  [ "$n" -eq 4 ] || { echo "$n script(s) fold a stage on scale, expected 4"; return 1; }
}

@test "every profile skill states what scale does to it" {
  for f in "$ROOT"/skills/workflow-*/SKILL.md; do
    grep -q '^## 2a\. Scale$' "$f" || { echo "no '## 2a. Scale' in ${f#"$ROOT"/}"; return 1; }
  done
}

@test "the convention states the floor and the one-way rule" {
  c="$ROOT/conventions/task-scale.md"
  grep -q '^## The floor$' "$c" || { echo "the convention has no floor section"; return 1; }
  grep -qi 'never lowered' "$c" || { echo "the convention does not state the one-way rule"; return 1; }
}

@test "the template ships lite" {
  tpl="$ROOT/templates/spine-md/en.md"
  v="$(sed -n 's/^\[SCALE\] = \[\([a-z]*\)\].*/\1/p' "$tpl")"
  [ "$v" = "lite" ] || { echo "[SCALE] ships '$v', expected lite"; return 1; }
}

@test "the configuration page documents full as the absent-field default" {
  # The guidance left the template when the settings became one-line fields; the reference page is
  # where it lands, and this assertion goes live with it.
  doc="$ROOT/docs/configuration.md"
  grep -qF 'A project without this field runs `full`' "$doc" \
    || { echo "the page does not document the absent-field default"; return 1; }
}

@test "the convention says when to suggest lite, without thresholds" {
  c="$ROOT/conventions/task-scale.md"
  grep -q '^## Suggesting lite$' "$c" || { echo "the convention has no 'Suggesting lite' section"; return 1; }
  section="$(sed -n '/^## Suggesting lite$/,/^## Explicit beats the axis$/p' "$c")"
  [ -n "$section" ]
  ! printf '%s\n' "$section" | grep -E '[0-9]+ (lines|files)' \
    || { echo "the section states a numeric threshold"; return 1; }
  printf '%s\n' "$section" | grep -q 'sources.scale' || { echo "the section does not name sources.scale"; return 1; }
  printf '%s\n' "$section" | grep -qi 'never a lowering' || { echo "the section does not say it is never a lowering"; return 1; }
}

@test "the orchestrator suggests lite only at manual confirmation and only when Task.md is silent" {
  s="$ROOT/skills/orchestrator/SKILL.md"
  step="$(sed -n '/^6\. Confirmation in manual mode:/,/^```$/p' "$s")"
  [ -n "$step" ] || { echo "step 6 not found"; return 1; }
  printf '%s\n' "$step" | grep -q 'scale_lite_suggest_option' || { echo "step 6 does not name the option key"; return 1; }
  printf '%s\n' "$step" | grep -q 'scale_lite_suggest`' || { echo "step 6 does not name the text key"; return 1; }
  printf '%s\n' "$step" | grep -q 'sources.scale' || { echo "step 6 does not read sources.scale"; return 1; }
  printf '%s\n' "$step" | grep -q '`task`' || { echo "step 6 does not exclude a Task.md scale"; return 1; }
  printf '%s\n' "$step" | grep -q '`epic`' || { echo "step 6 does not exclude the epic's scale"; return 1; }
  printf '%s\n' "$step" | grep -q '\[NEED_REVIEW\]' || { echo "step 6 does not place the write after [NEED_REVIEW]"; return 1; }
  printf '%s\n' "$step" | grep -qF 'no suggestion in `auto`' \
    || { echo "step 6 does not exclude auto"; return 1; }
  for k in scale_lite_suggest scale_lite_suggest_option; do
    for l in en ru; do
      grep -q "^## $k\$" "$ROOT/skills/orchestrator/locales/$l.md" || { echo "$l.md lacks $k"; return 1; }
    done
  done
}

@test "no suggestion when the command already named profile and mode" {
  s="$ROOT/skills/orchestrator/SKILL.md"
  rule="$(grep -n 'Confirmation is also skipped if both key parameters' "$s" | cut -d: -f1)"
  [ -n "$rule" ] || { echo "the skip rule is gone"; return 1; }
  sed -n "${rule},$((rule + 6))p" "$s" | grep -q 'scale_lite_suggest' \
    || { echo "the skip rule does not say the suggestion is skipped too"; return 1; }
}
