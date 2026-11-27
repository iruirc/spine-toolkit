#!/usr/bin/env bats
# changed: sweep workflows
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
    for s in 'add one line '"'"'ran: <repository> <module> HEAD <the phase commit'"'"'s short sha> tests <N> result "<result line>" log phase-evidence/phase-${ph.id}/<module>.log'"'"'' \
             'N being the sum of their counts' 'a line of the log that counts no tests is not quoted' 'a log with no result line gets no line' \
             'a run of named test classes gets none' 'after the commit, take its short sha in the module'"'"'s repository' \
             'keep <the log> ${DIR}/phase-evidence/phase-${ph.id}/ --name <module>, with --match for each result-line form test-frameworks names (topic testing)'; do
      grep -qF -- "$s" "$f" || { echo "$(basename "$f"): the phase brief lacks: $s"; return 1; }
    done
    ! grep -qF 'Executed <N>' "$f" || { echo "$(basename "$f"): the phase brief still writes Executed <N>"; return 1; }
  done
  [ "$n" -eq 8 ] || { echo "scanned $n script(s), expected 8"; return 1; }
}

@test "phase-verification gives the form of a ran: line and what the tests of the perimeter are" {
  line="$(section "$SKILL" 'The line')"
  for t in 'ran: <repository> <module> HEAD <sha> tests <N> result "<result line>" log phase-evidence/phase-<id>/<module>.log' \
           'is quoted exactly as the log has it' "the platform's \`test-frameworks\`" \
           'a result line that counts no tests is not quoted' '`<N>` is the sum of the counts of the quoted lines' \
           'has `Executed <N>` where `tests <N>` stands' 'A log with no result line gets none' \
           'the log is the excerpt `evidence.sh keep` writes, with `--match` for each result-line form `test-frameworks` names (topic **testing**)'; do
    grep -qF -- "$t" <<<"$line" || { echo "The line does not say: $t"; return 1; }
  done
  grep -qF 'every test of the modules it edits' <<<"$(section "$SKILL" 'The rungs')" \
    || { echo "The rungs never say what the tests of the perimeter are"; return 1; }
  grep -qF 'with no modules, the whole suite is the perimeter' <<<"$(section "$SKILL" 'The rungs')" \
    || { echo "The rungs leave a project without modules in the all-tests defect"; return 1; }
}

@test "finding 3 of Review exempts a project without modules" {
  f="$(grep -E '^3\. ' <<<"$(section "$SKILL" 'Review')")"
  grep -qF 'a project without modules aside' <<<"$f" || { echo "finding 3: $f"; return 1; }
}

@test "the Plan brief of the four phased profiles says which tests a phase runs" {
  for p in $PROFILES; do
    b="$(plan_brief "$ROOT/workflows/profile-$p.js")"
    for s in "the dependents' tests by class name" 'a full test plan of the app'; do
      grep -qF -- "$s" <<<"$b" || { echo "profile-$p.js: the Plan brief lacks: $s"; return 1; }
    done
  done
}

@test "the Tests column and the tooling convention count by the result lines, not by one framework's words" {
  grep -qF '`Tests` is a number: the sum of the counts of the run'"'"'s result lines, as `skills/phase-verification/SKILL.md` → `## The line` defines them' \
    "$ROOT/skills/task-documents/SKILL.md" || { echo "task-documents: Tests column undefined"; return 1; }
  ! grep -qF 'Executed N tests' "$ROOT/conventions/agent-tooling.md" || { echo "agent-tooling quotes one framework's summary"; return 1; }
  grep -qF 'quotes its result line' "$ROOT/conventions/agent-tooling.md" || { echo "agent-tooling: no result line"; return 1; }
}
