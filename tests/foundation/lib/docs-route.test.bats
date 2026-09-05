#!/usr/bin/env bats
# The registry is the one place a project says which documentation exists and what it covers.
# A parser that silently drops a field turns a declared component into an undeclared one, and
# the run then reports the absence of an obligation instead of the obligation — which is the
# failure this whole mechanism was built to stop.

setup() {
  ROOT="$(cd -- "$(dirname -- "$BATS_TEST_FILENAME")/../../.." && pwd)"
  DR="$ROOT/scripts/docs-route.sh"
  PROJ="$BATS_TEST_TMPDIR/proj"
  mkdir -p "$PROJ"
  printf '## Docs\n\nmap: DocsMap.md\nstrictness: advisory\nfreshness: on\n' >"$PROJ/CLAUDE-spine-toolkit.md"
}

map() { cat >"$PROJ/DocsMap.md"; }

@test "a state component is read with its genre, strictness, places and covers" {
  map <<'EOF'
## Timeline

genre: state
strictness: blocking
places:
  - Documents/Timeline/
covers:
  - Sources/Timeline/**
  - Packages/TimelineCore/**
EOF
  run "$DR" registry "$PROJ"
  [ "$status" -eq 0 ]
  case "$output" in *"Timeline"*"state"*"blocking"*) ;; *) echo "$output"; return 1 ;; esac
}

@test "a component that declares no strictness inherits the block default" {
  map <<'EOF'
## Timeline

genre: state
places:
  - Documents/Timeline/
covers:
  - Sources/Timeline/**
EOF
  run "$DR" registry "$PROJ"
  [ "$status" -eq 0 ]
  case "$output" in *"advisory"*) ;; *) echo "$output"; return 1 ;; esac
}

@test "an absent registry is not an error — the mechanism is simply off" {
  run "$DR" registry "$PROJ"
  [ "$status" -eq 0 ]
  [ -z "$(printf '%s' "$output" | tr -d '[:space:]')" ] || { echo "$output"; return 1; }
}

@test "an unknown genre is a registry error, not a silently skipped component" {
  map <<'EOF'
## Timeline

genre: prose
places:
  - Documents/Timeline/
covers:
  - Sources/**
EOF
  run "$DR" registry "$PROJ"
  [ "$status" -eq 2 ]
  case "$output" in *"prose"*) ;; *) echo "$output"; return 1 ;; esac
}

@test "a state component with no covers is a registry error" {
  map <<'EOF'
## Timeline

genre: state
places:
  - Documents/Timeline/
EOF
  run "$DR" registry "$PROJ"
  [ "$status" -eq 2 ]
  case "$output" in *"covers"*) ;; *) echo "$output"; return 1 ;; esac
}

@test "a tracker with no fed_by is a registry error" {
  map <<'EOF'
## Snapping-Progress

genre: tracker
places:
  - Trackers/Snapping.md
EOF
  run "$DR" registry "$PROJ"
  [ "$status" -eq 2 ]
  case "$output" in *"fed_by"*) ;; *) echo "$output"; return 1 ;; esac
}
