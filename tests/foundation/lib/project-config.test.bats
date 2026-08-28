#!/usr/bin/env bats
# The project config is core's format: `setup` writes it, the orchestrator and
# stack-detect read it. A block missing from the template is a block no project
# ever has, so every consumer of it silently takes its absent branch — which is
# how `## Platform` spent three tasks being read from a file nothing wrote it to.
#
# The last test closes the reference class the cross-plugin greps cannot see: a
# bare relative path resolves under the naming plugin's own root, so a path that
# belongs to the other plugin simply finds nothing and no `core/` or `platform/`
# prefix ever appears for a grep to catch.

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
               --exclude-dir=fixtures \
             | tr -d '`' | sort -u); do
    case "$p" in
      skills/*|agents/*|commands/*|conventions/*|templates/*|hooks/*|scripts/*|tests/*|workflows/*) ;;
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
