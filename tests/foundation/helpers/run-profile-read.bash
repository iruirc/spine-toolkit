#!/usr/bin/env bash
# Shared bats helper over run-profile-read.js: run a profile with stubbed agents and read several
# things from its result in one node start. Source from a .bats file via:
#   load "$(dirname "$BATS_TEST_FILENAME")/../helpers/run-profile-read"

RP_HELPERS="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
RP_ROOT="$(cd -- "$RP_HELPERS/../../.." && pwd)"

# $1 profile, $2 contract, $3 replies, then JS expressions over o: V[0], V[1], ... are their values.
rp() {
  local raw i=0
  raw="$(node "$RP_HELPERS/run-profile-read.js" "$RP_ROOT/workflows/profile-$1.js" "$2" "$3" "${@:4}")"
  V=()
  while :; do
    V[i]="${raw%%$'\x1e'*}"; i=$((i + 1))
    [[ "$raw" == *$'\x1e'* ]] || break
    raw="${raw#*$'\x1e'}"
  done
}
