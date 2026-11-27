#!/usr/bin/env bats
# Validators and phases copied whole tool logs into the task folder, and the task folder went into
# git as it was: tokens, cookies and keys a test run printed were committed with it. keep leaves the
# raw log in a raw/ folder git never sees and commits a scrubbed excerpt in its place.

bats_require_minimum_version 1.5.0

setup() {
  ROOT="$(cd -- "$(dirname -- "$BATS_TEST_FILENAME")/../../.." && pwd)"
  EV="$ROOT/scripts/evidence.sh"
  FIX="$ROOT/tests/foundation/fixtures/evidence"
  PROJ="$BATS_TEST_TMPDIR/Proj"
  TASK="$PROJ/Tasks/ACTIVE/042"
  mkdir -p "$TASK"
  cp "$FIX/SPINE.md" "$PROJ/SPINE.md"
  printf '# Task\n' >"$TASK/Task.md"
  git -C "$PROJ" init -q -b main
  OUT="$TASK/validation-evidence/t"
}

keep_fixture() {
  run "$EV" keep "$FIX/secrets.log" "$OUT" --name app --match '^Executed ' --match '^JUnit XML:' --match 'error:' "$@"
}

@test "keep strips every secret form and keeps the raw log whole" {
  # The three key lines sit above the tail; a --match of their own brings them into the excerpt.
  keep_fixture --match '"token":|^Authorization: Bearer|^X-Api-Key:'
  [ "$status" -eq 0 ] || { echo "$output"; return 1; }
  ! grep -n FAKE "$OUT/app.log" || return 1
  cmp "$FIX/secrets.log" "$OUT/raw/app.log"
  grep -q '"token": "\*\*\*"' "$OUT/app.log" || { cat "$OUT/app.log"; return 1; }
  grep -q '^Authorization: Bearer \*\*\*$' "$OUT/app.log" || { cat "$OUT/app.log"; return 1; }
  grep -q '^X-Api-Key: \*\*\*$' "$OUT/app.log" || { cat "$OUT/app.log"; return 1; }
  [[ "$output" =~ ^kept\ validation-evidence/t/app\.log\ redacted=([0-9]+)$ ]] || { echo "$output"; return 1; }
  [ "${BASH_REMATCH[1]}" -ge 17 ] || { echo "$output"; return 1; }
}

@test "every secret form is redacted where it stands, key kept" {
  # The excerpt of the whole log keeps only some of its lines; kept one at a time, each line is its
  # own tail, so every form is seen on its own. A key's body line alone is no key: its block is the
  # private-key test's.
  local i=0
  while IFS= read -r line; do
    i=$((i + 1))
    [[ "$line" != FAKEpem* ]] || continue
    printf '%s\n' "$line" >"$BATS_TEST_TMPDIR/one.log"
    run "$EV" keep "$BATS_TEST_TMPDIR/one.log" "$OUT" --name "l$i" --match .
    [ "$status" -eq 0 ] || { echo "line $i: $output"; return 1; }
    ! grep -q FAKE "$OUT/l$i.log" || { echo "line $i leaks: $(cat "$OUT/l$i.log")"; return 1; }
  done <"$FIX/secrets.log"
  grep -qx 'Authorization: Basic \*\*\*' "$OUT/l15.log"
  grep -qx 'Set-Cookie: \*\*\*' "$OUT/l17.log"
  grep -qx 'fetching https://user:\*\*\*@example.invalid/x' "$OUT/l18.log"
  grep -qx 'GET /cb?access_token=\*\*\*&x=1' "$OUT/l19.log"
  grep -qx 'login with password=\*\*\* user=tester' "$OUT/l13.log"
  grep -qx 'config: {"clientSecret": "\*\*\*"}' "$OUT/l12.log"
  grep -qx 'project \*\*\*' "$OUT/l26.log"
}

@test "the excerpt is the header, the matched lines in order, then the tail" {
  keep_fixture
  [ "$status" -eq 0 ] || { echo "$output"; return 1; }
  diff <(head -5 "$OUT/app.log") - <<'EOF'
# evidence excerpt v1 — raw: raw/app.log
Executed 12 tests, with 0 failures
JUnit XML: 7 tests, 0 failures, 0 errors, 0 skipped in 2 files
error: build failed at step 3
# tail
EOF
  [ "$(wc -l <"$OUT/app.log")" -eq 25 ]
  diff <(tail -17 "$OUT/app.log") <(tail -17 "$FIX/secrets.log")
}

@test "a private key cut by the tail boundary leaks no line of its body" {
  keep_fixture
  [ "$status" -eq 0 ] || { echo "$output"; return 1; }
  # BEGIN and the first body line are above the last 20 lines; the other two and END are in them.
  ! grep -q BEGIN "$OUT/app.log"
  ! grep -q pem0017 "$OUT/app.log"
  diff <(sed -n '6,8p' "$OUT/app.log") - <<'EOF'
***
***
-----END PRIVATE KEY-----
EOF
  [ "$(grep -c pem0017 "$OUT/raw/app.log")" -eq 3 ]
}

@test "a private key with no END line is redacted to the end of the log" {
  printf 'a\n-----BEGIN RSA PRIVATE KEY-----\nFAKEpemcut1\nFAKEpemcut2\n' >"$BATS_TEST_TMPDIR/cut.log"
  run "$EV" keep "$BATS_TEST_TMPDIR/cut.log" "$OUT"
  [ "$status" -eq 0 ] || { echo "$output"; return 1; }
  ! grep -q FAKE "$OUT/cut.log" || { cat "$OUT/cut.log"; return 1; }
}

@test "raw is invisible to git" {
  keep_fixture
  [ "$status" -eq 0 ] || { echo "$output"; return 1; }
  run git -C "$PROJ" status --porcelain --untracked-files=all
  [[ "$output" == *"validation-evidence/t/app.log"* ]] || { echo "$output"; return 1; }
  [[ "$output" != *raw* ]] || { echo "$output"; return 1; }
  [ "$(cat "$OUT/raw/.gitignore")" = '*' ]
  [ "$(wc -l <"$OUT/raw/.gitignore")" -eq 1 ]
}

@test "no --match line still writes the tail and says so" {
  run --separate-stderr "$EV" keep "$FIX/secrets.log" "$OUT" --name app --match '^nothing here'
  [ "$status" -eq 0 ] || { echo "$output $stderr"; return 1; }
  [ "$stderr" = "evidence: no line matched --match in $FIX/secrets.log" ] || { echo "$stderr"; return 1; }
  [ "$(sed -n 2p "$OUT/app.log")" = '# tail' ]
  [ "$(wc -l <"$OUT/app.log")" -eq 22 ]
}

@test "a log that is not UTF-8, has CRLF and a very long line is kept" {
  local log="$BATS_TEST_TMPDIR/xcb.log"
  { printf 'Build \xff\xfe started\r\n'
    printf 'x%.0s' $(seq 1 120000)
    printf ' token=FAKElong0001 done\r\n'
    printf 'Executed 3 tests, with 0 failures\r\n'; } >"$log"
  run "$EV" keep "$log" "$OUT" --match '^Executed '
  [ "$status" -eq 0 ] || { echo "$output"; return 1; }
  cmp "$log" "$OUT/raw/xcb.log"
  ! grep -q FAKE "$OUT/xcb.log"
  grep -q ' token=\*\*\* done' "$OUT/xcb.log"
  LC_ALL=C grep -q $'^Build \xff\xfe started$' "$OUT/xcb.log"
  [ "$(sed -n 5p "$OUT/xcb.log")" = 'Executed 3 tests, with 0 failures' ]
}

@test "an empty log and a short log give an excerpt without duplicates" {
  : >"$BATS_TEST_TMPDIR/empty.log"
  run "$EV" keep "$BATS_TEST_TMPDIR/empty.log" "$OUT" --match .
  [ "$status" -eq 0 ] || { echo "$output"; return 1; }
  diff "$OUT/empty.log" - <<'EOF'
# evidence excerpt v1 — raw: raw/empty.log
# tail
EOF
  printf 'one\nExecuted 2 tests, with 0 failures\nthree\n' >"$BATS_TEST_TMPDIR/short.log"
  run "$EV" keep "$BATS_TEST_TMPDIR/short.log" "$OUT" --match '^Executed '
  [ "$status" -eq 0 ] || { echo "$output"; return 1; }
  diff "$OUT/short.log" - <<'EOF'
# evidence excerpt v1 — raw: raw/short.log
# tail
one
Executed 2 tests, with 0 failures
three
EOF
}

@test "keep again with the same name overwrites" {
  keep_fixture
  [ "$status" -eq 0 ] || { echo "$output"; return 1; }
  printf 'second run\n' >"$BATS_TEST_TMPDIR/again.log"
  run "$EV" keep "$BATS_TEST_TMPDIR/again.log" "$OUT" --name app
  [ "$status" -eq 0 ] || { echo "$output"; return 1; }
  cmp "$BATS_TEST_TMPDIR/again.log" "$OUT/raw/app.log"
  [ "$(sed -n 3p "$OUT/app.log")" = 'second run' ]
  [ "$(wc -l <"$OUT/app.log")" -eq 3 ]
  [ "$(cat "$OUT/raw/.gitignore")" = '*' ]
}

@test "a log kept from its own raw copy stays whole" {
  mkdir -p "$OUT/raw"
  cp "$FIX/secrets.log" "$OUT/raw/app.log"
  run "$EV" keep "$OUT/raw/app.log" "$OUT"
  [ "$status" -eq 0 ] || { echo "$output"; return 1; }
  cmp "$FIX/secrets.log" "$OUT/raw/app.log"
}

@test "keep outside a task folder is a usage error" {
  mkdir -p "$BATS_TEST_TMPDIR/loose"
  run "$EV" keep "$FIX/secrets.log" "$BATS_TEST_TMPDIR/loose/evidence"
  [ "$status" -eq 2 ] || { echo "$output"; return 1; }
  [ ! -e "$BATS_TEST_TMPDIR/loose/evidence" ]
}

@test "an unparsable Redact pattern stops with its line" {
  printf '# Project\n\n## Redact\n\n- `acme_live_\\w+`\n- `([`\n' >"$PROJ/SPINE.md"
  run --separate-stderr "$EV" keep "$FIX/secrets.log" "$OUT" --name app
  [ "$status" -eq 2 ] || { echo "$output $stderr"; return 1; }
  [[ "$stderr" == *"SPINE.md line 6:"*'([`'* ]] || { echo "$stderr"; return 1; }
  [ ! -e "$OUT/app.log" ]
}

sha1_of() {
  { shasum "$1" 2>/dev/null || sha1sum "$1"; } | cut -d' ' -f1
}

@test "keep-image moves a viewed screenshot out of raw and lists its sha1" {
  mkdir -p "$OUT/raw"
  printf 'png home screen' >"$OUT/raw/home screen.png"
  local sum
  sum="$(sha1_of "$OUT/raw/home screen.png")"
  run "$EV" keep-image "$OUT/raw/home screen.png" "$OUT"
  [ "$status" -eq 0 ] || { echo "$output"; return 1; }
  [ "$output" = "kept validation-evidence/t/home screen.png sha1=$sum" ] || { echo "$output"; return 1; }
  [ ! -e "$OUT/raw/home screen.png" ]
  [ "$(cat "$OUT/home screen.png")" = 'png home screen' ]
  [ "$(cat "$OUT/kept.txt")" = "$sum  home screen.png" ] || { cat "$OUT/kept.txt"; return 1; }
  run "$EV" check "$TASK"
  [ "$status" -eq 0 ] || { echo "$output"; return 1; }
  [ -z "$output" ]
}

@test "keep-image of a screenshot kept before replaces its kept.txt line" {
  mkdir -p "$OUT/raw"
  printf 'first' >"$OUT/raw/a b.PNG"
  run "$EV" keep-image "$OUT/raw/a b.PNG" "$OUT"
  [ "$status" -eq 0 ] || { echo "$output"; return 1; }
  printf 'second' >"$OUT/raw/a b.PNG"
  run "$EV" keep-image "$OUT/raw/a b.PNG" "$OUT"
  [ "$status" -eq 0 ] || { echo "$output"; return 1; }
  [ "$(cat "$OUT/kept.txt")" = "$(sha1_of "$OUT/a b.PNG")  a b.PNG" ] || { cat "$OUT/kept.txt"; return 1; }
}

@test "keep-image refuses an image that is not in raw" {
  mkdir -p "$OUT/raw" "$TASK/other/raw"
  printf 'png' >"$OUT/shot.png"
  run "$EV" keep-image "$OUT/shot.png" "$OUT"
  [ "$status" -eq 2 ] || { echo "$output"; return 1; }
  [ -e "$OUT/shot.png" ]
  printf 'png' >"$TASK/other/raw/shot.png"
  run "$EV" keep-image "$TASK/other/raw/shot.png" "$OUT"
  [ "$status" -eq 2 ] || { echo "$output"; return 1; }
  [ -e "$TASK/other/raw/shot.png" ]
  printf 'text' >"$OUT/raw/notes.txt"
  run "$EV" keep-image "$OUT/raw/notes.txt" "$OUT"
  [ "$status" -eq 2 ] || { echo "$output"; return 1; }
  [ -e "$OUT/raw/notes.txt" ]
  [ ! -e "$OUT/kept.txt" ]
}

@test "check finds each kind of foreign evidence" {
  keep_fixture
  [ "$status" -eq 0 ] || { echo "$output"; return 1; }
  printf 'password=FAKEhand0018\n' >>"$OUT/app.log"
  cp "$FIX/secrets.log" "$OUT/copy.log"
  printf 'png x' >"$OUT/x.png"
  printf 'png home' >"$OUT/raw/home screen.png"
  run "$EV" keep-image "$OUT/raw/home screen.png" "$OUT"
  [ "$status" -eq 0 ] || { echo "$output"; return 1; }
  printf 'png home, edited' >"$OUT/home screen.png"
  printf 'notes\n' >"$OUT/notes.txt"
  run --separate-stderr "$EV" check "$TASK"
  [ "$status" -eq 1 ] || { echo "$output $stderr"; return 1; }
  diff <(printf '%s\n' "$output") - <<'EOF2'
evidence path=validation-evidence/t/app.log reason=secret
evidence path=validation-evidence/t/copy.log reason=unmarked
evidence path=validation-evidence/t/home screen.png reason=changed
evidence path=validation-evidence/t/notes.txt reason=other
evidence path=validation-evidence/t/x.png reason=unlisted
EOF2
}

@test "check passes a clean task and its step folders" {
  local step="$TASK/a.step/validation-evidence/t"
  run "$EV" keep "$FIX/secrets.log" "$OUT" --name app --match .
  [ "$status" -eq 0 ] || { echo "$output"; return 1; }
  run "$EV" keep "$FIX/secrets.log" "$step" --name app --match 'error:'
  [ "$status" -eq 0 ] || { echo "$output"; return 1; }
  mkdir -p "$OUT/raw" "$step/raw" "$TASK/phase-evidence/phase-1"
  printf 'png one' >"$OUT/raw/home screen.png"
  printf 'png two' >"$step/raw/list.jpeg"
  "$EV" keep-image "$OUT/raw/home screen.png" "$OUT" >/dev/null
  "$EV" keep-image "$step/raw/list.jpeg" "$step" >/dev/null
  printf '# Notes\n' >"$TASK/phase-evidence/phase-1/notes.md"
  printf '# Summary\n' >"$step/summary.md"
  run "$EV" check "$TASK"
  [ "$status" -eq 0 ] || { echo "$output"; return 1; }
  [ -z "$output" ]
}

@test "check walks step folders at any depth and no other folder" {
  mkdir -p "$TASK/a.step/b.step/phase-evidence/p" "$TASK/other" "$TASK/experiment" "$TASK/a.step/scratch"
  printf 'x\n' >"$TASK/a.step/b.step/phase-evidence/p/x.txt"
  printf 'x\n' >"$TASK/notes.txt"
  printf 'x\n' >"$TASK/other/x.txt"
  printf 'x\n' >"$TASK/experiment/x.txt"
  printf 'x\n' >"$TASK/a.step/scratch/y.txt"
  run "$EV" check "$TASK"
  [ "$status" -eq 1 ] || { echo "$output"; return 1; }
  [ "$output" = 'evidence path=a.step/b.step/phase-evidence/p/x.txt reason=other' ] || { echo "$output"; return 1; }
}

@test "check never reads raw" {
  mkdir -p "$OUT/raw" "$TASK/a.step/phase-evidence/p/raw"
  cp "$FIX/secrets.log" "$OUT/raw/app.log"
  printf '*\n' >"$OUT/raw/.gitignore"
  printf 'png' >"$OUT/raw/x.png"
  cp "$FIX/secrets.log" "$TASK/a.step/phase-evidence/p/raw/x.log"
  run "$EV" check "$TASK"
  [ "$status" -eq 0 ] || { echo "$output"; return 1; }
  [ -z "$output" ]
}

@test "check stops on a folder that is no task, and on a Redact line that does not parse" {
  mkdir -p "$BATS_TEST_TMPDIR/loose"
  run "$EV" check "$BATS_TEST_TMPDIR/loose"
  [ "$status" -eq 2 ] || { echo "$output"; return 1; }
  printf '# Project\n\n## Redact\n\n- `([`\n' >"$PROJ/SPINE.md"
  run --separate-stderr "$EV" check "$TASK"
  [ "$status" -eq 2 ] || { echo "$output $stderr"; return 1; }
  [[ "$stderr" == *"SPINE.md line 5:"* ]] || { echo "$stderr"; return 1; }
}

@test "Authorization with any scheme, or none, loses its credential" {
  printf '%s\n' 'Authorization: Token FAKEtok0019' 'Authorization: Digest FAKEdig0020' \
    'authorization: Negotiate FAKEneg0021' 'Authorization: FAKEbare0022' \
    'Authorization: Digest username="u", response="FAKEdigresp0024"' >"$BATS_TEST_TMPDIR/auth.log"
  run "$EV" keep "$BATS_TEST_TMPDIR/auth.log" "$OUT"
  [ "$status" -eq 0 ] || { echo "$output"; return 1; }
  [ "$output" = 'kept validation-evidence/t/auth.log redacted=5' ] || { echo "$output"; return 1; }
  diff "$OUT/auth.log" - <<'EOF2'
# evidence excerpt v1 — raw: raw/auth.log
# tail
Authorization: Token ***
Authorization: Digest ***
authorization: Negotiate ***
Authorization: ***
Authorization: Digest ***
EOF2
  run "$EV" check "$TASK"
  [ "$status" -eq 0 ] || { echo "$output"; return 1; }
}

@test "a quoted value with an escaped quote is masked whole" {
  printf '%s\n' '{"token": "a\"FAKEesc0023", "user": "tester"}' >"$BATS_TEST_TMPDIR/esc.log"
  run "$EV" keep "$BATS_TEST_TMPDIR/esc.log" "$OUT"
  [ "$status" -eq 0 ] || { echo "$output"; return 1; }
  [ "$(sed -n 3p "$OUT/esc.log")" = '{"token": "***", "user": "tester"}' ] || { cat "$OUT/esc.log"; return 1; }
}

@test "keep with no --match says nothing about matches" {
  printf 'one\n' >"$BATS_TEST_TMPDIR/one.log"
  run --separate-stderr "$EV" keep "$BATS_TEST_TMPDIR/one.log" "$OUT"
  [ "$status" -eq 0 ] || { echo "$output $stderr"; return 1; }
  [ -z "$stderr" ] || { echo "$stderr"; return 1; }
}

@test "a usage error prints the header's usage, every subcommand in it" {
  local cmd
  for cmd in "" bogus; do
    run --separate-stderr "$EV" $cmd
    [ "$status" -eq 2 ] || { echo "$cmd: $stderr"; return 1; }
    [[ "$stderr" == *"Usage: scripts/evidence.sh keep <log> <evidence dir>"* ]] || { echo "$stderr"; return 1; }
    [[ "$stderr" == *"scripts/evidence.sh keep-image <image> <evidence dir>"* ]] || { echo "$stderr"; return 1; }
    [[ "$stderr" == *"scripts/evidence.sh check <task dir>"* ]] || { echo "$stderr"; return 1; }
    [[ "$stderr" == *"Exit:"* ]] || { echo "$stderr"; return 1; }
  done
}

@test "no project config stops keep and check with a line of their own" {
  rm "$PROJ/SPINE.md"
  run --separate-stderr "$EV" keep "$FIX/secrets.log" "$OUT" --name app
  [ "$status" -eq 2 ] || { echo "$output $stderr"; return 1; }
  [[ "$stderr" == *"evidence: "*"no project config"* ]] || { echo "$stderr"; return 1; }
  [ ! -e "$OUT/app.log" ]
  run --separate-stderr "$EV" check "$TASK"
  [ "$status" -eq 2 ] || { echo "$output $stderr"; return 1; }
  [[ "$stderr" == *"evidence: "*"no project config"* ]] || { echo "$stderr"; return 1; }
}
