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
  grep -qF '`[WALKTHROUGH]` in `CLAUDE-spine-toolkit.md` → `deep`' <<<"$sw" \
    || { echo "the chain does not end at deep"; return 1; }
  grep -qF '`on` is the pre-depth value and resolves to `deep`' <<<"$sw" \
    || { echo "the pre-depth value is not resolved, or is named in a second vocabulary"; return 1; }
  grep -qF 'a project that wanted the old shape says `brief`' <<<"$sw" \
    || { echo "the notice does not tell an owner how to get the old shape back"; return 1; }
  # The writing agent is handed a depth, never the raw value, so it cannot know a
  # substitution happened; the skill must not ask it to say one did.
  grep -qF 'announced by the orchestrator, which is the only component that sees the raw value' <<<"$sw" \
    || { echo "the skill does not say who announces the substitution"; return 1; }
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

@test "the depth table still carries both columns and the sections brief drops" {
  # This table is the axis. Without it the two depths are the same document.
  grep -qF '| Section | Content | `brief` | `deep` |' "$SKILL" \
    || { echo "the ## Structure table lost its header row, or one of its depth columns"; return 1; }
  grep -qE '^\| header \|.*\| the four parts above \| the four parts above \|$' "$SKILL" \
    || { echo "the header row no longer names its contents at both depths"; return 1; }
  for s in '`## Glossary`' '`## Commit order`' '`## Out of scope`'; do
    # `|| true`: a bare failing grep inside $() aborts the test before the echo.
    row="$(grep -F "| $s |" "$SKILL" || true)"
    grep -qF '| absent |' <<<"$row" \
      || { echo "the table no longer marks $s absent at brief"; return 1; }
  done
}

@test "the three moves at a ceiling are ranked, and ranked in that order" {
  grep -qF 'the three moves are ranked, and the order is what decides' "$SKILL" \
    || { echo "the moves are listed but nothing says the order decides"; return 1; }
  grep -qF '1. **Never compress.**' "$SKILL" \
    || { echo "the highest-ranked move is gone: compression is what this branch exists to stop"; return 1; }
  grep -qF '2. **Go over rather than drop.**' "$SKILL" \
    || { echo "nothing says the ceiling yields before a claim does"; return 1; }
  grep -qF '3. **Consistently far over means the scope is wrong.**' "$SKILL" \
    || { echo "nothing says a section far over should shed claims, not sentences"; return 1; }
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

@test "the section that holds those headings in English is still there" {
  # Deleted once on this branch with the whole suite green. Later tasks cite the
  # headings verbatim, and a translated one breaks the citation.
  grep -q '^## Localization$' "$SKILL" \
    || { echo "## Localization is gone; nothing keeps the structure untranslated"; return 1; }
  lang="$(awk '/^## Localization$/{f=1;next} /^## /{f=0} f' "$SKILL")"
  grep -qF "Prose in the project's language, structure in English" <<<"$lang" \
    || { echo "## Localization no longer states the split it exists for"; return 1; }
}

@test "the config template ships the deep default beside all three values" {
  T="$ROOT/templates/claude-toolkit-md/en.md"
  grep -qE '^\[WALKTHROUGH\] = \[deep\] +# brief \| deep \| off$' "$T" \
    || { echo "the template does not ship deep beside the three values"; return 1; }
}

@test "the depth guidance explains all three values and what becomes of on" {
  # The guidance left the template when the settings became one-line fields; the reference page is
  # where it lands, and these assertions go live with it.
  doc="$ROOT/docs/configuration.md"
  # anchored: the migration sentence names every value too, and would satisfy a bare token
  for v in '^`deep` — ' '^`brief` — ' '^`off` — '; do
    grep -q "$v" "$doc" || { echo "the guidance does not enumerate $v"; return 1; }
  done
  grep -qF '`on` is the pre-depth value and is read as `deep`' "$doc" \
    || { echo "the guidance does not say what happens to on"; return 1; }
  grep -qF '`[WALKTHROUGH] = [brief|deep|off]`' "$doc" \
    || { echo "the override spelling drifted from task-md and task-new"; return 1; }
  # The slice runs from the `deep` line to the next line opening with a backtick, so each value's
  # description must start its own line at column 0 — a bullet or a re-wrap breaks it.
  para="$(awk '
    index($0, "`deep` — ") == 1 { f = 1 }
    f && substr($0, 1, 1) == "`" && index($0, "`deep` — ") != 1 { exit }
    f { print }' "$doc")"
  grep -qF 'it is the default' <<<"$para" \
    || { echo "the shipped value deep is not the one the guidance calls the default"; return 1; }
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

@test "every profile script hands the resolved depth to the writing agent" {
  for p in "$ROOT"/workflows/profile-*.js; do
    grep -qF "const depth = A.walkthrough === 'brief' ? 'brief' : 'deep'" "$p" \
      || { echo "first miss — $(basename "$p"): does not normalise the axis to a depth"; return 1; }
    grep -qF 'Walkthrough.md at depth ${depth}' "$p" \
      || { echo "first miss — $(basename "$p"): the depth never reaches the brief"; return 1; }
    grep -qF 'its ## The switch section says what ${depth} changes, and its ## Reader section' "$p" \
      || { echo "first miss — $(basename "$p"): the brief drops where depth is defined"; return 1; }
  done
}

@test "the off gate still short-circuits before any agent is dispatched" {
  # brief and deep must both fall through it; only off and the legacy false stop. Anchored at both
  # ends, so an appended limb that stops brief goes red instead of still containing the substring.
  for p in "$ROOT"/workflows/profile-*.js; do
    grep -qF "if (!WALKTHROUGH_AGENT || A.walkthrough === 'off' || A.walkthrough === false) return" "$p" \
      || { echo "first miss — $(basename "$p"): the off gate moved or changed shape"; return 1; }
  done
}

@test "every profile that writes the file tells its agent the value is a depth" {
  for p in feature bug refactor test epic; do
    S="$ROOT/skills/workflow-$p/SKILL.md"
    grep -qF 'the depth the contract carries' "$S" \
      || { echo "workflow-$p: the stage does not say the value is a depth"; return 1; }
  done
}

@test "the walkthrough chain spells the lite step in the canonical position" {
  # Used to be five copies, one per workflow-*/SKILL.md (epic named no `scale` step at all, the
  # four siblings named it last). The settings-resolver task consolidated the governance sentence
  # to a contract pointer in every one of them, so the chain — and its precedence, lite gate
  # before project config — is pinned once, here, instead.
  C="$ROOT/conventions/task-settings.md"
  grep -qF 'Task.md [WALKTHROUGH]  →  off when scale resolved to lite  →  CLAUDE-spine-toolkit.md [WALKTHROUGH]  →  deep' "$C" \
    || { echo "the chain omits the lite step or orders it wrong"; return 1; }
}

@test "the walkthrough chain ends at the new default" {
  C="$ROOT/conventions/task-settings.md"
  grep -qF 'CLAUDE-spine-toolkit.md [WALKTHROUGH]  →  deep' "$C" \
    || { echo "task-settings.md still defaults to the pre-depth value"; return 1; }
}

@test "the scale convention's worked example uses a value that still exists" {
  C="$ROOT/conventions/task-scale.md"
  grep -qF '`[WALKTHROUGH] = [deep]` in `Task.md` writes `Walkthrough.md` on a `lite` run' "$C" \
    || { echo "the worked example still sets a value the axis no longer has"; return 1; }
  ! grep -qF '[WALKTHROUGH] = [on]' "$C" \
    || { echo "the pre-depth value survives in the convention"; return 1; }
}

@test "the per-unit budget note describes both depths" {
  C="$ROOT/conventions/task-scale.md"
  grep -qF 'a section per commit at `deep` and a bullet at `brief`' "$C" \
    || { echo "the budget note still describes one shape"; return 1; }
}

@test "the file opens with what changed, at both depths, before the glossary" {
  row="$(grep -F '| `## What changed` |' "$SKILL" || true)"
  [ -n "$row" ] || { echo "the ## Structure table has no What changed row"; return 1; }
  ! grep -qF '| absent |' <<<"$row" || { echo "What changed is absent at one depth"; return 1; }
  wc_at="$(grep -nF '| `## What changed` |' "$SKILL" | head -1 | cut -d: -f1)"
  gl_at="$(grep -nF '| `## Glossary` |' "$SKILL" | head -1 | cut -d: -f1)"
  [ "$wc_at" -lt "$gl_at" ] || { echo "What changed is listed after the glossary it must not need"; return 1; }
  grep -q '^### `## What changed`$' "$SKILL" || { echo "no subsection for What changed"; return 1; }
  for label in '**Before:**' '**After:**' '**Commits:**' '**Behaviour:** unchanged' '**Steps:**'; do
    grep -qF "$label" "$SKILL" || { echo "What changed does not show $label"; return 1; }
  done
  grep -qF 'one and the same concrete case' "$SKILL" || { echo "nothing ties before and after to one case"; return 1; }
}

@test "the header is named by its contents, and bookkeeping is kept out of it" {
  grep -qF '| Repository | Range | Commits | ± lines |' "$SKILL" || { echo "no perimeter table"; return 1; }
  grep -qF '**Bookkeeping in the header.**' "$SKILL" || { echo "no anti-pattern for a header full of bookkeeping"; return 1; }
  ! grep -qF '≤ 10 lines' "$SKILL" || { echo "the header still carries a line count"; return 1; }
}

@test "a commit names the change it serves, and bookkeeping commits collapse into one list" {
  grep -qF '**Changes:**' "$SKILL" || { echo "a commit does not say which change it serves"; return 1; }
  grep -q '^### Bookkeeping commits$' "$SKILL" || { echo "no rule for bookkeeping commits"; return 1; }
  grep -qxF '### Bookkeeping' "$SKILL" || { echo "the closing list of bookkeeping commits is not shown"; return 1; }
}

@test "deep's explanatory sections are bounded by scope, not by a line count" {
  summary="$(grep -F '| `## Summary` |' "$SKILL" || true)"
  ! grep -qF '≤ 12' <<<"$summary" || { echo "Summary at deep still carries a line count"; return 1; }
  ! grep -qF '≤ 12 lines each' "$SKILL" || { echo "commit sub-headings still carry a line count"; return 1; }
  grep -qF 'is bounded by its scope alone' "$SKILL" || { echo "nothing says what bounds a section with no number"; return 1; }
}

@test "an identifier is a reference, never the subject" {
  st="$(awk '/^## Style$/{f=1;next} /^## /{f=0} f' "$SKILL")"
  grep -qF '**An identifier is a reference, never the subject.**' <<<"$st" || { echo "## Style has no rule for identifiers"; return 1; }
  grep -qF '**An identifier as the subject.**' "$SKILL" || { echo "no anti-pattern for an identifier as the subject"; return 1; }
}

@test "the check has a section of its own, and the writer never runs it" {
  grep -q '^## Check$' "$SKILL" || { echo "no ## Check section"; return 1; }
  ck="$(awk '/^## Check$/{f=1;next} /^## /{f=0} f' "$SKILL")"
  for token in '`walkthrough_check`' '`[WALKTHROUGH_CHECK]`' 'The writer never checks its own file' \
               'reads `Walkthrough.md` and nothing else' '`retelling`' '`unclear`' '**Revision.**' \
               '**One round.**' 'append-only rule does not apply'; do
    grep -qF "$token" <<<"$ck" || { echo "## Check does not say $token"; return 1; }
  done
}

@test "the English structure list names the new sections and labels" {
  lang="$(awk '/^## Localization$/{f=1;next} /^## /{f=0} f' "$SKILL")"
  for token in '`## What changed`' '`### Bookkeeping`' '`**Changes:**`'; do
    grep -qF "$token" <<<"$lang" || { echo "## Localization does not keep $token in English"; return 1; }
  done
}

@test "the check's field is offered and documented wherever a setting is" {
  T="$ROOT/templates/claude-toolkit-md/en.md"
  grep -qE '^\[WALKTHROUGH_CHECK\] = \[auto\] +# auto \| on \| off$' "$T" \
    || { echo "the config template does not ship auto beside the three values"; return 1; }
  for f in task-root task-step; do
    grep -qxF '# [WALKTHROUGH_CHECK] = [off] # auto | on | off' "$ROOT/templates/task-md/$f.md" \
      || { echo "$f.md does not offer the field"; return 1; }
  done
  D="$ROOT/docs/configuration.md"
  grep -qxF '### [WALKTHROUGH_CHECK]' "$D" || { echo "docs/configuration.md has no section for the field"; return 1; }
  grep -qF '`[WALKTHROUGH_CHECK] = [auto|on|off]`' "$D" || { echo "the override spelling is missing"; return 1; }
  grep -qF '`[WALKTHROUGH_CHECK] = [<auto|on|off>]`' "$ROOT/skills/task-new/SKILL.md" \
    || { echo "task-new does not offer the field"; return 1; }
  grep -qF '| `walkthrough_check` | `[WALKTHROUGH_CHECK]` | `[WALKTHROUGH_CHECK]` | `auto` `on` `off` |' \
    "$ROOT/conventions/task-settings.md" || { echo "task-settings.md has no row for the field"; return 1; }
}

@test "the depth guidance says what changed opens both depths" {
  doc="$ROOT/docs/configuration.md"
  grep -q '^`deep` — what changed' "$doc" || { echo "deep does not open with what changed"; return 1; }
  grep -q '^`brief` — what changed' "$doc" || { echo "brief does not open with what changed"; return 1; }
}

@test "every profile script checks a changed walkthrough when the contract says so" {
  n=0
  for p in "$ROOT"/workflows/profile-*.js; do
    n=$((n + 1))
    for line in "if (WALKTHROUGH_CHECK !== 'on' || w.changed === false) return" \
                "await checkWalkthrough(stage, agentType, depth, extra)" \
                "label: 'walkthrough:check'" "label: 'walkthrough:revise'" \
                "schema: COLD_READ, ...tuning(WALKTHROUGH_AGENT, 'light')" \
                "schema: WALKTHROUGH_ARTIFACT, ...tuning(WALKTHROUGH_AGENT, 'walkthrough')" \
                "required: ['ok', 'artifact_path', 'summary', 'changed']" \
                'Return changed true when you wrote the file, false when you left it as it was.'; do
      grep -qF "$line" "$p" || { echo "$(basename "$p"): missing '$line'"; return 1; }
    done
  done
  [ "$n" -eq 8 ] || { echo "scanned $n script(s), expected 8"; return 1; }
}

@test "the reader of the check is kept away from everything but the file" {
  for p in "$ROOT"/workflows/profile-*.js; do
    grep -qF 'open no other file of the task and no source file' "$p" \
      || { echo "$(basename "$p"): the reader is not confined to the file"; return 1; }
    grep -qF 'run no git command' "$p" || { echo "$(basename "$p"): the reader may still read git"; return 1; }
  done
}

@test "every profile that writes the file runs the check the contract asks for" {
  for p in feature bug refactor test epic; do
    S="$ROOT/skills/workflow-$p/SKILL.md"
    grep -qF '`walkthrough_check` is `on`' "$S" || { echo "workflow-$p: the check is never mentioned"; return 1; }
    grep -qF '`task-walkthrough` → `## Check`' "$S" || { echo "workflow-$p: the check does not point at its protocol"; return 1; }
  done
}

@test "a refresh drops the commits history no longer holds, and says so as history" {
  refresh="$(awk '/^## Refreshing$/{f=1;next} /^## /{f=0} f' "$SKILL")"
  for token in 'scripts/lint-walkthrough.sh' 'no longer reachable from `HEAD`' 'is removed' '`history`'; do
    grep -qF -- "$token" <<<"$refresh" || { echo "## Refreshing does not name $token"; return 1; }
  done
  grep -qF '`history` (commits the task made are no longer in its history)' "$SKILL" \
    || { echo "the trigger vocabulary does not carry history"; return 1; }
  grep -qF 'and when a commit is gone from history' "$SKILL" \
    || { echo "the rewrite anti-pattern does not name its second exception"; return 1; }
}
