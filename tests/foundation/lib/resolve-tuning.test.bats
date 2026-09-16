#!/usr/bin/env bats
# The resolver is the one reader of ## Models, ## Effort, [MODELS] and [EFFORT], and the orchestrator
# ships what it prints. A key-by-key chain resolved in prose cannot be tested, so it lives here.

setup() {
  ROOT="$(cd -- "$(dirname -- "$BATS_TEST_FILENAME")/../../.." && pwd)"
  RESOLVE="$ROOT/scripts/resolve-tuning.sh"
  PROJ="$BATS_TEST_TMPDIR/proj"
  TASK="$PROJ/Tasks/ACTIVE/042-a-task"
  mkdir -p "$TASK"
  printf '# CLAUDE-spine-toolkit.md\n\n## Mode\n\nmanual\n' >"$PROJ/CLAUDE-spine-toolkit.md"
  printf '[TASK_TYPE] = [BUG]\n[NEED_TEST] = [true]\n' >"$TASK/Task.md"
  ERR="$BATS_TEST_TMPDIR/err"
}

DEFAULT_MODELS='models={light: sonnet, architect: session, developer: session, tester: session, reviewer: session, refactorer: session, validator: sonnet, security: session, diagnostics: session}'
DEFAULT_EFFORT='effort={architect: session, developer: session, tester: session, reviewer: session, refactorer: session, validator: session, security: session, diagnostics: session}'

@test "a project that says nothing resolves to the defaults, models line first" {
  run "$RESOLVE" "$TASK"
  [ "$status" -eq 0 ]
  [ "${#lines[@]}" -eq 2 ] || { echo "$output"; return 1; }
  [ "${lines[0]}" = "$DEFAULT_MODELS" ] || { echo "$output"; return 1; }
  [ "${lines[1]}" = "$DEFAULT_EFFORT" ] || { echo "$output"; return 1; }
}

@test "the project's blocks move the keys they name and no other" {
  printf '## Models\n\nlight: haiku\narchitect: opus\n\n## Effort\n\nreviewer: high\n' >"$PROJ/CLAUDE-spine-toolkit.md"
  out="$("$RESOLVE" "$TASK")"
  [ "$(sed -n 1p <<<"$out")" = 'models={light: haiku, architect: opus, developer: session, tester: session, reviewer: session, refactorer: session, validator: sonnet, security: session, diagnostics: session}' ] \
    || { echo "$out"; return 1; }
  [ "$(sed -n 2p <<<"$out")" = 'effort={architect: session, developer: session, tester: session, reviewer: high, refactorer: session, validator: session, security: session, diagnostics: session}' ] \
    || { echo "$out"; return 1; }
}

@test "a task key beats the project's, and a key the task does not name keeps the project's value" {
  printf '## Models\n\narchitect: opus\nreviewer: opus\n' >"$PROJ/CLAUDE-spine-toolkit.md"
  printf '[TASK_TYPE] = [BUG]\n[MODELS] = [architect: sonnet]\n' >"$TASK/Task.md"
  out="$("$RESOLVE" "$TASK")"
  grep -qF 'architect: sonnet' <<<"$out" || { echo "$out"; return 1; }
  grep -qF 'reviewer: opus' <<<"$out" || { echo "$out"; return 1; }
}

@test "the template's commented override line is not a value" {
  printf '[TASK_TYPE] = [BUG]\n# [MODELS] = [architect: opus]  # <key>: <opus|sonnet|haiku|fable|session>, comma-separated\n' >"$TASK/Task.md"
  run "$RESOLVE" "$TASK"
  [ "${lines[0]}" = "$DEFAULT_MODELS" ] || { echo "$output"; return 1; }
}

@test "a step reads the epic's Task.md between its own and the project's" {
  printf '## Effort\n\nreviewer: max\n' >"$PROJ/CLAUDE-spine-toolkit.md"
  printf '[TASK_TYPE] = [EPIC]\n[EFFORT] = [reviewer: high, tester: low]\n' >"$TASK/Task.md"
  STEP="$TASK/1.step"
  mkdir -p "$STEP"
  printf '[TASK_TYPE] = [FEATURE]\n[EFFORT] = [tester: medium]\n' >"$STEP/Task.md"
  out="$("$RESOLVE" "$STEP")"
  grep -qF 'tester: medium' <<<"$out" || { echo "the step's own key lost: $out"; return 1; }
  grep -qF 'reviewer: high' <<<"$out" || { echo "the epic's key did not reach the step: $out"; return 1; }
}

@test "a folder that is not a step never reads the Task.md above it" {
  printf '[TASK_TYPE] = [EPIC]\n[MODELS] = [architect: opus]\n' >"$PROJ/Tasks/ACTIVE/Task.md"
  out="$("$RESOLVE" "$TASK")"
  grep -qF 'architect: session' <<<"$(sed -n 1p <<<"$out")" || { echo "$out"; return 1; }
}

@test "an unusable entry is reported, skipped, and the next source applies" {
  printf '## Models\n\narchitect: opus\n' >"$PROJ/CLAUDE-spine-toolkit.md"
  printf '[TASK_TYPE] = [BUG]\n[MODELS] = [architect: gpt, planner: opus]\n' >"$TASK/Task.md"
  out="$("$RESOLVE" "$TASK" 2>"$ERR")"
  grep -qF 'architect: opus' <<<"$out" || { echo "$out"; return 1; }
  grep -qF "Task.md [MODELS]: 'architect: gpt' not recognized, skipped" "$ERR" || { cat "$ERR"; return 1; }
  grep -qF "Task.md [MODELS]: 'planner: opus' not recognized, skipped" "$ERR" || { cat "$ERR"; return 1; }
}

@test "init is not a key, because no profile dispatches it" {
  printf '## Models\n\ninit: opus\n' >"$PROJ/CLAUDE-spine-toolkit.md"
  "$RESOLVE" "$TASK" 2>"$ERR" >/dev/null
  grep -qF "## Models: 'init: opus' not recognized, skipped" "$ERR" || { cat "$ERR"; return 1; }
}

@test "light is a model key and not an effort key" {
  printf '## Effort\n\nlight: low\n' >"$PROJ/CLAUDE-spine-toolkit.md"
  "$RESOLVE" "$TASK" 2>"$ERR" >/dev/null
  grep -qF "## Effort: 'light: low' not recognized, skipped" "$ERR" || { cat "$ERR"; return 1; }
}

@test "keys and values are read case-insensitively" {
  printf '[TASK_TYPE] = [BUG]\n[MODELS] = [Architect: Opus]\n' >"$TASK/Task.md"
  out="$("$RESOLVE" "$TASK")"
  grep -qF 'architect: opus' <<<"$out" || { echo "$out"; return 1; }
}

@test "the shipped config template resolves to the defaults and reports nothing" {
  cp "$ROOT/templates/claude-toolkit-md/en.md" "$PROJ/CLAUDE-spine-toolkit.md"
  out="$("$RESOLVE" "$TASK" 2>"$ERR")"
  [ ! -s "$ERR" ] || { echo "the template's guidance was read as entries:"; cat "$ERR"; return 1; }
  [ "$(sed -n 1p <<<"$out")" = "$DEFAULT_MODELS" ] || { echo "$out"; return 1; }
  [ "$(sed -n 2p <<<"$out")" = "$DEFAULT_EFFORT" ] || { echo "$out"; return 1; }
}

@test "a usage error exits 2" {
  run "$RESOLVE"
  [ "$status" -eq 2 ]
  run "$RESOLVE" "$BATS_TEST_TMPDIR/missing"
  [ "$status" -eq 2 ]
}

@test "the config's last entry for a repeated key wins, not the first" {
  cp "$ROOT/templates/claude-toolkit-md/en.md" "$PROJ/CLAUDE-spine-toolkit.md"
  awk '{print} /^architect: session$/ && !done {print "architect: opus"; done=1}' \
    "$PROJ/CLAUDE-spine-toolkit.md" >"$PROJ/CLAUDE-spine-toolkit.md.new"
  mv "$PROJ/CLAUDE-spine-toolkit.md.new" "$PROJ/CLAUDE-spine-toolkit.md"
  out="$("$RESOLVE" "$TASK" 2>"$ERR")"
  [ ! -s "$ERR" ] || { echo "unexpected stderr:"; cat "$ERR"; return 1; }
  grep -qF 'architect: opus' <<<"$out" || { echo "$out"; return 1; }
}

@test "a Task.md MODELS line's last entry for a repeated key wins" {
  printf '[TASK_TYPE] = [BUG]\n[MODELS] = [developer: opus, developer: sonnet]\n' >"$TASK/Task.md"
  out="$("$RESOLVE" "$TASK")"
  grep -qF 'developer: sonnet' <<<"$out" || { echo "$out"; return 1; }
  ! grep -qF 'developer: opus' <<<"$out" || { echo "kept the first entry: $out"; return 1; }
}

@test "two EFFORT lines in one Task.md fold in file order, last wins per key" {
  printf '[TASK_TYPE] = [BUG]\n[EFFORT] = [reviewer: low, developer: medium]\n[EFFORT] = [reviewer: high]\n' >"$TASK/Task.md"
  out="$("$RESOLVE" "$TASK")"
  grep -qF 'reviewer: high' <<<"$out" || { echo "$out"; return 1; }
  grep -qF 'developer: medium' <<<"$out" || { echo "the first line's other key was lost: $out"; return 1; }
}

@test "resolve-tuning.sh . inside a step folder still reaches the epic's Task.md" {
  printf '[TASK_TYPE] = [EPIC]\n[MODELS] = [architect: opus]\n' >"$TASK/Task.md"
  STEP="$TASK/1.step"
  mkdir -p "$STEP"
  printf '[TASK_TYPE] = [FEATURE]\n' >"$STEP/Task.md"
  out="$(cd "$STEP" && "$RESOLVE" .)"
  grep -qF 'architect: opus' <<<"$out" || { echo "the epic's key did not reach the step via '.': $out"; return 1; }
}

@test "a config written by 1.11.0 keeps every model it had and reports nothing" {
  printf '## Models\n\nlight: sonnet\n' >"$PROJ/CLAUDE-spine-toolkit.md"
  for role in architect developer tester reviewer refactorer validator security diagnostics; do
    printf '%s: platform\n' "$role" >>"$PROJ/CLAUDE-spine-toolkit.md"
  done
  out="$("$RESOLVE" "$TASK" 2>"$ERR")"
  [ ! -s "$ERR" ] || { echo "platform was reported:"; cat "$ERR"; return 1; }
  [ "$(sed -n 1p <<<"$out")" = "$DEFAULT_MODELS" ] || { echo "$out"; return 1; }
}

@test "light: platform reads as absent, so light keeps its sonnet default" {
  printf '## Models\n\nlight: platform\n' >"$PROJ/CLAUDE-spine-toolkit.md"
  out="$("$RESOLVE" "$TASK" 2>"$ERR")"
  [ ! -s "$ERR" ] || { cat "$ERR"; return 1; }
  grep -qF 'light: sonnet' <<<"$out" || { echo "$out"; return 1; }
}

@test "a task's platform entry leaves the project's value in place" {
  printf '## Models\n\narchitect: opus\n' >"$PROJ/CLAUDE-spine-toolkit.md"
  printf '[TASK_TYPE] = [BUG]\n[MODELS] = [architect: platform]\n' >"$TASK/Task.md"
  out="$("$RESOLVE" "$TASK" 2>"$ERR")"
  [ ! -s "$ERR" ] || { cat "$ERR"; return 1; }
  grep -qF 'architect: opus' <<<"$out" || { echo "$out"; return 1; }
}

@test "platform is still reported under an unknown models key and in Effort" {
  printf '## Models\n\nplanner: platform\n\n## Effort\n\nreviewer: platform\n' >"$PROJ/CLAUDE-spine-toolkit.md"
  "$RESOLVE" "$TASK" 2>"$ERR" >/dev/null
  grep -qF "## Models: 'planner: platform' not recognized, skipped" "$ERR" || { cat "$ERR"; return 1; }
  grep -qF "## Effort: 'reviewer: platform' not recognized, skipped" "$ERR" || { cat "$ERR"; return 1; }
}

@test "a task can name session over the project's model" {
  printf '## Models\n\nvalidator: opus\n' >"$PROJ/CLAUDE-spine-toolkit.md"
  printf '[TASK_TYPE] = [BUG]\n[MODELS] = [validator: session]\n' >"$TASK/Task.md"
  out="$("$RESOLVE" "$TASK" 2>"$ERR")"
  [ ! -s "$ERR" ] || { cat "$ERR"; return 1; }
  grep -qF 'validator: session' <<<"$(sed -n 1p <<<"$out")" || { echo "$out"; return 1; }
}

@test "a platform entry in the epic's Task.md reads as absent for its step" {
  printf '## Models\n\narchitect: opus\n' >"$PROJ/CLAUDE-spine-toolkit.md"
  printf '[TASK_TYPE] = [EPIC]\n[MODELS] = [architect: platform]\n' >"$TASK/Task.md"
  STEP="$TASK/1.step"
  mkdir -p "$STEP"
  printf '[TASK_TYPE] = [FEATURE]\n' >"$STEP/Task.md"
  out="$("$RESOLVE" "$STEP" 2>"$ERR")"
  [ ! -s "$ERR" ] || { cat "$ERR"; return 1; }
  grep -qF 'architect: opus' <<<"$(sed -n 1p <<<"$out")" || { echo "$out"; return 1; }
}
