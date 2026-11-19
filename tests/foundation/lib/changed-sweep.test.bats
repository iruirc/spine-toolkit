#!/usr/bin/env bats
# A test that walks a source tree is a sweep: it carries '# changed: sweep <dir>...' naming each
# directory it walks, and `scripts/test-foundation.sh changed` runs it for a change under one of
# them. Walking means a glob over the directory, a find or a for loop in it, a profile script or a
# skill reached through a variable (profile-$p.js, skills/$s/SKILL.md), a drive through the
# run-profile helpers (workflows), or the whole directory handed to a tool ("$ROOT/skills" to ls,
# grep -r, cp -R): no file names its target literally, so nothing but the mark selects it. The
# per-file check is sweep_findings in helpers/sweep-lint.bash.

load "$(dirname "$BATS_TEST_FILENAME")/../helpers/sweep-lint"

setup() {
  ROOT="$(cd -- "$(dirname -- "$BATS_TEST_FILENAME")/../../.." && pwd)"
}

# A fixture test file: <mark line or empty> followed by one line that walks skills/ and, with
# <more>, one that walks workflows/.
fixture() {   # <name> <mark> [walk-workflows]
  local f="$BATS_TEST_TMPDIR/$1.test.bats"
  { echo '#!/usr/bin/env bats'
    [ -z "$2" ] || echo "$2"
    echo 'for s in "$ROOT"/skills/*; do :; done'
    [ -z "${3:-}" ] || echo 'x="$ROOT/workflows/profile-$p.js"'
  } >"$f"
  printf '%s\n' "$f"
}

@test "every test that walks a source tree names the directories it walks in its mark" {
  bad=""
  for f in "$ROOT"/tests/foundation/lib/*.bats; do
    [ "$(basename "$f")" = changed-sweep.test.bats ] && continue
    out="$(sweep_findings "$f")"
    [ -z "$out" ] || bad="$bad"$'\n'"$(basename "$f"): $(tr '\n' ';' <<<"$out")"
  done
  [ -z "$bad" ] || { echo "sweep marks to fix:$bad"; return 1; }
}

@test "a right mark and a file that walks nothing are clean" {
  [ -z "$(sweep_findings "$(fixture ok '# changed: sweep skills')")" ]
  [ -z "$(sweep_findings "$(fixture two '# changed: sweep skills workflows' w)")" ]
  printf '#!/usr/bin/env bats\n# names scripts/a.sh\n' >"$BATS_TEST_TMPDIR/none.test.bats"
  [ -z "$(sweep_findings "$BATS_TEST_TMPDIR/none.test.bats")" ]
}

@test "a bare sweep mark is a finding" {
  run sweep_findings "$(fixture bare '# changed: sweep')"
  grep -qF -- "bare sweep mark" <<<"$output"
  run sweep_findings "$(fixture bare-two '# changed: sweep' w)"
  grep -qF -- "bare sweep mark" <<<"$output"
  grep -qF -- "walks skills but" <<<"$output"
  grep -qF -- "walks workflows but" <<<"$output"
}

@test "a walk with no mark is a finding" {
  run sweep_findings "$(fixture unmarked '')"
  [ "$output" = "walks skills but the mark does not name it" ]
}

@test "a walked directory missing from the mark is a finding" {
  run sweep_findings "$(fixture missing '# changed: sweep skills' w)"
  [ "$output" = "walks workflows but the mark does not name it" ]
}

@test "a directory in the mark the file never walks is a finding" {
  run sweep_findings "$(fixture extra '# changed: sweep skills commands')"
  [ "$output" = "the mark names commands, which the file never walks" ]
}

@test "an unknown word in the mark is a finding" {
  run sweep_findings "$(fixture unknown '# changed: sweep skills agents')"
  grep -qF -- "unknown word 'agents'" <<<"$output"
}

@test "a mark on a file that walks nothing is a finding" {
  printf '#!/usr/bin/env bats\n# changed: sweep skills\n# names scripts/a.sh\n' >"$BATS_TEST_TMPDIR/none.test.bats"
  run sweep_findings "$BATS_TEST_TMPDIR/none.test.bats"
  [ "$output" = "the mark names skills, which the file never walks" ]
}

@test "the profile scripts and the run-profile helpers count as workflows, a workflow skill as skills" {
  printf 'x=profile-$p.js\n' >"$BATS_TEST_TMPDIR/p.test.bats"
  [ "$(sweep_walked "$BATS_TEST_TMPDIR/p.test.bats")" = workflows ]
  printf 'load helpers/run-profile\n' >"$BATS_TEST_TMPDIR/h.test.bats"
  [ "$(sweep_walked "$BATS_TEST_TMPDIR/h.test.bats")" = workflows ]
  printf 'x=workflow-$p\n' >"$BATS_TEST_TMPDIR/w.test.bats"
  [ "$(sweep_walked "$BATS_TEST_TMPDIR/w.test.bats")" = skills ]
}
