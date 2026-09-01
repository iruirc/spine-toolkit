#!/usr/bin/env bats
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

@test "the template ships lite and documents full as the absent-block default" {
  tpl="$ROOT/templates/claude-toolkit-md/en.md"
  v="$(awk '/^## Scale$/{f=1;next} f&&NF{print;exit}' "$tpl")"
  [ "$v" = "lite" ] || { echo "## Scale ships '$v', expected lite"; return 1; }
  grep -qF 'A project without this block runs `full`' "$tpl" \
    || { echo "the template does not document the absent-block default"; return 1; }
}
