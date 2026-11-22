#!/usr/bin/env bats
# changed: sweep skills workflows
# ops-risks is a closed list of seven operational risks the diff can show. It writes no artifact:
# the architect lays the proof into a phase at Plan, the reviewer checks it against the diff at
# Review. This suite holds the text of the skill and the design questions that feed it.

setup() {
  ROOT="$(cd -- "$(dirname -- "$BATS_TEST_FILENAME")/../../.." && pwd)"
  SKILL="$ROOT/skills/ops-risks/SKILL.md"
}

# A section's body, heading excluded, up to the next H2.
section() { # $1 = file, $2 = heading text without "## "
  awk -v h="## $2" '$0==h{f=1;next} f&&/^## /{exit} f' "$1"
}

@test "the skill exists under its own name and writes no artifact" {
  [ -f "$SKILL" ] || { echo "no skills/ops-risks/SKILL.md"; return 1; }
  grep -qxF 'name: ops-risks' "$SKILL" || { echo "frontmatter name is not ops-risks"; return 1; }
  grep -qF 'It writes no artifact.' "$SKILL" || { echo "nothing says the skill writes no artifact"; return 1; }
}

@test "the skill carries its five sections" {
  for h in 'Touches' 'Risks' 'Plan' 'Review' 'Language'; do
    grep -qxF "## $h" "$SKILL" || { echo "no ## $h"; return 1; }
  done
}

@test "the risk list is closed and holds exactly the seven labels" {
  s="$(section "$SKILL" 'Risks')"
  got="$(grep -oE '^\| `[a-z-]+` \|' <<<"$s" | sed -E 's/^\| `([a-z-]+)` \|$/\1/' | paste -sd ' ' -)"
  [ "$got" = "startup lifecycle stored-data contract rollout-flag hot-path release-settings" ] \
    || { echo "## Risks labels are: $got"; return 1; }
  grep -qF 'The list is closed.' <<<"$s" || { echo "nothing closes the list"; return 1; }
}

@test "security is left to security-lens" {
  intro="$(awk '/^## /{exit} {print}' "$SKILL")"
  grep -qF 'security-lens' <<<"$intro" || { echo "the introduction does not hand security to security-lens"; return 1; }
}

@test "touches reaches the behaviour's path, and doubt counts as touching" {
  s="$(section "$SKILL" 'Touches')"
  for token in 'code the behaviour calls, or code that calls it' 'When in doubt, it touches.'; do
    grep -qF "$token" <<<"$s" || { echo "## Touches does not say $token"; return 1; }
  done
}

@test "Review sorts a missing proof by who can give it" {
  s="$(section "$SKILL" 'Review')"
  for token in 'Major' 'Minor' '## For Done' '## Ops risks' 'none triggered — the diff touches' 'no case in ManualChecks.md'; do
    grep -qF -- "$token" <<<"$s" || { echo "## Review does not say $token"; return 1; }
  done
}

@test "Plan puts the proof into the phase" {
  s="$(section "$SKILL" 'Plan')"
  for token in '**Verification:**' '## For the owner'; do
    grep -qF -- "$token" <<<"$s" || { echo "## Plan does not say $token"; return 1; }
  done
}

@test "the size of the task does not move it" {
  grep -qF "follows from what the diff touches, never from the task's size." "$SKILL" \
    || { echo "the skill does not state the rule"; return 1; }
}

@test "feature-requirements asks the three design questions" {
  f="$ROOT/skills/feature-requirements/SKILL.md"
  for row in '| Rollout switch |' '| Stored data |' '| Performance-sensitive path |'; do
    grep -qF -- "$row" "$f" || { echo "feature-requirements has no row $row"; return 1; }
  done
}
