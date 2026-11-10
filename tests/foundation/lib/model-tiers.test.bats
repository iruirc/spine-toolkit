#!/usr/bin/env bats
# A project written before the model tiers names `sonnet` in [MODELS]; model-tiers.sh says so,
# turns it into `fast`, and writes the [MODEL_TIERS] line that gives `fast` its model in each runtime
# (docs/superpowers/specs/2026-11-10-model-tiers-design.md, section 3). Every test works on a copy.

bats_require_minimum_version 1.5.0

setup() {
  ROOT="$(cd -- "$(dirname -- "$BATS_TEST_FILENAME")/../../.." && pwd)"
  MT="$ROOT/scripts/model-tiers.sh"
  P="$BATS_TEST_TMPDIR/p"
  CFG="$P/SPINE.md"
  mkdir -p "$P"
}

# The config a project had before the tiers: sonnet named outright, no [MODEL_TIERS].
old_config() {
  printf '%s\n' \
    '[LANGUAGE] = [en]' \
    '[MODELS] = [light: sonnet, architect: session, validator: sonnet, tester: opus]  # who runs on what' \
    '[EFFORT] = [tester: high]' >"$CFG"
}

json_field() { python3 -c 'import json,sys; d=json.load(sys.stdin); print(eval(sys.argv[1], {"d": d}))' "$1"; }

@test "check names sonnet keys, and a missing tier line only where a key says fast" {
  old_config
  run --separate-stderr "$MT" check "$CFG" --runtime codex-cli
  [ "$status" -eq 0 ]
  [ "$output" = 'sonnet light,validator' ] || { echo "$output"; false; }
  [ -z "$stderr" ]
  printf '%s\n' '[MODELS] = [light: sonnet, validator: fast]' >"$CFG"
  run --separate-stderr "$MT" check "$CFG" --runtime codex-cli
  [ "$output" = $'sonnet light\ntier-missing fast@codex-cli' ] || { echo "$output"; false; }
}

# A tier nobody uses needs no model: a rerun of setup must not ask about it every time.
@test "check asks for no tier line in a config with no fast entry" {
  printf '%s\n' '[MODELS] = [light: session, architect: session, validator: session, tester: opus]' >"$CFG"
  for rt in codex-cli claude-code; do
    run --separate-stderr "$MT" check "$CFG" --runtime "$rt"
    [ "$status" -eq 0 ]
    [ -z "$output" ] || { echo "$rt: $output"; false; }
  done
  printf '%s\n' '# [MODELS] = [light: fast]' '[MODELS] = [light: session]' >"$CFG"
  run "$MT" check "$CFG" --runtime codex-cli
  [ -z "$output" ] || { echo "a commented-out fast counted: $output"; false; }
}

# "Keep the session's model" in setup writes this, so the question is not asked again.
@test "apply --set takes session as the tier's model, and check is then quiet" {
  cp "$ROOT/templates/spine-md/en.md" "$CFG"
  run --separate-stderr "$MT" apply "$CFG" --set fast@codex-cli=session
  [ "$status" -eq 0 ]
  grep -qE '^\[MODEL_TIERS\] = \[fast@claude-code: sonnet, fast@codex-cli: session\]' "$CFG" || { cat "$CFG"; false; }
  run "$MT" check "$CFG" --runtime codex-cli
  [ -z "$output" ] || { echo "$output"; false; }
  t="$P/Tasks/ACTIVE/001-x"; mkdir -p "$t"; cp "$ROOT/templates/task-md/task-root.md" "$t/Task.md"
  run --separate-stderr "$ROOT/scripts/resolve-settings.sh" show "$t" --runtime codex-cli
  [ "$status" -eq 0 ]; [ -z "$stderr" ] || { echo "$stderr"; false; }
  grep -qF 'validator: fast → session, light: fast → session]' <<<"$output" || { echo "$output"; false; }
  [ -z "$(grep -F 'no fast@' <<<"$output")" ] || { echo "$output"; false; }
}

@test "check on the new template prints nothing for claude-code" {
  cp "$ROOT/templates/spine-md/en.md" "$CFG"
  run "$MT" check "$CFG" --runtime claude-code
  [ "$status" -eq 0 ]
  [ -z "$output" ] || { echo "$output"; false; }
}

@test "check on the new template asks for the other runtime only" {
  cp "$ROOT/templates/spine-md/en.md" "$CFG"
  run "$MT" check "$CFG" --runtime codex-cli
  [ "$status" -eq 0 ]
  [ "$output" = "tier-missing fast@codex-cli" ] || { echo "$output"; false; }
}

@test "check does not read a commented-out line" {
  printf '%s\n' '# [MODELS] = [light: sonnet]' '  [MODELS] = [validator: sonnet]' '[MODELS] = [tester: fast]' \
    '# [MODEL_TIERS] = [fast@claude-code: sonnet]' >"$CFG"
  run "$MT" check "$CFG" --runtime claude-code
  [ "$output" = $'tier-missing fast@claude-code' ] || { echo "$output"; false; }
}

@test "apply --migrate rewrites sonnet and adds the claude-code line" {
  old_config
  run "$MT" apply "$CFG" --migrate
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  grep -qxF '[MODEL_TIERS] = [fast@claude-code: sonnet]' "$CFG"
  [ "$(grep -n '^\[MODEL_TIERS\]' "$CFG" | cut -d: -f1)" -eq "$(( $(grep -n '^\[MODELS\]' "$CFG" | cut -d: -f1) - 1 ))" ]
  grep -qxF '[MODELS] = [light: fast, architect: session, validator: fast, tester: opus]  # who runs on what' "$CFG"
  grep -qxF '[LANGUAGE] = [en]' "$CFG"
  grep -qxF '[EFFORT] = [tester: high]' "$CFG"
  [ "$(wc -l <"$CFG" | tr -d ' ')" -eq 4 ]
}

@test "apply --migrate matches sonnet in any case and leaves other values alone" {
  printf '%s\n' '[MODELS] = [light: Sonnet, tester: sonnet-4, validator: SONNET, developer: opus]' >"$CFG"
  run "$MT" apply "$CFG" --migrate
  grep -qxF '[MODELS] = [light: fast, tester: sonnet-4, validator: fast, developer: opus]' "$CFG"
}

@test "apply --set adds a Codex line and never overwrites one" {
  cp "$ROOT/templates/spine-md/en.md" "$CFG"
  run "$MT" apply "$CFG" --set fast@codex-cli=gpt-6-mini
  [ "$status" -eq 0 ]
  grep -qxE '\[MODEL_TIERS\] = \[fast@claude-code: sonnet, fast@codex-cli: gpt-6-mini\] +# .*' "$CFG"
  run "$MT" apply "$CFG" --set fast@codex-cli=other
  [ "$status" -eq 0 ]
  grep -qF 'fast@codex-cli: gpt-6-mini' "$CFG"
  [ -z "$(grep -F 'fast@codex-cli: other' "$CFG")" ] || { grep -F MODEL_TIERS "$CFG"; false; }
  [ "$(grep -c 'fast@codex-cli' "$CFG")" -eq 1 ]
}

@test "apply --set keeps the trailing comment and fills an empty line without a comma" {
  printf '%s\n' '[MODEL_TIERS] = []  # per runtime' '[MODELS] = [light: fast]' >"$CFG"
  run "$MT" apply "$CFG" --set fast@codex-cli=gpt-6-mini
  [ "$status" -eq 0 ]
  [ "$(head -n1 "$CFG")" = '[MODEL_TIERS] = [fast@codex-cli: gpt-6-mini]  # per runtime' ] || { cat "$CFG"; false; }
}

@test "apply --set puts a missing line above MODELS, or at the end when there is none" {
  printf '%s\n' '[LANGUAGE] = [en]' '[MODELS] = [light: fast]' >"$CFG"
  run "$MT" apply "$CFG" --set fast@codex-cli=gpt-6-mini
  [ "$(cat "$CFG")" = $'[LANGUAGE] = [en]\n[MODEL_TIERS] = [fast@codex-cli: gpt-6-mini]\n[MODELS] = [light: fast]' ] || { cat "$CFG"; false; }
  printf '[LANGUAGE] = [en]' >"$CFG"
  run "$MT" apply "$CFG" --set fast@codex-cli=gpt-6-mini
  [ "$(cat "$CFG")" = $'[LANGUAGE] = [en]\n[MODEL_TIERS] = [fast@codex-cli: gpt-6-mini]' ] || { cat "$CFG"; false; }
}

@test "apply takes tier and runtime in any case as already there" {
  printf '%s\n' '[MODEL_TIERS] = [Fast@Codex-CLI: gpt-6-mini]' '[MODELS] = [light: fast]' >"$CFG"
  cp "$CFG" "$BATS_TEST_TMPDIR/before"
  run "$MT" apply "$CFG" --set fast@codex-cli=other
  cmp "$CFG" "$BATS_TEST_TMPDIR/before"
  run "$MT" check "$CFG" --runtime codex-cli
  [ -z "$output" ]
}

@test "apply is idempotent and covers folded MODELS lines" {
  printf '%s\n' \
    '[MODELS] = [light: sonnet, architect: session]' \
    '[MODELS] = [validator: sonnet, tester: opus]' >"$CFG"
  run "$MT" apply "$CFG" --migrate
  [ "$status" -eq 0 ]
  cp "$CFG" "$BATS_TEST_TMPDIR/first"
  [ -z "$(grep '^\[MODELS\]' "$CFG" | grep -i sonnet)" ] || { cat "$CFG"; false; }
  run "$MT" apply "$CFG" --migrate
  [ "$status" -eq 0 ]
  cmp "$CFG" "$BATS_TEST_TMPDIR/first"
  [ "$(grep -c '^\[MODEL_TIERS\]' "$CFG")" -eq 1 ]
  run "$MT" check "$CFG" --runtime claude-code
  [ -z "$output" ]
}

@test "apply leaves the file's line endings and a missing final newline alone" {
  printf '[MODELS] = [light: sonnet]\r\n[EFFORT] = [tester: high]' >"$CFG"
  run "$MT" apply "$CFG" --migrate
  [ "$(od -An -c "$CFG" | tr -d ' \n')" = '[MODEL_TIERS]=[fast@claude-code:sonnet]\r\n[MODELS]=[light:fast]\r\n[EFFORT]=[tester:high]' ] \
    || { od -c "$CFG"; false; }
}

@test "apply keeps the file's permissions and leaves no temp file behind" {
  old_config
  chmod 640 "$CFG"
  run "$MT" apply "$CFG" --migrate
  [ "$status" -eq 0 ]
  # GNU first, as scripts/long-run.sh reads a file: BSD stat has no -c, and GNU stat -f reads the filesystem.
  [ "$(stat -c %a "$CFG" 2>/dev/null || stat -f %Lp "$CFG")" = "640" ]
  [ "$(ls -A "$P")" = "SPINE.md" ]
}

@test "the resolver reads what apply wrote" {
  t="$P/Tasks/ACTIVE/001-x"; mkdir -p "$t"; cp "$ROOT/templates/task-md/task-root.md" "$t/Task.md"
  old_config
  run "$MT" apply "$CFG" --migrate --set fast@codex-cli=gpt-6-mini
  [ "$status" -eq 0 ]
  run --separate-stderr "$ROOT/scripts/resolve-settings.sh" json "$t" --runtime codex-cli
  [ "$status" -eq 0 ]
  # tester: opus is no Codex model, and is the only thing the resolver has to say about this file
  [ "$stderr" = "$CFG [MODELS]: 'tester: opus' is not a codex-cli model, read as session" ] || { echo "$stderr"; false; }
  [ "$(json_field 'd["models"]["validator"]' <<<"$output")" = "gpt-6-mini" ]
  run --separate-stderr "$ROOT/scripts/resolve-settings.sh" json "$t" --runtime claude-code
  [ "$status" -eq 0 ]; [ -z "$stderr" ]
  [ "$(json_field 'd["models"]["validator"]' <<<"$output")" = "sonnet" ]
  [ "$(json_field 'd["models"]["architect"]' <<<"$output")" = "session" ]
  [ "$(json_field 'd["models"]["tester"]' <<<"$output")" = "opus" ]
}

@test "usage errors exit 2 with a usage line" {
  old_config
  for args in \
    "" "bogus $CFG" "check" "check $CFG" "check $CFG --runtime" "check $CFG --runtime Codex_CLI" \
    "check $CFG --runtime codex-cli extra" "check $P/none.md --runtime codex-cli" "check $P --runtime codex-cli" \
    "apply $CFG" "apply $CFG --set" "apply $CFG --set fast@codex-cli" "apply $CFG --set fast@=m" \
    "apply $CFG --set slow@codex-cli=m" "apply $CFG --set fast@Codex=m" "apply $CFG --set fast@codex-cli=a,b" \
    "apply $CFG --set fast@codex-cli=a]b" "apply $CFG --set fast@codex-cli=-m" "apply $CFG --migrate --runtime x" \
    "apply $P/none.md --migrate"; do
    cp "$CFG" "$BATS_TEST_TMPDIR/before"
    run --separate-stderr "$MT" $args
    [ "$status" -eq 2 ] || { echo "args: $args -> $status"; false; }
    grep -q '^usage:' <<<"$stderr" || { echo "args: $args -> no usage line: $stderr"; false; }
    [ -z "$output" ]
    cmp "$CFG" "$BATS_TEST_TMPDIR/before"
  done
}

# setup's step 6e reports an apply that could not write, and carries on: not a usage error.
@test "apply that cannot write exits 1 with one line, and leaves the config as it was" {
  [ "$(id -u)" -ne 0 ] || skip "root writes into a read-only folder"
  old_config
  cp "$CFG" "$BATS_TEST_TMPDIR/before"
  chmod 555 "$P"
  run --separate-stderr "$MT" apply "$CFG" --migrate
  chmod 755 "$P"
  [ "$status" -eq 1 ] || { echo "status $status: $stderr"; false; }
  [ -z "$output" ]
  [ "$(printf '%s\n' "$stderr" | wc -l | tr -d ' ')" -eq 1 ] || { echo "$stderr"; false; }
  grep -q '^model-tiers: ' <<<"$stderr" || { echo "$stderr"; false; }
  [ -z "$(grep '^usage:' <<<"$stderr")" ] || { echo "$stderr"; false; }
  cmp "$CFG" "$BATS_TEST_TMPDIR/before"
  [ "$(ls -A "$P")" = "SPINE.md" ]
}

# What setup's step 6e relies on for a project it has just created: the template's own config.
@test "a config made from the template asks the Codex question and no Claude Code one" {
  cp "$ROOT/templates/spine-md/en.md" "$CFG"
  run "$MT" check "$CFG" --runtime claude-code
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  run "$MT" check "$CFG" --runtime codex-cli
  [ "$status" -eq 0 ]
  [ "$output" = "tier-missing fast@codex-cli" ]
  run "$MT" apply "$CFG" --set fast@codex-cli=gpt-5.1-codex-mini
  [ "$status" -eq 0 ]
  run "$MT" check "$CFG" --runtime codex-cli
  [ -z "$output" ]
  grep -qE '^\[MODEL_TIERS\] = \[fast@claude-code: sonnet, fast@codex-cli: gpt-5.1-codex-mini\]' "$CFG"
}
