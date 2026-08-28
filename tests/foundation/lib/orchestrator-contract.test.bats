#!/usr/bin/env bats
# The role vocabulary is declared in three places that must agree: the lint that
# validates a platform's manifest, the `agents=` map the orchestrator hands to
# every executor, and the contract doc a third party writes a platform from.
# Drift between them resolves a stage to nothing at dispatch time, which is far
# from where the typo lives.

setup() {
  ROOT="$(cd -- "$(dirname -- "$BATS_TEST_FILENAME")/../../.." && pwd)"
  SKILL="$ROOT/skills/orchestrator/SKILL.md"
  LINT="$ROOT/scripts/lint-manifest.sh"
  CONTRACT="$ROOT/conventions/platform-contract.md"
  VOCABULARY="$(sed -n 's/^ROLES="\(.*\)"$/\1/p' "$LINT")"
  AGENT_KEYS="$(grep -m1 '^agents={' "$SKILL" \
    | sed 's/^agents={//; s/}$//' | tr ',' '\n' | sed 's/:.*//' | tr -d ' ' | tr '\n' ' ')"
  AGENT_KEYS="${AGENT_KEYS% }"
}

@test "the outbound contract's agents map covers exactly the core role vocabulary" {
  [ -n "$VOCABULARY" ]
  [ "$(tr ' ' '\n' <<<"$AGENT_KEYS" | sort | tr '\n' ' ')" \
    = "$(tr ' ' '\n' <<<"$VOCABULARY" | sort | tr '\n' ' ')" ]
}

@test "the outbound contract's agents map lists roles in vocabulary order" {
  [ "$AGENT_KEYS" = "$VOCABULARY" ]
}

@test "the platform contract names every core role" {
  for role in $VOCABULARY; do
    grep -qw "$role" "$CONTRACT" || {
      echo "role missing from conventions/platform-contract.md: $role"
      return 1
    }
  done
}
