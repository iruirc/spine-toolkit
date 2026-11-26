#!/usr/bin/env bats
# A Method A agent hears the owner's last typed message as the only user voice; a choice picked in
# an AUQ reaches it only once typed. These hold the orchestrator to that rule.

setup() {
  ROOT="$(cd -- "$(dirname -- "$BATS_TEST_FILENAME")/../../.." && pwd)"
  S="$ROOT/skills/orchestrator/SKILL.md"
}

# A Russian string as \uXXXX escapes: no Cyrillic outside *.ru.md.
unescape() { python3 -c 'import sys; print(sys.argv[1].encode("ascii").decode("unicode_escape"))' "$1"; }
section() { awk -v h="## $2" '$0==h{f=1;next} f&&/^## /{exit} f' "$1"; }

@test "a choice made in an AUQ is typed before a Workflow call" {
  w="$(section "$S" "The run's own words")"
  for f in '**A choice that must be typed.**' 'Method A only' \
           "read the owner's last typed message" 'A launch request is the typed command or trigger phrase' \
           'names every chosen finding by its id and every decision on one' 'names only some of the choices' \
           'The order of the AUQ and the typed message does not matter' 'When it is asked:' \
           'and any other AUQ answer that decides what is done with a chosen finding' \
           '`auq_fix_review_option_all`' '`auq_fix_review_option_pick`' '`auq_fix_rounds_option_more`' \
           '`auq_fix_incomplete_option_round`' '`stage_done_option_fix_minor`' \
           'typed_confirmation_needed' 'typed_confirmation_bare' 'typed_confirmation_stopped' \
           'appended to `user_directive`' 'the reply wins' 'answers land in `Research.md` and `Questions.md`'; do
    grep -qF -- "$f" <<<"$w" || { echo "run's own words lost: $f"; return 1; }
  done
}

@test "the four orders of an AUQ and a typed message are spelled out" {
  w="$(section "$S" "The run's own words")"
  for f in '| only AUQ answers | not asked:' \
           '| a typed message, then an AUQ | asked |' \
           '| an AUQ, then a typed message on another subject | asked |' \
           '| an AUQ, then a typed message naming every chosen id and decision | not asked;'; do
    grep -qF -- "$f" <<<"$w" || { echo "order not spelled out: $f"; return 1; }
  done
}

@test "a launch request exempts only a choice it does not contradict" {
  w="$(section "$S" "The run's own words")"
  for f in 'a launch request for this task that names no finding or names every chosen one' \
           '| a launch request naming some findings, then an AUQ choosing others | asked |' \
           'and the file is written, as step 3 below does' \
           'where it and the choice differ, step 4 applies to it'; do
    grep -qF -- "$f" <<<"$w" || { echo "exemption unbounded: $f"; return 1; }
  done
}

@test "fix_findings hold the review's findings verbatim, never a decision" {
  g="$(section "$S" 'Gating')"
  grep -qF '`fix_findings` hold the findings verbatim: no decision, note or gloss is written into them' <<<"$g" || { echo "Gating: no verbatim rule"; return 1; }
  grep -qF 'The request is itself a launch request' <<<"$g" || { echo "Gating: launch request sentence"; return 1; }
  grep -qF 'An AUQ answer never reaches the agent, whatever its order against that message' "$ROOT/conventions/stage-dispatch.md" || { echo "stage-dispatch: no host paragraph"; return 1; }
}

@test "the typed-confirmation keys are in both locales" {
  for l in en ru; do
    for k in typed_confirmation_needed typed_confirmation_bare typed_confirmation_stopped; do
      grep -qx "## $k" "$ROOT/skills/orchestrator/locales/$l.md" || { echo "$l: no $k"; return 1; }
    done
  done
  grep -A1 -x '## typed_confirmation_needed' "$ROOT/skills/orchestrator/locales/en.md" | grep -qF 'the last thing you typed' || { echo "en: needed has no reason"; return 1; }
  grep -A1 -x '## typed_confirmation_needed' "$ROOT/skills/orchestrator/locales/ru.md" | grep -qF "$(unescape '\u043f\u043e\u0441\u043b\u0435\u0434\u043d\u0435\u0435, \u0447\u0442\u043e \u0442\u044b \u043d\u0430\u0431\u0440\u0430\u043b')" || { echo "ru: needed has no reason"; return 1; }
}
