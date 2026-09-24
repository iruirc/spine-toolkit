#!/usr/bin/env bats
# The orchestrator is the only side with a filesystem: it records the base, computes the
# ranges and notices commits after Done. If it stops doing any of it, Review goes blind again.

setup() {
  ROOT="$(cd -- "$(dirname -- "$BATS_TEST_FILENAME")/../../.." && pwd)"
  S="$ROOT/skills/orchestrator/SKILL.md"
}

section() { awk -v h="## $2" '$0==h{f=1;next} f&&/^## /{exit} f' "$1"; }

@test "the contract carries catch-up and review_ranges" {
  grep -qF '`action` | enum: `run` / `continue` / `redo` / `restart` / `restart-full` / `catch-up`' "$S" || { echo "input contract"; return 1; }
  c="$(section "$S" 'Outbound Contract')"
  grep -qF 'action=run|continue|redo|restart|restart-full|catch-up' <<<"$c" || { echo "example action"; return 1; }
  grep -qE '^review_ranges=\{"since": ' <<<"$c" || { echo "example review_ranges"; return 1; }
  grep -qF '`review_ranges` — ' <<<"$c" || { echo "no review_ranges paragraph"; return 1; }
}

@test "step 5.6 records the base and asks for the right --since" {
  r="$(section "$S" 'Resolution Algorithm')"
  grep -qF '5.6. Record the base and compute the review ranges' <<<"$r" || { echo "no step 5.6"; return 1; }
  for f in 'task-ranges.sh" record <task dir>' 'task-ranges.sh" ranges <task dir> --since <since>' \
           'done     if action=catch-up' 'base     if Review.md is absent, or action is restart or restart-full' 'reviewed otherwise' \
           'action=catch-up                → start at Validation'; do
    grep -qF "$f" <<<"$r" || { echo "step 5/5.6 lost: $f"; return 1; }
  done
}

@test "step 5.6 falls back to base and says so" {
  r="$(section "$S" 'Resolution Algorithm')"
  grep -qF 'came back rewritten or unknown' <<<"$r" || { echo "no fallback"; return 1; }
  grep -qF 'warn_review_ranges_full' <<<"$r" || { echo "the fallback is silent"; return 1; }
}

@test "State Detection offers catch-up first when Done is behind" {
  d="$(section "$S" 'State Detection')"
  for f in 'ranges <task dir> --since done' 'auq_catch_up_question' '`catch-up` first' 'warn_catch_up_whole_task'; do
    grep -qF "$f" <<<"$d" || { echo "State Detection lost: $f"; return 1; }
  done
  m="$(section "$S" 'Stage Management')"
  grep -qF '| "catch up 026" | `catch-up` |' <<<"$m" || { echo "no trigger row"; return 1; }
  ru_trigger="$(python3 -c 'print("\"%s N\"" % "".join(map(chr, (0x434, 0x43e, 0x433, 0x43e, 0x43d, 0x438))))')"   # the Russian "catch up N"
  sed -n '/^description:/,/^---$/p' "$S" | grep -qF "$ru_trigger" || { echo "no Russian trigger in the description"; return 1; }
  grep -qF '| `catch-up` |' <<<"$m" || { echo "no archival row"; return 1; }
}

@test "the four catch-up keys exist in both locales" {
  for l in en ru; do
    for k in auq_catch_up_question auq_catch_up_option warn_catch_up_whole_task warn_review_ranges_full; do
      grep -qx "## $k" "$ROOT/skills/orchestrator/locales/$l.md" || { echo "$l: no $k"; return 1; }
    done
  done
}
