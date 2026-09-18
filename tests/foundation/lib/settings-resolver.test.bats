#!/usr/bin/env bats
# Every setting a task runs with comes from one chain and one reader (scripts/resolve-settings.sh).
# The chain is what a project's choice travels along; a chain resolved in prose cannot be tested,
# which is why five surfaces used to resolve it five ways.

setup() {
  ROOT="$(cd -- "$(dirname -- "$BATS_TEST_FILENAME")/../../.." && pwd)"
  RESOLVE="$ROOT/scripts/resolve-settings.sh"
  PROJ="$BATS_TEST_TMPDIR/proj"
  TASK="$PROJ/Tasks/ACTIVE/042-a-task"
  mkdir -p "$TASK"
  printf '# CLAUDE-spine-toolkit.md\n\n## Mode\n\nmanual\n' >"$PROJ/CLAUDE-spine-toolkit.md"
  printf '[TASK_TYPE] = [BUG]\n[NEED_TEST] = [true]\n' >"$TASK/Task.md"
  ERR="$BATS_TEST_TMPDIR/err"
}

field() { python3 -c 'import json,sys; print(json.load(sys.stdin)[sys.argv[1]])' "$1"; }
source_of() { python3 -c 'import json,sys; print(json.load(sys.stdin)["sources"][sys.argv[1]])' "$1"; }
map_value() { python3 -c 'import json,sys; print(json.load(sys.stdin)[sys.argv[1]][sys.argv[2]])' "$1" "$2"; }

@test "a project that says nothing resolves every field to its default" {
  run "$RESOLVE" json "$TASK"
  [ "$status" -eq 0 ]
  [ "$(field mode <<<"$output")" = manual ] || { echo "$output"; return 1; }
  [ "$(field scale <<<"$output")" = full ] || { echo "$output"; return 1; }
  [ "$(field walkthrough <<<"$output")" = deep ] || { echo "$output"; return 1; }
  [ "$(field drive_app <<<"$output")" = auto ] || { echo "$output"; return 1; }
  [ "$(field manual_checks <<<"$output")" = auto ] || { echo "$output"; return 1; }
  [ "$(field driver <<<"$output")" = auto ] || { echo "$output"; return 1; }
  [ "$(field phase_verification <<<"$output")" = proportional ] || { echo "$output"; return 1; }
  [ "$(field docs_lever <<<"$output")" = on ] || { echo "$output"; return 1; }
  [ "$(field settings_report <<<"$output")" = diff ] || { echo "$output"; return 1; }
}

@test "the task beats the project, and the source says which won" {
  printf '## Validation\n\ndrive_app: auto\nphase_verification: proportional\n' >>"$PROJ/CLAUDE-spine-toolkit.md"
  printf '[TASK_TYPE] = [BUG]\n[DRIVE_APP] = [off]\n' >"$TASK/Task.md"
  run "$RESOLVE" json "$TASK"
  [ "$(field drive_app <<<"$output")" = off ] || { echo "$output"; return 1; }
  [ "$(source_of drive_app <<<"$output")" = task ] || { echo "$output"; return 1; }
  [ "$(source_of phase_verification <<<"$output")" = project ] || { echo "$output"; return 1; }
}

@test "a lite task writes no walkthrough, and the source names the field that decided" {
  printf '## Reporting\n\nwalkthrough: deep\n' >>"$PROJ/CLAUDE-spine-toolkit.md"
  printf '[TASK_TYPE] = [BUG]\n[SCALE] = [lite]\n' >"$TASK/Task.md"
  run "$RESOLVE" json "$TASK"
  [ "$(field walkthrough <<<"$output")" = off ] || { echo "$output"; return 1; }
  [ "$(source_of walkthrough <<<"$output")" = scale ] || { echo "$output"; return 1; }
}

@test "a lite task that asks for a walkthrough gets one" {
  printf '[TASK_TYPE] = [BUG]\n[SCALE] = [lite]\n[WALKTHROUGH] = [brief]\n' >"$TASK/Task.md"
  run "$RESOLVE" json "$TASK"
  [ "$(field walkthrough <<<"$output")" = brief ] || { echo "$output"; return 1; }
  [ "$(source_of walkthrough <<<"$output")" = task ] || { echo "$output"; return 1; }
}

@test "a step inherits the epic and overrides it key by key" {
  EPIC="$PROJ/Tasks/ACTIVE/050-an-epic"
  STEP="$EPIC/1-first.step"
  mkdir -p "$STEP"
  printf '[TASK_TYPE] = [EPIC]\n[DRIVE_APP] = [off]\n[MANUAL_CHECKS] = [always]\n' >"$EPIC/Task.md"
  printf '[TASK_TYPE] = [FEATURE]\n[MANUAL_CHECKS] = [auto]\n' >"$STEP/Task.md"
  run "$RESOLVE" json "$STEP"
  [ "$(field drive_app <<<"$output")" = off ] || { echo "$output"; return 1; }
  [ "$(source_of drive_app <<<"$output")" = epic ] || { echo "$output"; return 1; }
  [ "$(field manual_checks <<<"$output")" = auto ] || { echo "$output"; return 1; }
  [ "$(source_of manual_checks <<<"$output")" = task ] || { echo "$output"; return 1; }
}

@test "an epic's [WALKTHROUGH] beats the lite gate for a step that names none of its own" {
  printf '## Reporting\n\nwalkthrough: deep\n' >>"$PROJ/CLAUDE-spine-toolkit.md"
  EPIC="$PROJ/Tasks/ACTIVE/054-an-epic"
  STEP="$EPIC/1-first.step"
  mkdir -p "$STEP"
  printf '[TASK_TYPE] = [EPIC]\n[SCALE] = [lite]\n[WALKTHROUGH] = [brief]\n' >"$EPIC/Task.md"
  printf '[TASK_TYPE] = [FEATURE]\n' >"$STEP/Task.md"
  run "$RESOLVE" json "$STEP"
  [ "$(field walkthrough <<<"$output")" = brief ] || { echo "$output"; return 1; }
  [ "$(source_of walkthrough <<<"$output")" = epic ] || { echo "$output"; return 1; }
}

@test "an unusable entry is reported, skipped, and the next source applies" {
  printf '## Validation\n\ndrive_app: off\n' >>"$PROJ/CLAUDE-spine-toolkit.md"
  printf '[TASK_TYPE] = [BUG]\n[DRIVE_APP] = [maybe]\n' >"$TASK/Task.md"
  out="$("$RESOLVE" json "$TASK" 2>"$ERR")"
  [ "$(field drive_app <<<"$out")" = off ] || { echo "$out"; return 1; }
  grep -qF "Task.md [DRIVE_APP]: 'maybe' not recognized, skipped" "$ERR" || { cat "$ERR"; return 1; }
}

@test "on is the pre-depth spelling of deep, and says so in words a typo does not get" {
  printf '[TASK_TYPE] = [BUG]\n[WALKTHROUGH] = [on]\n' >"$TASK/Task.md"
  out="$("$RESOLVE" json "$TASK" 2>"$ERR")"
  [ "$(field walkthrough <<<"$out")" = deep ] || { echo "$out"; return 1; }
  [ "$(source_of walkthrough <<<"$out")" = task ] || { echo "$out"; return 1; }
  grep -qF "Task.md [WALKTHROUGH]: 'on' is the pre-depth spelling, read as 'deep'" "$ERR" \
    || { cat "$ERR"; return 1; }
  ! grep -qF 'not recognized' "$ERR" || { echo "a migration was reported as a typo:"; cat "$ERR"; return 1; }
}

@test "a walkthrough value that is neither a depth nor a pre-depth spelling is reported as unusable" {
  printf '## Reporting\n\nwalkthrough: brief\n' >"$PROJ/CLAUDE-spine-toolkit.md"
  printf '[TASK_TYPE] = [BUG]\n[WALKTHROUGH] = [deeep]\n' >"$TASK/Task.md"
  out="$("$RESOLVE" json "$TASK" 2>"$ERR")"
  grep -qF "Task.md [WALKTHROUGH]: 'deeep' not recognized, skipped" "$ERR" || { cat "$ERR"; return 1; }
  ! grep -qF 'pre-depth' "$ERR" || { echo "a typo was reported as a migration:"; cat "$ERR"; return 1; }
  [ "$(field walkthrough <<<"$out")" = brief ] || { echo "the chain did not continue: $out"; return 1; }
}

@test "on in the project's ## Reporting reads as deep too" {
  printf '## Reporting\n\nwalkthrough: on\n' >"$PROJ/CLAUDE-spine-toolkit.md"
  out="$("$RESOLVE" json "$TASK" 2>"$ERR")"
  [ "$(field walkthrough <<<"$out")" = deep ] || { echo "$out"; return 1; }
  [ "$(source_of walkthrough <<<"$out")" = project ] || { echo "$out"; return 1; }
  grep -qF "## Reporting: 'on' is the pre-depth spelling, read as 'deep'" "$ERR" || { cat "$ERR"; return 1; }
}

@test "a commented-out template line is documentation, not a value" {
  printf '[TASK_TYPE] = [BUG]\n# [DRIVE_APP] = [off]\n' >"$TASK/Task.md"
  run "$RESOLVE" json "$TASK"
  [ "$(field drive_app <<<"$output")" = auto ] || { echo "$output"; return 1; }
  [ "$(source_of drive_app <<<"$output")" = default ] || { echo "$output"; return 1; }
}

@test "show prints the fields that were chosen, in Task.md syntax, and counts the rest" {
  printf '## Mode\n\nauto\n' >"$PROJ/CLAUDE-spine-toolkit.md"
  printf '[TASK_TYPE] = [BUG]\n[SCALE] = [lite]\n' >"$TASK/Task.md"
  run "$RESOLVE" show "$TASK"
  [ "$status" -eq 0 ]
  grep -qE '^\[SCALE\] += \[lite\] +# task$' <<<"$output" || { echo "$output"; return 1; }
  grep -qE '^\[WORKFLOW_MODE\] += \[auto\] +# project$' <<<"$output" || { echo "$output"; return 1; }
  grep -qE '^# [0-9]+ more at their default$' <<<"$output" || { echo "$output"; return 1; }
}

@test "show names a field only when the value chosen differs from the built-in default" {
  # The shipped template writes every field down explicitly, so a column keyed on "somebody
  # chose it" prints sixteen lines in a project that has changed nothing.
  cp "$ROOT/templates/claude-toolkit-md/en.md" "$PROJ/CLAUDE-spine-toolkit.md"
  out="$("$RESOLVE" show "$TASK" 2>"$ERR")"
  [ ! -s "$ERR" ] || { echo "the template's guidance was read as entries:"; cat "$ERR"; return 1; }
  # scale is the one field the template ships away from the built-in default, and walkthrough
  # follows it; everything else the template writes is the default written down.
  grep -qE '^\[SCALE\] += \[lite\] +# project$' <<<"$out" || { echo "$out"; return 1; }
  grep -q '^\[WALKTHROUGH\]' <<<"$out" || { echo "$out"; return 1; }
  for f in WORKFLOW_MODE DOCS DRIVE_APP MANUAL_CHECKS DRIVER PHASE_VERIFICATION LANG MODELS EFFORT; do
    ! grep -q "^\[$f\]" <<<"$out" || { echo "$f is the default written down, and printed: $out"; return 1; }
  done
  [ "$(grep -c '^\[' <<<"$out")" -eq 2 ] || { echo "$out"; return 1; }
  grep -qxF '# 15 more at their default' <<<"$out" || { echo "$out"; return 1; }
}

@test "a project budget equal to the default is not a diff, and --all still names it" {
  printf '## Budgets\n\nPlan.md: 200\n' >"$PROJ/CLAUDE-spine-toolkit.md"
  run "$RESOLVE" show "$TASK"
  ! grep -q '^\[BUDGETS\]' <<<"$output" || { echo "$output"; return 1; }
  run "$RESOLVE" show "$TASK" --all
  grep -qE '^\[BUDGETS\] += \[.*Plan\.md: 200.*\]' <<<"$output" || { echo "$output"; return 1; }
}

@test "show annotates the scale-driven walkthrough with the value that decided and what it displaced" {
  printf '## Reporting\n\nwalkthrough: deep\n\n## Scale\n\nlite\n' >"$PROJ/CLAUDE-spine-toolkit.md"
  run "$RESOLVE" show "$TASK"
  grep -qE '^\[WALKTHROUGH\] += \[off\] +# scale: lite \(project: deep\)$' <<<"$output" \
    || { echo "$output"; return 1; }
}

@test "show annotates a scale-driven walkthrough the project never named with the scale alone" {
  printf '## Scale\n\nlite\n' >"$PROJ/CLAUDE-spine-toolkit.md"
  run "$RESOLVE" show "$TASK"
  grep -qE '^\[WALKTHROUGH\] += \[off\] +# scale: lite$' <<<"$output" || { echo "$output"; return 1; }
}

@test "show --all prints a field left at its default, and plain show does not" {
  run "$RESOLVE" show "$TASK"
  [ "$status" -eq 0 ]
  ! grep -q '\[SCALE\]' <<<"$output" || { echo "$output"; return 1; }
  run "$RESOLVE" show "$TASK" --all
  [ "$status" -eq 0 ]
  grep -qE '^\[SCALE\] += \[full\] +# default$' <<<"$output" || { echo "$output"; return 1; }
  ! grep -q 'more at their default' <<<"$output" || { echo "$output"; return 1; }
}

@test "raw prints a block's value lines and drops its guidance" {
  printf '## Paths\n\n- External packages: Packages/*\n\n(guidance\nover two lines)\n' >"$PROJ/CLAUDE-spine-toolkit.md"
  run "$RESOLVE" raw "$PROJ" Paths
  [ "$status" -eq 0 ]
  [ "$output" = "- External packages: Packages/*" ] || { echo "$output"; return 1; }
}

@test "a usage error exits 2" {
  run "$RESOLVE" json
  [ "$status" -eq 2 ]
  run "$RESOLVE" json "$PROJ/no-such-dir"
  [ "$status" -eq 2 ]
}

@test "settings_report reads full from the Progress block, and progress still reads its own first line" {
  printf '## Progress\n\nlive\nsettings: full\n' >>"$PROJ/CLAUDE-spine-toolkit.md"
  run "$RESOLVE" json "$TASK"
  [ "$(field settings_report <<<"$output")" = full ] || { echo "$output"; return 1; }
  [ "$(source_of settings_report <<<"$output")" = project ] || { echo "$output"; return 1; }
  [ "$(field progress <<<"$output")" = live ] || { echo "$output"; return 1; }
}

@test "two Task.md MODELS lines fold in file order, the last entry for a repeated key wins" {
  printf '[TASK_TYPE] = [BUG]\n[MODELS] = [architect: opus]\n[MODELS] = [tester: haiku, architect: sonnet]\n' >"$TASK/Task.md"
  run "$RESOLVE" json "$TASK"
  [ "$status" -eq 0 ]
  [ "$(map_value models architect <<<"$output")" = sonnet ] || { echo "$output"; return 1; }
  [ "$(map_value models tester <<<"$output")" = haiku ] || { echo "$output"; return 1; }
}

@test "a task's model key beats the project's, and a key the task does not name keeps the project's value" {
  printf '## Models\n\narchitect: opus\nreviewer: opus\n' >"$PROJ/CLAUDE-spine-toolkit.md"
  printf '[TASK_TYPE] = [BUG]\n[MODELS] = [architect: sonnet]\n' >"$TASK/Task.md"
  run "$RESOLVE" json "$TASK"
  [ "$(map_value models architect <<<"$output")" = sonnet ] || { echo "$output"; return 1; }
  [ "$(map_value models reviewer <<<"$output")" = opus ] || { echo "$output"; return 1; }
}

@test "a task's platform model entry is skipped silently, leaving the project's value in place" {
  printf '## Models\n\narchitect: opus\n' >"$PROJ/CLAUDE-spine-toolkit.md"
  printf '[TASK_TYPE] = [BUG]\n[MODELS] = [architect: platform]\n' >"$TASK/Task.md"
  out="$("$RESOLVE" json "$TASK" 2>"$ERR")"
  [ ! -s "$ERR" ] || { cat "$ERR"; return 1; }
  [ "$(map_value models architect <<<"$out")" = opus ] || { echo "$out"; return 1; }
}

@test "a step's [MODELS] falls back to the epic's Task.md" {
  EPIC="$PROJ/Tasks/ACTIVE/050-an-epic"
  STEP="$EPIC/1-first.step"
  mkdir -p "$STEP"
  printf '[TASK_TYPE] = [EPIC]\n[MODELS] = [architect: opus]\n' >"$EPIC/Task.md"
  printf '[TASK_TYPE] = [FEATURE]\n' >"$STEP/Task.md"
  run "$RESOLVE" json "$STEP"
  [ "$(map_value models architect <<<"$output")" = opus ] || { echo "$output"; return 1; }
  [ "$(source_of models <<<"$output")" = epic ] || { echo "$output"; return 1; }
}

@test "a step's [MODELS] key overrides the epic's, and a key the step does not name still reaches it" {
  EPIC="$PROJ/Tasks/ACTIVE/053-an-epic"
  STEP="$EPIC/1-first.step"
  mkdir -p "$STEP"
  printf '[TASK_TYPE] = [EPIC]\n[MODELS] = [architect: opus, reviewer: haiku]\n' >"$EPIC/Task.md"
  printf '[TASK_TYPE] = [FEATURE]\n[MODELS] = [architect: sonnet]\n' >"$STEP/Task.md"
  run "$RESOLVE" json "$STEP"
  [ "$(map_value models architect <<<"$output")" = sonnet ] || { echo "the step's own key lost: $output"; return 1; }
  [ "$(map_value models reviewer <<<"$output")" = haiku ] || { echo "the epic's key did not reach the step: $output"; return 1; }
  [ "$(source_of models <<<"$output")" = task ] || { echo "$output"; return 1; }
}

@test "a project that says nothing resolves models and effort to their defaults, light and validator at sonnet" {
  run "$RESOLVE" json "$TASK"
  [ "$status" -eq 0 ]
  [ "$(map_value models light <<<"$output")" = sonnet ] || { echo "$output"; return 1; }
  [ "$(map_value models validator <<<"$output")" = sonnet ] || { echo "$output"; return 1; }
  [ "$(map_value models architect <<<"$output")" = session ] || { echo "$output"; return 1; }
  [ "$(map_value effort architect <<<"$output")" = session ] || { echo "$output"; return 1; }
  [ "$(map_value effort validator <<<"$output")" = session ] || { echo "$output"; return 1; }
  [ "$(source_of models <<<"$output")" = default ] || { echo "$output"; return 1; }
  [ "$(source_of effort <<<"$output")" = default ] || { echo "$output"; return 1; }
}

@test "light: platform reads as absent, so light keeps its sonnet default" {
  printf '## Models\n\nlight: platform\n' >"$PROJ/CLAUDE-spine-toolkit.md"
  out="$("$RESOLVE" json "$TASK" 2>"$ERR")"
  [ ! -s "$ERR" ] || { cat "$ERR"; return 1; }
  [ "$(map_value models light <<<"$out")" = sonnet ] || { echo "$out"; return 1; }
}

@test "a config written by 1.11.0 keeps every model it had and reports nothing" {
  printf '## Models\n\nlight: sonnet\n' >"$PROJ/CLAUDE-spine-toolkit.md"
  for role in architect developer tester reviewer refactorer validator security diagnostics; do
    printf '%s: platform\n' "$role" >>"$PROJ/CLAUDE-spine-toolkit.md"
  done
  out="$("$RESOLVE" json "$TASK" 2>"$ERR")"
  [ ! -s "$ERR" ] || { echo "platform was reported:"; cat "$ERR"; return 1; }
  [ "$(map_value models light <<<"$out")" = sonnet ] || { echo "$out"; return 1; }
  [ "$(map_value models validator <<<"$out")" = sonnet ] || { echo "$out"; return 1; }
  for role in architect developer tester reviewer refactorer security diagnostics; do
    [ "$(map_value models "$role" <<<"$out")" = session ] || { echo "$role: $out"; return 1; }
  done
}

@test "keys and values are read case-insensitively" {
  printf '[TASK_TYPE] = [BUG]\n[MODELS] = [Architect: Opus]\n' >"$TASK/Task.md"
  run "$RESOLVE" json "$TASK"
  [ "$(map_value models architect <<<"$output")" = opus ] || { echo "$output"; return 1; }
}

@test "a folder that is not a step never reads the Task.md above it" {
  printf '[TASK_TYPE] = [EPIC]\n[MODELS] = [architect: opus]\n' >"$PROJ/Tasks/ACTIVE/Task.md"
  run "$RESOLVE" json "$TASK"
  [ "$(map_value models architect <<<"$output")" = session ] || { echo "$output"; return 1; }
}

@test "light is a model key and not an effort key" {
  printf '## Effort\n\nlight: low\n' >"$PROJ/CLAUDE-spine-toolkit.md"
  "$RESOLVE" json "$TASK" 2>"$ERR" >/dev/null
  grep -qF "## Effort: 'light: low' not recognized, skipped" "$ERR" || { cat "$ERR"; return 1; }
}

@test "two Task.md EFFORT lines fold in file order, the last entry for a repeated key wins" {
  printf '[TASK_TYPE] = [BUG]\n[EFFORT] = [reviewer: low, developer: medium]\n[EFFORT] = [reviewer: high]\n' >"$TASK/Task.md"
  run "$RESOLVE" json "$TASK"
  [ "$(map_value effort reviewer <<<"$output")" = high ] || { echo "$output"; return 1; }
  [ "$(map_value effort developer <<<"$output")" = medium ] || { echo "the first line's other key was lost: $output"; return 1; }
}

@test "a step's [EFFORT] key overrides the epic's, and a key the step does not name still reaches it" {
  printf '## Effort\n\nreviewer: max\n' >"$PROJ/CLAUDE-spine-toolkit.md"
  EPIC="$PROJ/Tasks/ACTIVE/051-an-epic"
  STEP="$EPIC/1-first.step"
  mkdir -p "$STEP"
  printf '[TASK_TYPE] = [EPIC]\n[EFFORT] = [reviewer: high, tester: low]\n' >"$EPIC/Task.md"
  printf '[TASK_TYPE] = [FEATURE]\n[EFFORT] = [tester: medium]\n' >"$STEP/Task.md"
  run "$RESOLVE" json "$STEP"
  [ "$(map_value effort tester <<<"$output")" = medium ] || { echo "the step's own key lost: $output"; return 1; }
  [ "$(map_value effort reviewer <<<"$output")" = high ] || { echo "the epic's key did not reach the step: $output"; return 1; }
}

@test "platform is still reported under an unknown ## Models key, and in ## Effort" {
  printf '## Models\n\nplanner: platform\n\n## Effort\n\nreviewer: platform\n' >"$PROJ/CLAUDE-spine-toolkit.md"
  "$RESOLVE" json "$TASK" 2>"$ERR" >/dev/null
  grep -qF "## Models: 'planner: platform' not recognized, skipped" "$ERR" || { cat "$ERR"; return 1; }
  grep -qF "## Effort: 'reviewer: platform' not recognized, skipped" "$ERR" || { cat "$ERR"; return 1; }
}

@test "a platform entry in the epic's Task.md reads as absent for its step" {
  printf '## Models\n\narchitect: opus\n' >"$PROJ/CLAUDE-spine-toolkit.md"
  EPIC="$PROJ/Tasks/ACTIVE/052-an-epic"
  STEP="$EPIC/1-first.step"
  mkdir -p "$STEP"
  printf '[TASK_TYPE] = [EPIC]\n[MODELS] = [architect: platform]\n' >"$EPIC/Task.md"
  printf '[TASK_TYPE] = [FEATURE]\n' >"$STEP/Task.md"
  out="$("$RESOLVE" json "$STEP" 2>"$ERR")"
  [ ! -s "$ERR" ] || { cat "$ERR"; return 1; }
  [ "$(map_value models architect <<<"$out")" = opus ] || { echo "$out"; return 1; }
}

@test "init is not a key, because no profile dispatches it" {
  printf '## Models\n\ninit: opus\n' >"$PROJ/CLAUDE-spine-toolkit.md"
  "$RESOLVE" json "$TASK" 2>"$ERR" >/dev/null
  grep -qF "## Models: 'init: opus' not recognized, skipped" "$ERR" || { cat "$ERR"; return 1; }
}

@test "a task can name session over the project's model" {
  printf '## Models\n\nvalidator: opus\n' >"$PROJ/CLAUDE-spine-toolkit.md"
  printf '[TASK_TYPE] = [BUG]\n[MODELS] = [validator: session]\n' >"$TASK/Task.md"
  out="$("$RESOLVE" json "$TASK" 2>"$ERR")"
  [ ! -s "$ERR" ] || { cat "$ERR"; return 1; }
  [ "$(map_value models validator <<<"$out")" = session ] || { echo "$out"; return 1; }
}

@test "the config's last entry for a repeated key wins, not the first" {
  cp "$ROOT/templates/claude-toolkit-md/en.md" "$PROJ/CLAUDE-spine-toolkit.md"
  awk '{print} /^architect: session$/ && !done {print "architect: opus"; done=1}' \
    "$PROJ/CLAUDE-spine-toolkit.md" >"$PROJ/CLAUDE-spine-toolkit.md.new"
  mv "$PROJ/CLAUDE-spine-toolkit.md.new" "$PROJ/CLAUDE-spine-toolkit.md"
  out="$("$RESOLVE" json "$TASK" 2>"$ERR")"
  [ ! -s "$ERR" ] || { echo "unexpected stderr:"; cat "$ERR"; return 1; }
  [ "$(map_value models architect <<<"$out")" = opus ] || { echo "$out"; return 1; }
}

@test "the shipped config template resolves to the defaults and reports nothing" {
  # The template is what a new project starts from, and its guidance paragraphs sit inside the
  # very blocks the resolver reads. `scale` is the one deliberate exception: the template writes
  # `lite` where an absent block resolves to `full`, and `walkthrough` follows it down.
  cp "$ROOT/templates/claude-toolkit-md/en.md" "$PROJ/CLAUDE-spine-toolkit.md"
  out="$("$RESOLVE" json "$TASK" 2>"$ERR")"
  [ ! -s "$ERR" ] || { echo "the template's guidance was read as entries:"; cat "$ERR"; return 1; }
  while read -r name want; do
    [ "$(field "$name" <<<"$out")" = "$want" ] || { echo "$name: $out"; return 1; }
  done <<'FIELDS'
lang en
mode manual
progress normal
settings_report diff
scale lite
walkthrough off
drive_app auto
manual_checks auto
driver auto
phase_verification proportional
docs_lever on
docs_map DocsMap.md
docs_strictness advisory
docs_freshness on
FIELDS
  [ "$(source_of budgets <<<"$out")" = default ] || { echo "the empty ## Budgets block was read: $out"; return 1; }
  [ "$(map_value budgets Plan.md <<<"$out")" = 200 ] || { echo "$out"; return 1; }
  [ "$(map_value models light <<<"$out")" = sonnet ] || { echo "$out"; return 1; }
  [ "$(map_value models validator <<<"$out")" = sonnet ] || { echo "$out"; return 1; }
  for role in architect developer tester reviewer refactorer security diagnostics; do
    [ "$(map_value models "$role" <<<"$out")" = session ] || { echo "$role: $out"; return 1; }
    [ "$(map_value effort "$role" <<<"$out")" = session ] || { echo "$role: $out"; return 1; }
  done
  [ "$(map_value effort validator <<<"$out")" = session ] || { echo "$out"; return 1; }
}

@test "a budgets override is recorded with its own source, and show prints it" {
  printf '## Budgets\n\nPlan.md: 150\n' >"$PROJ/CLAUDE-spine-toolkit.md"
  run "$RESOLVE" json "$TASK"
  [ "$status" -eq 0 ]
  [ "$(map_value budgets Plan.md <<<"$output")" = 150 ] || { echo "$output"; return 1; }
  [ "$(source_of budgets <<<"$output")" = project ] || { echo "$output"; return 1; }
  [ "$(source_of budgets.Plan.md <<<"$output")" = project ] || { echo "$output"; return 1; }
  run "$RESOLVE" show "$TASK"
  grep -qE '^\[BUDGETS\] += \[Plan\.md: 150\] +# project$' <<<"$output" || { echo "$output"; return 1; }
}

@test "a budgets override equal to the default is still the project's choice, not the default's" {
  printf '## Budgets\n\nPlan.md: 200\n' >"$PROJ/CLAUDE-spine-toolkit.md"
  run "$RESOLVE" json "$TASK"
  [ "$(map_value budgets Plan.md <<<"$output")" = 200 ] || { echo "$output"; return 1; }
  [ "$(source_of budgets <<<"$output")" = project ] || { echo "$output"; return 1; }
  [ "$(source_of budgets.Plan.md <<<"$output")" = project ] || { echo "$output"; return 1; }
}

@test "no script but the resolver parses the config file" {
  n=0
  for f in "$ROOT"/scripts/*.sh; do
    case "$(basename "$f")" in resolve-settings.sh) continue ;; esac
    n=$((n + 1))
    ! grep -q "CLAUDE-spine-toolkit.md'" "$f" || { echo "$(basename "$f") parses the config itself"; return 1; }
  done
  [ "$n" -ge 10 ] || { echo "scanned $n script(s), expected at least 10"; return 1; }
}

@test "no profile script tells an agent where to look a setting up" {
  n=0
  for p in "$ROOT"/workflows/profile-*.js; do
    n=$((n + 1))
    for token in '[DRIVE_APP]' '[MANUAL_CHECKS]' '[PHASE_VERIFICATION]' '## Validation'; do
      ! grep -qF "$token" "$p" || { echo "$(basename "$p") still spells the chain for $token"; return 1; }
    done
  done
  [ "$n" -eq 7 ] || { echo "scanned $n script(s), expected 7"; return 1; }
}

@test "the epic forwards every field a step can override" {
  # driver stays off this list: it never rides the Outbound Contract
  # (tests/foundation/lib/orchestrator-contract.test.bats — "the driver does not travel").
  # The fallback is the prelude's guarded local (DRIVE_APP, …), not A.<field> directly — an
  # absent contract field must not push a bare `undefined` into the pushed step's args.
  for field in drive_app manual_checks phase_verification; do
    guarded="$(tr '[:lower:]' '[:upper:]' <<<"$field")"
    grep -qF "$field: st.$field === undefined ? $guarded : st.$field" "$ROOT/workflows/profile-epic.js" \
      || { echo "profile-epic.js does not forward $field to a step"; return 1; }
  done
}

@test "drive_app, manual_checks and phase_verification default like every other guarded local" {
  for p in "$ROOT"/workflows/profile-*.js; do
    grep -qxF "const DRIVE_APP = A.drive_app === 'off' ? 'off' : 'auto'" "$p" \
      || { echo "$(basename "$p"): drive_app is not guarded"; return 1; }
    grep -qxF "const MANUAL_CHECKS = A.manual_checks === 'always' ? 'always' : 'auto'" "$p" \
      || { echo "$(basename "$p"): manual_checks is not guarded"; return 1; }
    grep -qxF "const PHASE_VERIFICATION = A.phase_verification === 'full' ? 'full' : 'proportional'" "$p" \
      || { echo "$(basename "$p"): phase_verification is not guarded"; return 1; }
  done
}
