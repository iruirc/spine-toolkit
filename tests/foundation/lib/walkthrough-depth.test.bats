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
  grep -qF '`on` is deprecated and resolves to `deep`' <<<"$sw" \
    || { echo "the pre-1.8 value is not resolved"; return 1; }
}

@test "the skill names its reader before it names any budget" {
  grep -q '^## Reader$' "$SKILL" || { echo "no ## Reader section"; return 1; }
  reader="$(awk '/^## Reader$/{f=1;next} /^## /{f=0} f' "$SKILL")"
  grep -q 'did not write this code and was not on this task' <<<"$reader" \
    || { echo "## Reader does not name the reader"; return 1; }
  reader_at="$(grep -n '^## Reader$' "$SKILL" | head -1 | cut -d: -f1)"
  budgets_at="$(grep -n '^## Structure$' "$SKILL" | head -1 | cut -d: -f1)"
  [ -n "$reader_at" ] || { echo "no ## Reader heading to locate"; return 1; }
  [ -n "$budgets_at" ] || { echo "no ## Structure heading to locate; it was renamed"; return 1; }
  [ "$reader_at" -lt "$budgets_at" ] \
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

@test "the resolution chain is pinned link by link, not just at its tail" {
  sw="$(awk '/^## The switch$/{f=1;next} /^## /{f=0} f' "$SKILL")"
  grep -qF '`[WALKTHROUGH] = [brief|deep|off]` in `Task.md`' <<<"$sw" \
    || { echo "the first link of the chain is not pinned"; return 1; }
  grep -qF '`off` when the run'"'"'s `scale` is `lite`' <<<"$sw" \
    || { echo "the lite step of the chain is not pinned"; return 1; }
}

@test "every section name later tasks cite exists under its exact spelling" {
  grep -q '^### `## Out of scope` (`deep`)$' "$SKILL" \
    || { echo "no out-of-scope section"; return 1; }
  while IFS= read -r h; do
    grep -qF "$h" "$SKILL" || { echo "sub-heading missing or renamed: $h"; return 1; }
  done <<'NAMES'
#### What appeared
#### What failure this is written against
#### How it is closed
#### Why <X> and not <Y>
#### What is deliberately absent
NAMES
}

@test "the config template ships the deep default and explains all three values" {
  T="$ROOT/templates/claude-toolkit-md/en.md"
  rep="$(awk '/^## Reporting$/{f=1;next} /^## /{f=0} f' "$T")"
  grep -qxF 'walkthrough: deep' <<<"$rep" \
    || { echo "the template does not ship deep"; return 1; }
  # anchored: the migration sentence names every value too, and would satisfy a bare token
  for v in '^`deep` — ' '^`brief` — ' '^`off` — '; do
    grep -q "$v" <<<"$rep" || { echo "## Reporting does not enumerate $v"; return 1; }
  done
  grep -qF '`on` is the pre-1.8 spelling and is read as `deep`' <<<"$rep" \
    || { echo "the template does not say what happens to on"; return 1; }
  grep -qF '`[WALKTHROUGH] = [brief|deep|off]` in its `Task.md`' <<<"$rep" \
    || { echo "the template's override spelling drifted from task-md and task-new"; return 1; }
  # the value shipped above and the value the prose calls the default must be one value
  shipped="$(sed -n 's/^walkthrough: //p' <<<"$rep")"
  para="$(awk -v lead="\`$shipped\` — " '
    index($0, lead) == 1 { f = 1 }
    f && substr($0, 1, 1) == "`" && index($0, lead) != 1 { exit }
    f { print }' <<<"$rep")"
  grep -qF 'it is the default' <<<"$para" \
    || { echo "the shipped value $shipped is not the one the prose calls the default"; return 1; }
}

@test "both task templates offer the three values in the optional block" {
  for f in task-root task-step; do
    grep -qF '# [WALKTHROUGH] = [off]       # brief | deep | off' \
      "$ROOT/templates/task-md/$f.md" \
      || { echo "$f.md does not offer the three values"; return 1; }
  done
}

@test "task-new tells the author when brief is the right choice" {
  N="$ROOT/skills/task-new/SKILL.md"
  grep -qF '`[WALKTHROUGH] = [<brief|deep|off>]`' "$N" \
    || { echo "task-new still documents a two-value axis"; return 1; }
  grep -qF 'readers already know the area' "$N" \
    || { echo "task-new does not say when to pick brief"; return 1; }
}
