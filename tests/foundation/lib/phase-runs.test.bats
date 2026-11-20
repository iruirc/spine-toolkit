#!/usr/bin/env bats
# changed: sweep workflows skills
# A phase that runs a whole module records the run under its check, so Validation carries it instead of
# running the module again; the Plan brief and the rungs say which tests belong to a phase at all.

setup() {
  ROOT="$(cd -- "$(dirname -- "$BATS_TEST_FILENAME")/../../.." && pwd)"
  SKILL="$ROOT/skills/phase-verification/SKILL.md"
  PROFILES="feature bug refactor test"
}

section() { # $1 file, $2 heading text: the body up to the next ## heading
  awk -v h="## $2" '$0==h{f=1;next} f&&/^## /{exit} f' "$1"
}

plan_brief() {
  awk '/^\/\/ ── Plan ─/{p=1;next} p&&/^\/\/ ── /{exit} p' "$1"
}

@test "a phase records each whole-module run under its check" {
  n=0
  for f in "$ROOT"/workflows/profile-*.js; do
    n=$((n + 1))
    for s in 'add one line "ran: <repository> <module> HEAD <the phase commit'"'"'s short sha> Executed <N> log phase-evidence/phase-${ph.id}/<module>.log"' \
             'a run of named test classes gets none' 'after the commit, take its short sha in the module'"'"'s repository'; do
      grep -qF -- "$s" "$f" || { echo "$(basename "$f"): the phase brief lacks: $s"; return 1; }
    done
  done
  [ "$n" -eq 8 ] || { echo "scanned $n script(s), expected 8"; return 1; }
}

@test "phase-verification gives the form of a ran: line and what the tests of the perimeter are" {
  grep -qF 'ran: <repository> <module> HEAD <sha> Executed <N> log phase-evidence/phase-<id>/<module>.log' <<<"$(section "$SKILL" 'The line')" \
    || { echo "The line does not give the form of a ran: line"; return 1; }
  grep -qF 'every test of the modules it edits' <<<"$(section "$SKILL" 'The rungs')" \
    || { echo "The rungs never say what the tests of the perimeter are"; return 1; }
  grep -qF 'with no modules, the whole suite is the perimeter' <<<"$(section "$SKILL" 'The rungs')" \
    || { echo "The rungs leave a project without modules in the all-tests defect"; return 1; }
}

@test "the Plan brief of the four phased profiles says which tests a phase runs" {
  for p in $PROFILES; do
    b="$(plan_brief "$ROOT/workflows/profile-$p.js")"
    for s in "the dependents' tests by class name" 'a full test plan of the app'; do
      grep -qF -- "$s" <<<"$b" || { echo "profile-$p.js: the Plan brief lacks: $s"; return 1; }
    done
  done
}
