#!/usr/bin/env bats
bats_require_minimum_version 1.5.0
# The project config is core's format: `setup` writes it, the orchestrator and
# stack-detect read it. A block missing from the template is a block no project
# ever has, so every consumer of it silently takes its absent branch — which is
# how `## Platform` spent three tasks being read from a file nothing wrote it to.
#
# The last two close the reference classes a prose grep cannot see. A bare
# relative path resolves under the naming plugin's own root, so a path belonging
# to the other plugin simply finds nothing and carries no prefix to grep for. And
# a path written from the monorepo root reaches the sibling tree without ever
# spelling a trailing slash, which is how two bats files kept core's suite bound
# to platform/ for twelve tasks.

setup() {
  ROOT="$(cd -- "$(dirname -- "$BATS_TEST_FILENAME")/../../.." && pwd)"
  TPL="$ROOT/templates/spine-md/en.md"
}

# The three scans below ask what files core HAS, and that is the index plus
# whatever is untracked and not ignored — never a tree walk, which also reads
# ignored scratch (a build directory, an agent's workspace) and reddens these
# checks over a file that was never core's. Paths come back repo-relative.
# Exit 1 is "no match"; anything above it is git failing, and a failed scan must
# not read as a clean one.
core_grep() {
  local rc=0
  git -C "$ROOT" grep --untracked --full-name "$@" || rc=$?
  [ "$rc" -le 1 ] || { echo "git grep exited $rc — the scan did not run" >&2; return 1; }
}

@test "the config template declares every block and every field the toolkit reads" {
  for block in Platform Agents Stack Modules EstimationDeltas; do
    grep -q "^## $block\$" "$TPL" || { echo "missing block: ## $block"; return 1; }
  done
  for f in LANG PROGRESS SETTINGS_REPORT BUDGETS DOCS_MAP DOCS_STRICTNESS DOCS_FRESHNESS \
           WORKFLOW_MODE SCALE DRIVE_APP MANUAL_CHECKS MANUAL_CHECKS_CHECK DRIVER PHASE_VERIFICATION WALKTHROUGH \
           WALKTHROUGH_CHECK SECURITY DOCS MODELS EFFORT LONG_RUN FIX_ROUNDS DEVICE DEVICE_SOURCE; do
    grep -q "^\[$f\] = \[" "$TPL" || { echo "missing field: [$f]"; return 1; }
  done
}

catalog_words() {
  grep -icE '\b(swift|swiftui|uikit|appkit|combine|rxswift|swinject|xct[a-z]*|ios|macos|viper|mvvm)\b' "$1"
}

@test "the config template names no platform's stack values" {
  [ "$(catalog_words "$TPL")" = "0" ]
}

@test "the orchestrator names no platform's stack values" {
  [ "$(catalog_words "$ROOT/skills/orchestrator/SKILL.md")" = "0" ]
}

@test "only the setup surface still names the pre-split config" {
  # `setup` migrates a project written by the pre-split toolkit, so it must name
  # the old file. Nothing else may: elsewhere the name is rot, and a consumer
  # reading it looks at a file no current install has.
  hits="$(core_grep -l 'CLAUDE-swift-toolkit')"
  offenders="$(grep -vE '^(skills/setup/|commands/setup\.md|tests/foundation/lib/project-config\.test\.bats)' <<<"$hits" || true)"
  [ -z "$offenders" ] || {
    echo "unexpected reference(s) to the pre-split config name:"; echo "$offenders"; return 1
  }
  # The exception covers five files today; a sixth means it has drifted and must
  # be re-read, not widened.
  n="$(printf '%s\n' "$hits" | grep -c . || true)"
  [ "$n" -eq 5 ] || { echo "the pre-split name appears in $n file(s), expected 5"; return 1; }
}

@test "every bare relative path core names resolves under its own plugin root" {
  # tests/fixtures/ holds whole foreign plugins, and the contract sends strangers
  # there to copy one — so their paths are in scope, resolved against themselves.
  # Excluding them is how three monorepo-era paths shipped inside the copy target.
  missing=""
  scan="$(core_grep -oE '`[A-Za-z_][A-Za-z0-9_.-]*/[^` ]*`' \
            -- '*.md' '*.sh' '*.js' '*.bats' '*.zsh')"
  while IFS= read -r hit; do
    [ -n "$hit" ] || continue
    f="${hit%%:*}"
    p="$(printf '%s' "${hit#*:}" | tr -d '`')"
    case "$p" in
      skills/*|agents/*|commands/*|conventions/*|templates/*|hooks/*|scripts/*|tests/*|workflows/*) ;;
      # A monorepo-root prefix is a path this plugin does not have: it resolves
      # nowhere once core is a repo of its own, and nowhere here either.
      core/*) ;;
      *) continue ;;
    esac
    base="$ROOT"
    case "$f" in
      tests/fixtures/*)
        rel="${f#tests/fixtures/}"
        base="$ROOT/tests/fixtures/${rel%%/*}" ;;
    esac
    # bash 3.2's `compgen -G` succeeds on any pattern ending in `/`, existing or not,
    # so the trailing slash has to go before the glob is what decides.
    q="$(printf '%s' "$p" | sed 's/<[^>]*>/*/g')"
    compgen -G "$base/${q%/}" >/dev/null \
      || missing="$missing $f:$p"
  done < <(printf '%s\n' "$scan" | sort -u)
  [ -z "$missing" ] || { echo "path(s) that do not resolve under their plugin root:$missing"; return 1; }
}

@test "no file in core names the platform tree by a filesystem path" {
  # `$ROOT/../platform` has no trailing slash, so the prescribed `platform/` grep
  # walks straight past it — which is how two of these survived twelve reviews.
  # `git filter-repo --path core` turns every one of them into a dangling path
  # with no sibling tree left to restore.
  # Both namings are now wrong for core to write: the pre-split directory, and
  # the published repo name that the first pattern's `[^A-Za-z0-9_.-]` class
  # swallows. Core's own repo name is a monorepo-root prefix and equally wrong;
  # the installed-plugin cache paths `setup` and `task-new` document are the one
  # legitimate use, excluded by that prefix rather than by sparing a leading dot
  # or slash — which spared every absolute and dot-relative sibling path too.
  pat='(\.\./(platform|swift-platform|spine-platform-swift|spine-platform-kotlin|spine-toolkit)([^A-Za-z0-9_-]|$)'
  pat="$pat"'|(^|[^A-Za-z0-9_.-])platform/'
  pat="$pat"'|(^|[^A-Za-z0-9_-])(swift-platform|spine-platform-swift|spine-platform-kotlin|spine-toolkit)/)'
  raw="$(core_grep -nE "$pat")"
  hits="$(grep -vE '(^|/)\.claude/plugins/(cache|marketplaces)/' <<<"$raw" || true)"
  offenders="$(grep -vF 'project-config.test.bats' <<<"$hits" || true)"
  [ -z "$offenders" ] || { echo "core reference(s) to the platform tree:"; echo "$offenders"; return 1; }
  # The self-exclusion above is otherwise unbounded — a violation added to this
  # file would be invisible. Pin the count: a change here must be re-read.
  n="$(grep -cF 'project-config.test.bats' <<<"$hits" || true)"
  [ "$n" -eq 3 ] || { echo "self-excluded lines in this file: $n, expected 3"; return 1; }
}

@test "the config template declares the driver field" {
  # A field the template does not carry is a field no project ever has, and every
  # reader of it silently takes the absent branch.
  grep -q '^\[DRIVER\] = \[' "$TPL" || { echo "no [DRIVER] field in the template"; return 1; }
}

@test "the config template ships auto and names no concrete driver plugin" {
  # `auto` is the shipped value, and it has to be: an explicit `—` means none, so a
  # template shipping it would opt every new project out of driving. A real plugin
  # name here would be core knowing an ecosystem.
  grep -qE '^\[DRIVER\] = \[(auto|<[a-z-]+>)\]' "$TPL" \
    || { echo "[DRIVER] must ship 'auto' or a placeholder"; return 1; }
}

@test "both task templates offer the DRIVER override" {
  # Both, not one: a field in the root template and not the step template is a
  # field an epic's steps silently cannot use, which surfaces only as a step that
  # drove the app when its parent said not to.
  for t in task-root task-step; do
    f="$ROOT/templates/task-md/$t.md"
    grep -q '\[DRIVER\]' "$f" || { echo "no [DRIVER] in $t.md"; return 1; }
    grep -q '\[DRIVE_APP\]' "$f" || { echo "no [DRIVE_APP] in $t.md — the anchor moved"; return 1; }
  done
}

@test "both task templates offer the DEVICE override, and neither the DEVICE_SOURCE one" {
  for t in task-root task-step; do
    f="$ROOT/templates/task-md/$t.md"
    grep -q '^# \[DEVICE\] = \[' "$f" || { echo "no [DEVICE] in $t.md"; return 1; }
    ! grep -q 'DEVICE_SOURCE' "$f" || { echo "$t.md offers a field no task can set"; return 1; }
  done
}

@test "the config template declares the phase_verification field" {
  grep -q '^\[PHASE_VERIFICATION\] = \[' "$TPL" \
    || { echo "no [PHASE_VERIFICATION] field in the template"; return 1; }
}

@test "the config template ships proportional and names no third value" {
  # The trailing comment is the whole value list a project sees here, so an `off`
  # absent from it is an `off` nobody goes looking for.
  grep -qE '^\[PHASE_VERIFICATION\] = \[proportional\] +# proportional \| full$' "$TPL" \
    || { echo "[PHASE_VERIFICATION] must ship proportional and name proportional | full"; return 1; }
}

@test "both task templates offer the PHASE_VERIFICATION override" {
  for t in task-root task-step; do
    grep -qF '# [PHASE_VERIFICATION] = [full] # proportional | full' "$ROOT/templates/task-md/$t.md" \
      || { echo "no [PHASE_VERIFICATION] in $t.md"; return 1; }
  done
}

@test "the Budgets field ships empty" {
  grep -qE '^\[BUDGETS\] = \[\]' "$TPL" \
    || { echo "the template ships a ceiling a project did not choose"; return 1; }
}

@test "the config template offers the settings_report field" {
  grep -qE '^\[SETTINGS_REPORT\] = \[diff\] +# diff \| full \| off$' "$TPL" \
    || { echo "[SETTINGS_REPORT] must ship diff and name diff | full | off"; return 1; }
}

@test "the SCALE asymmetry holds: the template ships lite, an absent field resolves full" {
  # The one field whose shipped line and its absent-field default differ on purpose, asserted in
  # four places and held equal in none — so a "fix" to either half names the other two,
  # skills/setup/SKILL.md's migration note and docs/configuration.md, instead of passing silently.
  ships="$(sed -n 's/^\[SCALE\] = \[\([a-z]*\)\].*/\1/p' "$TPL")"
  resolves="$(sed -n "s/^ *('scale', 'SCALE', \[[^]]*\], '\([a-z]*\)').*/\1/p" "$ROOT/scripts/resolve-settings.sh")"
  [ "$ships" = lite ] || { echo "the template ships [SCALE] = [$ships], expected lite"; return 1; }
  [ "$resolves" = full ] || { echo "the resolver's scale default is '$resolves', expected full"; return 1; }
}

@test "the config template ships security at auto and names its three values" {
  grep -qxF '[SECURITY] = [auto]                    # auto | on | off' "$TPL" \
    || { echo "[SECURITY] must ship auto and name auto | on | off"; return 1; }
}

@test "both task templates offer the SECURITY override" {
  for t in task-root task-step; do
    grep -qxF '# [SECURITY] = [on]           # auto | on | off' "$ROOT/templates/task-md/$t.md" \
      || { echo "no [SECURITY] in $t.md"; return 1; }
  done
}

@test "the config template ships long_run at its defaults" {
  grep -qE '^\[LONG_RUN\] = \[stall: 5, max: 30\] +# minutes: stall \| max$' "$TPL" \
    || { echo "[LONG_RUN] must ship stall: 5, max: 30"; return 1; }
}

@test "both task templates offer the LONG_RUN override" {
  for t in task-root task-step; do
    grep -qF '# [LONG_RUN] = [max: 60]' "$ROOT/templates/task-md/$t.md" \
      || { echo "no [LONG_RUN] in $t.md"; return 1; }
  done
}

@test "the fix_rounds field ships at 2 in the config and as an override in both task templates" {
  grep -qE '^\[FIX_ROUNDS\] = \[2\] +# a whole number, 0 turns the auto loop off$' "$TPL" \
    || { echo "[FIX_ROUNDS] must ship 2 with its comment"; return 1; }
  for t in task-root task-step; do
    grep -qF '# [FIX_ROUNDS] = [0]         # a whole number, 0 turns the auto loop off' "$ROOT/templates/task-md/$t.md" \
      || { echo "no [FIX_ROUNDS] in $t.md"; return 1; }
  done
}

# --- Project config lookup: SPINE.md, or the legacy name where a project has not migrated ---

# A task folder under <root>, with a Task.md from the template; prints the task dir.
mk_task() {
  local t="$1/Tasks/ACTIVE/001-x"
  mkdir -p "$t"
  cp "$ROOT/templates/task-md/task-root.md" "$t/Task.md"
  printf '%s' "$t"
}

@test "SPINE.md alone is the project config" {
  p="$BATS_TEST_TMPDIR/p"; t="$(mk_task "$p")"
  printf '[LANG] = [ru]\n' > "$p/SPINE.md"
  run "$ROOT/scripts/resolve-settings.sh" json "$t"
  [ "$status" -eq 0 ]
  grep -q '"lang": "ru"' <<<"$output"
  grep -q "\"project_config\": \"$p/SPINE.md\"" <<<"$output"
}

@test "the legacy name alone is still read" {
  p="$BATS_TEST_TMPDIR/p"; t="$(mk_task "$p")"
  printf '[LANG] = [ru]\n' > "$p/CLAUDE-spine-toolkit.md"
  run "$ROOT/scripts/resolve-settings.sh" json "$t"
  [ "$status" -eq 0 ]
  grep -q '"lang": "ru"' <<<"$output"
  grep -q "\"project_config\": \"$p/CLAUDE-spine-toolkit.md\"" <<<"$output"
}

@test "both present: SPINE.md wins and stderr names the ignored file" {
  p="$BATS_TEST_TMPDIR/p"; t="$(mk_task "$p")"
  printf '[LANG] = [ru]\n' > "$p/SPINE.md"
  printf '[LANG] = [en]\n' > "$p/CLAUDE-spine-toolkit.md"
  run --separate-stderr "$ROOT/scripts/resolve-settings.sh" json "$t"
  [ "$status" -eq 0 ]
  grep -q '"lang": "ru"' <<<"$output"
  [ "$stderr" = "project config: $p/SPINE.md selected, $p/CLAUDE-spine-toolkit.md ignored" ]
}

@test "a nearer legacy file beats a farther SPINE.md" {
  p="$BATS_TEST_TMPDIR/p"; t="$(mk_task "$p")"
  printf '[LANG] = [ru]\n' > "$p/SPINE.md"
  printf '[LANG] = [en]\n' > "$p/Tasks/CLAUDE-spine-toolkit.md"
  run "$ROOT/scripts/resolve-settings.sh" json "$t"
  [ "$status" -eq 0 ]
  grep -q '"lang": "en"' <<<"$output"
  grep -q "\"project_config\": \"$p/Tasks/CLAUDE-spine-toolkit.md\"" <<<"$output"
}

@test "no config at all: project_config is null" {
  p="$BATS_TEST_TMPDIR/p"; t="$(mk_task "$p")"
  run "$ROOT/scripts/resolve-settings.sh" json "$t"
  [ "$status" -eq 0 ]
  grep -q '"project_config": null' <<<"$output"
}

@test "raw reads the file json selected" {
  p="$BATS_TEST_TMPDIR/p"; t="$(mk_task "$p")"
  printf '## Platform\n\nfixture-platform\n' > "$p/SPINE.md"
  printf '## Platform\n\nother-platform\n' > "$p/CLAUDE-spine-toolkit.md"
  run --separate-stderr "$ROOT/scripts/resolve-settings.sh" raw "$t" Platform
  [ "$status" -eq 0 ]
  [ "$output" = "fixture-platform" ]
}

@test "SPINE.md in the 1.x block format is refused like the legacy name" {
  p="$BATS_TEST_TMPDIR/p"; t="$(mk_task "$p")"
  printf '## Language\n\nen\n' > "$p/SPINE.md"
  run --separate-stderr "$ROOT/scripts/resolve-settings.sh" json "$t"
  [ "$status" -eq 2 ]
  grep -q "SPINE.md: the ## Language format is 2.0-incompatible" <<<"$stderr"
}

@test "the template's first line names SPINE.md and the config templates never name the legacy file" {
  [ "$(head -1 "$TPL")" = "# SPINE.md — Spine Configuration" ]
  ! grep -q 'CLAUDE-spine-toolkit' "$TPL"
  grep -q '^@./SPINE.md$' "$ROOT/templates/claude-md-stub/en.md"
  grep -q '^@./SPINE.md$' "$ROOT/templates/claude-md-stub/ru.md"
  ! grep -rq 'CLAUDE-spine-toolkit' "$ROOT/templates/claude-md-stub"
}
