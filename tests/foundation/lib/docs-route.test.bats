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

task() {
  TASK="$PROJ/Tasks/ACTIVE/042-a-task"
  mkdir -p "$TASK"
  printf '[TASK_TYPE] = [FEATURE]\n' >"$TASK/Task.md"
}

two_components() {
  map <<'EOF'
## Timeline

genre: state
strictness: blocking
places:
  - Documents/Timeline/
covers:
  - Sources/Timeline/**

## Snapping-Progress

genre: tracker
places:
  - Trackers/Snapping.md
fed_by:
  - Tasks/*/042-*
EOF
}

@test "a changed path under covers opens a row for that component" {
  task; two_components
  run bash -c "printf 'M\tSources/Timeline/Resolver.txt\n' | '$DR' route '$PROJ' --task-dir '$TASK' --phase 3"
  [ "$status" -eq 0 ]
  grep -q '^| 3 | Timeline | state | blocking |  |  |$' "$TASK/Docs.md"
}

@test "a tracker is never asked — routing writes no row for it" {
  task; two_components
  run bash -c "printf 'M\tSources/Timeline/Resolver.txt\n' | '$DR' route '$PROJ' --task-dir '$TASK' --phase 3"
  [ "$status" -eq 0 ]
  ! grep -q 'Snapping-Progress' "$TASK/Docs.md"
}

@test "a path outside every covers opens no row at all" {
  task; two_components
  run bash -c "printf 'M\tSources/Export/Writer.txt\n' | '$DR' route '$PROJ' --task-dir '$TASK' --phase 3"
  [ "$status" -eq 0 ]
  ! grep -q '^| 3 |' "$TASK/Docs.md"
}

@test "a bare path with no status column is read as modified" {
  task; two_components
  run bash -c "printf 'Sources/Timeline/Resolver.txt\n' | '$DR' route '$PROJ' --task-dir '$TASK' --phase 1"
  [ "$status" -eq 0 ]
  grep -q '^| 1 | Timeline |' "$TASK/Docs.md"
}

@test "a rename is routed by its destination path" {
  task; two_components
  run bash -c "printf 'R100\tSources/Export/Old.txt\tSources/Timeline/New.txt\n' | '$DR' route '$PROJ' --task-dir '$TASK' --phase 2"
  [ "$status" -eq 0 ]
  grep -q '^| 2 | Timeline |' "$TASK/Docs.md"
}

@test "routing the same phase twice does not duplicate a row" {
  task; two_components
  printf 'M\tSources/Timeline/Resolver.txt\n' | "$DR" route "$PROJ" --task-dir "$TASK" --phase 3
  printf 'M\tSources/Timeline/Other.txt\n' | "$DR" route "$PROJ" --task-dir "$TASK" --phase 3
  [ "$(grep -c '^| 3 | Timeline |' "$TASK/Docs.md")" -eq 1 ]
}

@test "the same component in a later phase is a new row" {
  task; two_components
  printf 'M\tSources/Timeline/Resolver.txt\n' | "$DR" route "$PROJ" --task-dir "$TASK" --phase 3
  printf 'M\tSources/Timeline/Other.txt\n' | "$DR" route "$PROJ" --task-dir "$TASK" --phase 4
  [ "$(grep -c '| Timeline |' "$TASK/Docs.md")" -eq 2 ]
}

@test "[DOCS] = [off] in Task.md silences routing for that task" {
  task; two_components
  printf '[TASK_TYPE] = [FEATURE]\n[DOCS] = [off]\n' >"$TASK/Task.md"
  run bash -c "printf 'M\tSources/Timeline/Resolver.txt\n' | '$DR' route '$PROJ' --task-dir '$TASK' --phase 3"
  [ "$status" -eq 0 ]
  [ ! -f "$TASK/Docs.md" ]
}

@test "the commented override line in the task template is not a value" {
  task; two_components
  printf '[TASK_TYPE] = [FEATURE]\n# [DOCS] = [off]         # on | off\n' >"$TASK/Task.md"
  run bash -c "printf 'M\tSources/Timeline/Resolver.txt\n' | '$DR' route '$PROJ' --task-dir '$TASK' --phase 3"
  [ "$status" -eq 0 ]
  grep -q '^| 3 | Timeline |' "$TASK/Docs.md"
}

@test "a checkout's diff is re-origined to the project root" {
  run bash -c "printf 'M\tSources/Timeline/Resolver.txt\n' | '$DR' reorigin Packages/Core"
  [ "$status" -eq 0 ]
  [ "$output" = "$(printf 'M\tPackages/Core/Sources/Timeline/Resolver.txt')" ]
}

@test "re-origining carries both path columns of a rename" {
  run bash -c "printf 'R100\tA/Old.txt\tA/New.txt\n' | '$DR' reorigin ../shared"
  [ "$status" -eq 0 ]
  [ "$output" = "$(printf 'R100\t../shared/A/Old.txt\t../shared/A/New.txt')" ]
}

@test "a tracker named in DOCS_NEW is named but never asked" {
  task; two_components
  printf '[TASK_TYPE] = [FEATURE]\n[DOCS_NEW] = [Attach-Progress:tracker]\n' >"$TASK/Task.md"
  run bash -c "printf 'M\tSources/Export/Writer.txt\n' | '$DR' route '$PROJ' --task-dir '$TASK' --phase 3"
  [ "$status" -eq 0 ]
  case "$output" in *"Attach-Progress"*) ;; *) echo "$output"; return 1 ;; esac
  [ ! -f "$TASK/Docs.md" ] || ! grep -q 'Attach-Progress' "$TASK/Docs.md"
}

@test "a component named in DOCS_NEW opens a row even though nothing covers it yet" {
  task
  map <<'EOF'
## Timeline

genre: state
places:
  - Documents/Timeline/
covers:
  - Sources/Timeline/**
EOF
  printf '[TASK_TYPE] = [FEATURE]\n[DOCS_NEW] = [TrackAttachment:state]\n' >"$TASK/Task.md"
  run bash -c "printf 'M\tSources/Export/Writer.txt\n' | '$DR' route '$PROJ' --task-dir '$TASK' --phase 3"
  [ "$status" -eq 0 ]
  grep -q '^| 3 | TrackAttachment | state | .* |  |  |$' "$TASK/Docs.md"
}
