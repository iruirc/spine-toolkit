#!/usr/bin/env bats
# The artifact is declared to be for someone who was not on the task, and was
# written for the author instead. What holds the difference is not a length
# ceiling but two things a grep can see: a named reader, and a value vocabulary
# with more than "yes" in it.

setup() {
  ROOT="$(cd -- "$(dirname -- "$BATS_TEST_FILENAME")/../../.." && pwd)"
  SKILL="$ROOT/skills/task-walkthrough/SKILL.md"
}

@test "the switch offers all three values" {
  sw="$(awk '/^## The switch$/{f=1;next} /^## /{f=0} f' "$SKILL")"
  for v in '`brief`' '`deep`' '`off`'; do
    grep -qF "$v" <<<"$sw" || { echo "## The switch does not offer $v"; return 1; }
  done
}

@test "the switch names deep as the default and reads on as deep" {
  sw="$(awk '/^## The switch$/{f=1;next} /^## /{f=0} f' "$SKILL")"
  grep -qF 'walkthrough:` in `CLAUDE-spine-toolkit.md` → `deep`' <<<"$sw" \
    || { echo "the chain does not end at deep"; return 1; }
  grep -qF '`on` is accepted as a deprecated spelling of `deep`' <<<"$sw" \
    || { echo "the pre-1.8 spelling is not resolved"; return 1; }
}

@test "the skill names its reader before it names any budget" {
  grep -q '^## Reader$' "$SKILL" || { echo "no ## Reader section"; return 1; }
  reader="$(awk '/^## Reader$/{f=1;next} /^## /{f=0} f' "$SKILL")"
  grep -q 'did not write this code and was not on this task' <<<"$reader" \
    || { echo "## Reader does not name the reader"; return 1; }
  [ "$(grep -n '^## Reader$' "$SKILL" | cut -d: -f1)" \
    -lt "$(grep -n '^## Structure$' "$SKILL" | cut -d: -f1)" ] \
    || { echo "the reader is named after the budgets that are supposed to derive from it"; return 1; }
}

@test "a budget bounds scope and is forbidden from bounding comprehension" {
  grep -q '^## Style$' "$SKILL" || { echo "no ## Style section"; return 1; }
  grep -qF 'The budgets bound **scope**, not comprehension' "$SKILL" \
    || { echo "the budget note does not say what it bounds"; return 1; }
  grep -qF '**Telegraphic compression.**' "$SKILL" \
    || { echo "the anti-pattern that produced the problem is not listed"; return 1; }
}

@test "the deep form carries the two sections it exists for" {
  grep -q '^### `## Glossary` (`deep`)$' "$SKILL" || { echo "no glossary section"; return 1; }
  grep -q '^### `## Commit order` (`deep`)$' "$SKILL" || { echo "no commit-order section"; return 1; }
  grep -q '^### `## Commits` — `deep`$' "$SKILL" || { echo "no deep commit form"; return 1; }
  grep -q '^### `## Commits` — `brief`$' "$SKILL" || { echo "no brief commit form"; return 1; }
}

@test "the commit sub-headings are a menu and say so" {
  grep -qF 'menu, not a checklist' "$SKILL" \
    || { echo "nothing stops a rename commit from carrying five empty headings"; return 1; }
  grep -qF '**Deep by reflex.**' "$SKILL" \
    || { echo "the anti-pattern for a filled-out empty section is missing"; return 1; }
}

@test "the coverage anchor keeps the shape docs-route parses" {
  grep -qxF '[COVERS] = <first-sha>..<last-sha>' "$SKILL" \
    || { echo "the anchor's byte-for-byte form moved"; return 1; }
  grep -q 'docs-route.sh' "$SKILL" \
    || { echo "the skill does not say who parses the anchor"; return 1; }
}

@test "no downstream project's vocabulary entered the skill's examples" {
  # Every example is invented on purpose: client-derived material is not kept in
  # this repository, and a redacted example is unreadable rather than general.
  ! grep -qiE 'vsdc|ios_ve|MediaTime|TrackAttachment|hostSourceTime' "$SKILL" \
    || { echo "a downstream project's names are in the skill"; return 1; }
}
