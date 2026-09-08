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

@test "the orchestrator documents the driver pre-flight and both its keys" {
  SK="$ROOT/skills/orchestrator/SKILL.md"
  grep -q 'warn_driver_plugin_missing' "$SK" || { echo "key not referenced from the body"; return 1; }
  grep -q 'warn_driver_server_missing' "$SK" || { echo "key not referenced from the body"; return 1; }
  # The check must be conditional, or every run pays for a manifest it will not use.
  # Scoped to the Routing window on purpose: SKILL.md already names drive_app around
  # line 366, explaining why walkthrough travels in the contract and it does not. An
  # unscoped grep is therefore green before this task's edit and tests nothing.
  routing="$(awk '/^## Routing$/{r=1;next} /^## State Detection$/{r=0} r' "$SK")"
  grep -q 'drive_app' <<<"$routing" \
    || { echo "the pre-flight does not name its gate inside ## Routing"; return 1; }
}

@test "the driver does not travel in the Outbound Contract" {
  # D-10 of the spec, as a guard: core holds the driver's name to warn about it and
  # for nothing else. The moment it rides the contract, a workflow script starts
  # gating on it, and core owns a decision that belongs to whoever drives. drive_app
  # is absent for the same reason and stays the reference for this shape.
  SK="$ROOT/skills/orchestrator/SKILL.md"
  contract="$(awk '/^## Outbound Contract$/{c=1;next} /^## Dispatch$/{c=0} c' "$SK")"
  ! grep -qE '\bdriver\b' <<<"$contract" \
    || { echo "the Outbound Contract names the driver; it must not"; return 1; }
}

@test "both driver warning keys exist in both locales with parity" {
  for lang in en ru; do
    L="$ROOT/skills/orchestrator/locales/$lang.md"
    for key in warn_driver_plugin_missing warn_driver_server_missing; do
      grep -q "^## $key\$" "$L" || { echo "$key missing from $lang.md"; return 1; }
    done
  done
}
