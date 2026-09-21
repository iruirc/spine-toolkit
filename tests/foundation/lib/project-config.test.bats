#!/usr/bin/env bats
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
  TPL="$ROOT/templates/claude-toolkit-md/en.md"
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
           WORKFLOW_MODE SCALE DRIVE_APP MANUAL_CHECKS DRIVER PHASE_VERIFICATION WALKTHROUGH \
           WALKTHROUGH_CHECK DOCS MODELS EFFORT; do
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
