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

@test "the outbound contract carries scale, and its example line is filled" {
  grep -qxF 'scale=lite|full' "$SKILL" || {
    echo "no filled scale= line in the Outbound Contract block"; return 1
  }
}

@test "the scale field documents the whole resolution chain" {
  para="$(awk '/^`scale` —/{f=1} f{print} f&&/^$/{exit}' "$SKILL")"
  [ -n "$para" ] || { echo "no \`scale\` paragraph in the Outbound Contract"; return 1; }
  for token in '[SCALE]' '## Scale' '`full`'; do
    case "$para" in
      *"$token"*) ;;
      *) echo "the scale chain does not name $token"; return 1 ;;
    esac
  done
}

@test "the ratchet writes back, refuses to lower, and honours an author's full" {
  grep -q 'scale_escalation' "$SKILL" || { echo "no scale_escalation return field"; return 1; }
  grep -qF '`[SCALE] = [full]`' "$SKILL" || { echo "no write-back into Task.md"; return 1; }
  grep -qi 'never lowered' "$SKILL" || { echo "the one-way rule is not stated"; return 1; }
}

@test "scale reaches the two profiles that have no implementing stage" {
  # Stated rather than omitted: a field that is "sometimes there" is a field
  # every consumer has to test for before reading.
  for p in review research; do
    grep -q 'scale' "$ROOT/skills/workflow-$p/SKILL.md" \
      || { echo "workflow-$p says nothing about scale"; return 1; }
  done
}
