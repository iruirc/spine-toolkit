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

@test "check names sonnet keys and a missing tier line" {
  old_config
  run --separate-stderr "$MT" check "$CFG" --runtime codex-cli
  [ "$status" -eq 0 ]
  [ "$output" = $'sonnet light,validator\ntier-missing fast@codex-cli' ] || { echo "$output"; false; }
  [ -z "$stderr" ]
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
  printf '%s\n' '# [MODELS] = [light: sonnet]' '  [MODELS] = [validator: sonnet]' \
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
  ! grep -qF other "$CFG"
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
  ! grep '^\[MODELS\]' "$CFG" | grep -qi sonnet
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
  [ "$(stat -f %Lp "$CFG" 2>/dev/null || stat -c %a "$CFG")" = "640" ]
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
