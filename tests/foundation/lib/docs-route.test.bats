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

pkg() {
  mkdir -p "$PROJ/Packages/$1"
  cat >"$PROJ/Packages/$1/DocsMap.md"
}

paths_block() {
  printf '\n## Paths\n\n- External packages: /Packages/*\n' >>"$PROJ/CLAUDE-spine-toolkit.md"
}

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
  # The block's value differs from the code's own fallback on purpose: with both at `advisory`
  # a stub config() that never opened the file would pass this test unchanged.
  printf '## Docs\n\nmap: DocsMap.md\nstrictness: blocking\nfreshness: on\n' >"$PROJ/CLAUDE-spine-toolkit.md"
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
  case "$output" in *"blocking"*) ;; *) echo "$output"; return 1 ;; esac
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

@test "a list value that lost its indentation is an error, not a silently dropped field" {
  map <<'EOF'
## Timeline

genre: state
places:
  - Documents/Timeline/
covers:
  - Sources/Timeline/**
- Packages/TimelineCore/**
EOF
  run "$DR" registry "$PROJ"
  [ "$status" -eq 2 ]
  case "$output" in *"TimelineCore"*"indented"*) ;; *) echo "$output"; return 1 ;; esac
}

@test "a package registry contributes its components with package-relative paths resolved" {
  paths_block
  pkg Core <<'EOF'
## DSL

genre: state
places:
  - Documents/DSL/
covers:
  - Sources/DSL/**
EOF
  run "$DR" registry "$PROJ"
  [ "$status" -eq 0 ]
  case "$output" in *"DSL"*"Packages/Core/DocsMap.md"*) ;; *) echo "$output"; return 1 ;; esac
}

@test "a package's own places and covers come back prefixed with the package path" {
  # `source` is prefixed by relpath, not by under(), so the test above cannot see whether the
  # list values inside a package map are prefixed at all. This one can.
  paths_block
  pkg Core <<'EOF'
## DSL

genre: state
places:
  - Documents/DSL/
covers:
  - Sources/DSL/**
EOF
  run "$DR" registry "$PROJ" --paths
  [ "$status" -eq 0 ]
  case "$output" in *"covers"*"Packages/Core/Sources/DSL/**"*) ;; *) echo "$output"; return 1 ;; esac
  case "$output" in *"places"*"Packages/Core/Documents/DSL/"*) ;; *) echo "$output"; return 1 ;; esac
}

@test "one name declared in two registries stops the assembly and names both files" {
  paths_block
  map <<'EOF'
## DSL

genre: state
places:
  - Documents/DSL/
covers:
  - Sources/**
EOF
  pkg Core <<'EOF'
## DSL

genre: state
places:
  - Documents/DSL/
covers:
  - Sources/DSL/**
EOF
  run "$DR" registry "$PROJ"
  [ "$status" -eq 2 ]
  case "$output" in *"DocsMap.md"*"Packages/Core/DocsMap.md"*) ;; *) echo "$output"; return 1 ;; esac
}

@test "a package without a registry contributes nothing and is not an error" {
  paths_block
  mkdir -p "$PROJ/Packages/Quiet"
  map <<'EOF'
## Timeline

genre: state
places:
  - Documents/Timeline/
covers:
  - Sources/**
EOF
  run "$DR" registry "$PROJ"
  [ "$status" -eq 0 ]
  [ "$(printf '%s\n' "$output" | grep -c .)" -eq 1 ]
  case "$output" in *Timeline*) ;; *) echo "$output"; return 1 ;; esac
}
