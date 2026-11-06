#!/usr/bin/env bats
# One skill holds the reader and the style rules for every task artifact.
# This suite holds its shape: the sections, the twelve style rules, the artifacts it covers.

setup() {
  ROOT="$(cd -- "$(dirname -- "$BATS_TEST_FILENAME")/../../.." && pwd)"
  SKILL="$ROOT/skills/artifact-reader/SKILL.md"
}

section() { # $1 = heading text
  awk -v h="## $1" '$0==h{f=1;next} f&&/^## /{exit} f' "$SKILL"
}

@test "the skill exists and resolves under its own name" {
  [ -f "$SKILL" ] || { echo "no skills/artifact-reader/SKILL.md"; return 1; }
  grep -q '^name: artifact-reader$' "$SKILL" || { echo "frontmatter name is not artifact-reader"; return 1; }
}

@test "the skill ships no locales" {
  [ ! -d "$ROOT/skills/artifact-reader/locales" ] || { echo "artifact-reader must not carry locales/"; return 1; }
}

@test "the five sections exist, in order" {
  got="$(grep '^## ' "$SKILL" | paste -sd'|' -)"
  [ "$got" = '## Reader|## Style|## Self-check|## Anti-patterns|## Scope' ] || { echo "headings: '$got'"; return 1; }
}

@test "Scope names all ten artifacts and the precedence sentence" {
  scope="$(section Scope)"
  for a in Walkthrough.md ManualChecks.md Done.md Plan.md Review.md Questions.md Research.md OpsChecklist.md Validation.md Docs.md; do
    grep -qF "$a" <<<"$scope" || { echo "Scope never names $a"; return 1; }
  done
  grep -qF 'wins over any brevity instruction in an agent body' <<<"$scope" \
    || { echo "Scope never says the style wins over a brevity instruction"; return 1; }
}

@test "Style carries all twelve rules by their bold lead" {
  style="$(section Style)"
  for lead in '**One fact per sentence.**' '**Meaning first, identifier in brackets.**' '**A label is never the subject.**' \
    '**Explain the basics the reader needs.**' '**A problem is a chain, not a category.**' \
    '**Every decision names the rejected alternative.**' '**Tables for comparisons and lists of cases.**' \
    '**Pictures where space or order matters.**' '**Proof is concrete.**' '**Human text on the first screen.**' \
    '**No history in the body.**' '**A blank line before every field, list and table.**'; do
    grep -qF -- "$lead" <<<"$style" || { echo "Style lacks $lead"; return 1; }
  done
}

@test "the Codex manifest hides the skill from implicit invocation" {
  grep -qF 'allow_implicit_invocation: false' "$ROOT/skills/artifact-reader/agents/openai.yaml" \
    || { echo "artifact-reader can be picked by Codex on its own"; return 1; }
}

@test "the core skills that write task artifacts point at artifact-reader" {
  for s in task-walkthrough task-documents ops-checklist; do
    grep -qF 'artifact-reader' "$ROOT/skills/$s/SKILL.md" || { echo "$s never names artifact-reader"; return 1; }
  done
}

@test "both registries of core skill names list artifact-reader" {
  grep -qF '`artifact-reader`' "$ROOT/.claude/CLAUDE.md" || { echo ".claude/CLAUDE.md does not list it"; return 1; }
  awk '/^Do \*\*not\*\* name that skill `setup`/{f=1} f' "$ROOT/docs/building-a-platform.md" | grep -qF '`artifact-reader`' \
    || { echo "the platform guide's list of core skill names does not include it"; return 1; }
}

# The Russian lines are spelled as UTF-8 bytes: a test file is not a place the i18n lint lets Cyrillic in.
@test "the i18n example shows an identifier as a reference, not as the subject" {
  f="$ROOT/conventions/i18n.md"
  bad="$(printf '`FooDataProvider` \xd0\xbf\xd0\xb5\xd1\x80\xd0\xb5\xd0\xb2\xd0\xb5\xd0\xb4\xd1\x91\xd0\xbd')"
  line1="$(printf '\xd0\x98\xd1\x81\xd1\x82\xd0\xbe\xd1\x87\xd0\xbd\xd0\xb8\xd0\xba \xd0\xb4\xd0\xb0\xd0\xbd\xd0\xbd\xd1\x8b\xd1\x85 \xd1\x81\xd0\xbf\xd0\xb8\xd1\x81\xd0\xba\xd0\xb0 (`FooDataProvider`) \xd1\x82\xd0\xb5\xd0\xbf\xd0\xb5\xd1\x80\xd1\x8c \xd1\x81\xd1\x82\xd1\x80\xd0\xbe\xd0\xb8\xd1\x82\xd1\x81\xd1\x8f \xd0\xb8\xd0\xb7 \xd0\xbc\xd0\xbe\xd0\xb4\xd0\xb5\xd0\xbb\xd0\xb8.')"
  line2="$(printf '\xd0\x9f\xd0\xbe\xd1\x8d\xd1\x82\xd0\xbe\xd0\xbc\xd1\x83 \xd0\xb2\xd1\x8b\xd0\xb4\xd0\xb5\xd0\xbb\xd0\xb5\xd0\xbd\xd0\xb8\xd0\xb5 \xd0\xb1\xd0\xbe\xd0\xbb\xd1\x8c\xd1\x88\xd0\xb5 \xd0\xbd\xd0\xb5 \xd1\x82\xd0\xb5\xd1\x80\xd1\x8f\xd0\xb5\xd1\x82\xd1\x81\xd1\x8f \xd0\xbf\xd1\x80\xd0\xb8 \xd0\xbe\xd0\xb1\xd0\xbd\xd0\xbe\xd0\xb2\xd0\xbb\xd0\xb5\xd0\xbd\xd0\xb8\xd0\xb8 \xd1\x81\xd0\xbf\xd0\xb8\xd1\x81\xd0\xba\xd0\xb0.   <- RU prose (project language)')"
  if grep -qF -- "$bad" "$f"; then echo "i18n.md still makes an identifier the subject"; return 1; fi
  grep -qxF -- "$line1" "$f" || { echo "first example line missing"; return 1; }
  grep -qxF -- "$line2" "$f" || { echo "second example line missing"; return 1; }
  grep -qF 'artifact-reader' "$f" || { echo "i18n.md never names artifact-reader"; return 1; }
}
