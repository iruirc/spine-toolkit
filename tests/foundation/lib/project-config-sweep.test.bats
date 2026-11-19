#!/usr/bin/env bats
# changed: sweep skills conventions templates workflows commands
# Split from project-config.test.bats: the tests that walk the source trees.

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
