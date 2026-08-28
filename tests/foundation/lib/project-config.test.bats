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

# `swift-lang` is a core skill's own name, not a catalog value; it loses the
# `swift-` prefix in a later rename and is filtered out until then.
catalog_words() {
  grep -vF 'swift-lang' "$1" \
    | grep -icE '\b(swift|swiftui|uikit|appkit|combine|rxswift|swinject|xctest|ios|macos|viper|mvvm)\b'
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
  offenders="$(grep -rl 'CLAUDE-swift-toolkit' "$ROOT" \
    | grep -vE "/(skills/setup/|commands/setup\.md|tests/foundation/lib/project-config\.test\.bats)" || true)"
  [ -z "$offenders" ] || {
    echo "unexpected reference(s) to the pre-split config name:"; echo "$offenders"; return 1
  }
}

@test "every bare relative path core names resolves under core" {
  # tests/fixtures/ holds a whole foreign plugin: its paths resolve against
  # itself, not against this root.
  missing=""
  for p in $(grep -rhoE '`[A-Za-z_][A-Za-z0-9_.-]*/[^` ]*`' "$ROOT" \
               --include='*.md' --include='*.sh' --include='*.js' \
               --include='*.bats' --include='*.zsh' \
               --exclude-dir=fixtures \
             | tr -d '`' | sort -u); do
    case "$p" in
      skills/*|agents/*|commands/*|conventions/*|templates/*|hooks/*|scripts/*|tests/*|workflows/*) ;;
      # A monorepo-root prefix is a path this plugin does not have: it resolves
      # nowhere once core is a repo of its own, and nowhere here either.
      core/*) ;;
      *) continue ;;
    esac
    # bash 3.2's `compgen -G` succeeds on any pattern ending in `/`, existing or not,
    # so the trailing slash has to go before the glob is what decides.
    q="$(printf '%s' "$p" | sed 's/<[^>]*>/*/g')"
    compgen -G "$ROOT/${q%/}" >/dev/null \
      || missing="$missing $p"
  done
  [ -z "$missing" ] || { echo "path(s) that do not resolve under core:$missing"; return 1; }
}

@test "no file in core names the platform tree by a filesystem path" {
  # `$ROOT/../platform` has no trailing slash, so the prescribed `platform/` grep
  # walks straight past it — which is how two of these survived twelve reviews.
  # `git filter-repo --path core` turns every one of them into a dangling path
  # with no sibling tree left to restore.
  offenders="$(grep -rnE '(\.\./platform([^A-Za-z0-9_-]|$)|(^|[^A-Za-z0-9_.-])platform/)' "$ROOT" \
    | grep -vF 'project-config.test.bats' || true)"
  [ -z "$offenders" ] || { echo "core reference(s) to the platform tree:"; echo "$offenders"; return 1; }
}
