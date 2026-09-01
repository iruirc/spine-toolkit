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

@test "the config template declares every block the toolkit reads" {
  for block in Language Platform Agents Stack Mode Progress Modules EstimationDeltas; do
    grep -q "^## $block\$" "$TPL" || { echo "missing block: ## $block"; return 1; }
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
  hits="$(grep -rl --exclude-dir=.git 'CLAUDE-swift-toolkit' "$ROOT" || true)"
  offenders="$(grep -vE "/(skills/setup/|commands/setup\.md|tests/foundation/lib/project-config\.test\.bats)" <<<"$hits" || true)"
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
      "$ROOT"/tests/fixtures/*)
        rel="${f#"$ROOT"/tests/fixtures/}"
        base="$ROOT/tests/fixtures/${rel%%/*}" ;;
    esac
    # bash 3.2's `compgen -G` succeeds on any pattern ending in `/`, existing or not,
    # so the trailing slash has to go before the glob is what decides.
    q="$(printf '%s' "$p" | sed 's/<[^>]*>/*/g')"
    compgen -G "$base/${q%/}" >/dev/null \
      || missing="$missing ${f#"$ROOT"/}:$p"
  done < <(grep -roE '`[A-Za-z_][A-Za-z0-9_.-]*/[^` ]*`' "$ROOT" \
             --include='*.md' --include='*.sh' --include='*.js' \
             --include='*.bats' --include='*.zsh' \
             --exclude-dir=.git | sort -u)
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
  pat='(\.\./(platform|swift-platform|spine-toolkit)([^A-Za-z0-9_-]|$)'
  pat="$pat"'|(^|[^A-Za-z0-9_.-])platform/'
  pat="$pat"'|(^|[^A-Za-z0-9_-])(swift-platform|spine-toolkit)/)'
  hits="$(grep -rnE --exclude-dir=.git "$pat" "$ROOT" \
            | grep -vE '/\.claude/plugins/(cache|marketplaces)/' || true)"
  offenders="$(grep -vF 'project-config.test.bats' <<<"$hits" || true)"
  [ -z "$offenders" ] || { echo "core reference(s) to the platform tree:"; echo "$offenders"; return 1; }
  # The self-exclusion above is otherwise unbounded — a violation added to this
  # file would be invisible. Pin the count: a change here must be re-read.
  n="$(grep -cF 'project-config.test.bats' <<<"$hits" || true)"
  [ "$n" -eq 3 ] || { echo "self-excluded lines in this file: $n, expected 3"; return 1; }
}
